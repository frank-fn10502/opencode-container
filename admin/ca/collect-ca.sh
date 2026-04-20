#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}"

default_targets=(
  "registry-1.docker.io:443"
  "auth.docker.io:443"
  "production.cloudflare.docker.com:443"
  "mcr.microsoft.com:443"
  "registry.npmjs.org:443"
  "pypi.org:443"
  "files.pythonhosted.org:443"
  "deb.debian.org:443"
  "security.debian.org:443"
  "packages.microsoft.com:443"
)

# 這個 script 做兩件事：
# 1. 讀取目標 host 在 TLS handshake 實際送出的 certificate chain。
# 2. 如果 chain 停在 intermediate CA，視需要沿著 AIA CA Issuers URL 找回
#    缺少的 self-signed root CA。
usage() {
  cat <<'USAGE'
Usage: admin/ca/collect-ca.sh [--target HOST[:PORT]]... [--output-dir DIR] [--no-aia] [--save-chain] [--save-leaf] [--save-chain-top]

Probe common Docker/npm/PyPI/apt TLS endpoints with:

  openssl s_client -connect HOST:PORT -servername HOST -showcerts

By default, the script saves CA certificates from the TLS handshake response,
based on Basic Constraints: CA:TRUE, and follows AIA CA Issuers URLs from the
observed chain to try to retrieve the self-signed root CA. Leaf/server
certificates are not saved as trust anchors.

Options:
  --target HOST[:PORT]
              Probe one endpoint. Repeatable. If omitted, built-in registry
              targets are used.
  --output-dir DIR
              Directory where .crt files are written.
              Default: admin/ca
  --no-aia
              Do not follow AIA CA Issuers URLs. Only save CA certificates
              observed directly in the TLS handshake response.
  --save-chain
              Save every certificate observed in each TLS response. Debug only.
  --save-leaf
              Save only the first BEGIN CERTIFICATE block from each openssl
              output. Debug only; this is usually a leaf/server certificate.
  --save-chain-top
              Save only the last certificate from each observed chain. This is
              often an intermediate CA when the root CA is not sent.
  -h, --help  Show this help.
USAGE
}

targets=()
save_chain=0
save_leaf=0
save_chain_top=0
fetch_aia=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --target\n' >&2
        exit 2
      fi
      targets+=("$2")
      shift 2
      ;;
    --output-dir)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --output-dir\n' >&2
        exit 2
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --no-aia)
      fetch_aia=0
      shift
      ;;
    --save-chain)
      save_chain=1
      shift
      ;;
    --save-leaf)
      save_leaf=1
      shift
      ;;
    --save-chain-top)
      save_chain_top=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${#targets[@]}" -eq 0 ]]; then
  targets=("${default_targets[@]}")
fi

selected_modes=$((save_chain + save_leaf + save_chain_top))
if [[ "${selected_modes}" -gt 1 ]]; then
  printf 'Use only one save mode: --save-chain, --save-leaf, or --save-chain-top.\n' >&2
  exit 2
fi

if ! command -v openssl >/dev/null 2>&1; then
  printf 'openssl command not found. Install openssl on the host, then run this script again.\n' >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

safe_name() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9_.-]/-/g'
}

split_chain() {
  local input="$1"
  local prefix="$2"

  # openssl s_client 會輸出診斷文字與 PEM block。這裡只保留
  # BEGIN/END CERTIFICATE 區塊，並依照 OpenSSL 輸出的順序寫成編號檔；
  # 一般情況下第一張會是 leaf/server certificate。
  awk -v prefix="${prefix}" '
    /-----BEGIN CERTIFICATE-----/ {
      in_cert = 1
      cert_index += 1
      file = sprintf("%s-%02d.crt", prefix, cert_index)
    }
    in_cert {
      print > file
    }
    /-----END CERTIFICATE-----/ {
      in_cert = 0
      close(file)
    }
    END {
      print cert_index + 0
    }
  ' "${input}"
}

describe_cert() {
  local cert="$1"
  local subject issuer fingerprint

  subject="$(openssl x509 -in "${cert}" -noout -subject 2>/dev/null | sed 's/^subject=//')"
  issuer="$(openssl x509 -in "${cert}" -noout -issuer 2>/dev/null | sed 's/^issuer=//')"
  fingerprint="$(openssl x509 -in "${cert}" -noout -fingerprint -sha256 2>/dev/null | sed 's/^sha256 Fingerprint=//; s/^SHA256 Fingerprint=//')"

  printf '    subject: %s\n' "${subject:-unknown}"
  printf '    issuer:  %s\n' "${issuer:-unknown}"
  printf '    sha256:  %s\n' "${fingerprint:-unknown}"
}

cert_subject() {
  openssl x509 -in "$1" -noout -subject 2>/dev/null | sed 's/^subject=//'
}

cert_issuer() {
  openssl x509 -in "$1" -noout -issuer 2>/dev/null | sed 's/^issuer=//'
}

cert_is_ca() {
  local cert="$1"
  # CA trust anchor 必須是 CA certificate。leaf/server certificate 通常是
  # CA:FALSE，不應該被安裝成可重複使用的公司 CA。
  openssl x509 -in "${cert}" -noout -text 2>/dev/null \
    | grep -A2 'Basic Constraints' \
    | grep -q 'CA:TRUE'
}

cert_is_self_signed() {
  local cert="$1"
  local subject issuer

  # self-signed CA 的 subject 與 issuer 會相同；再搭配 CA:TRUE，才是我們要放進
  # Docker image trust store 的 root CA 形狀。
  subject="$(cert_subject "${cert}")"
  issuer="$(cert_issuer "${cert}")"
  [[ -n "${subject}" && "${subject}" == "${issuer}" ]]
}

extract_aia_ca_issuers_uri() {
  local cert="$1"
  # AIA CA Issuers 通常指向簽發目前憑證的 issuer certificate。若 TLS handshake
  # 沒有送出 root CA，從觀察到的 intermediate CA 往上追 AIA 有機會取回 root CA。
  openssl x509 -in "${cert}" -noout -text 2>/dev/null \
    | sed -n '/Authority Information Access/,/^[[:space:]]*$/p' \
    | grep -i 'CA Issuers' \
    | grep -oE 'URI:[^ ]+' \
    | head -n 1 \
    | sed 's/^URI://'
}

download_url() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 20 -o "${output}" "${url}"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -q --timeout=20 -O "${output}" "${url}"
    return
  fi

  return 1
}

to_pem() {
  local input="$1"
  local output="$2"

  # CA Issuers URL 回傳格式不固定：可能是 PEM、DER，也可能是 PKCS7 bundle。
  # 後續一律用 OpenSSL 檢查 PEM，所以先把下載內容 normalize 成 PEM。
  if head -c 40 "${input}" | grep -q 'BEGIN CERTIFICATE'; then
    cp "${input}" "${output}"
    return 0
  fi

  if openssl x509 -inform DER -in "${input}" -outform PEM -out "${output}" 2>/dev/null; then
    return 0
  fi

  if openssl pkcs7 -inform DER -in "${input}" -print_certs -out "${output}" 2>/dev/null; then
    return 0
  fi

  return 1
}

save_root_if_new() {
  local root_pem="$1"
  local fingerprint output

  # root CA 檔名用 SHA256 fingerprint，讓不同 registry 追到同一張 root CA 時
  # 可以自然去重。
  fingerprint="$(openssl x509 -in "${root_pem}" -noout -fingerprint -sha256 2>/dev/null \
    | sed 's/.*=//; s/://g' \
    | tr '[:upper:]' '[:lower:]')"

  if [[ -z "${fingerprint}" ]]; then
    return 1
  fi

  output="${OUTPUT_DIR}/root-ca-${fingerprint}.crt"
  if [[ ! -f "${output}" ]]; then
    cp "${root_pem}" "${output}"
    printf '  Saved root CA from AIA: %s\n' "${output#${SCRIPT_DIR}/}"
    describe_cert "${output}"
    return 0
  fi

  printf '  Root CA from AIA already exists: %s\n' "${output#${SCRIPT_DIR}/}"
  return 0
}

fetch_root_via_aia() {
  local start_cert="$1"
  local label="$2"
  local current="$start_cert"
  local depth=0
  local max_depth=8
  local url raw_download pem_download

  # 沿著 issuer -> issuer 往上走，直到遇到 CA:TRUE 的 self-signed cert。
  # 設定 max_depth，避免錯誤或循環的 AIA chain 無限執行。
  while [[ "${depth}" -lt "${max_depth}" ]]; do
    if cert_is_self_signed "${current}" && cert_is_ca "${current}"; then
      save_root_if_new "${current}"
      return $?
    fi

    url="$(extract_aia_ca_issuers_uri "${current}")"
    if [[ -z "${url}" ]]; then
      printf '  AIA CA Issuers URL not found for %s at depth %d.\n' "${label}" "${depth}" >&2
      return 1
    fi

    case "${url}" in
      http://*|https://*)
        ;;
      ldap://*|ldap:/*)
        printf '  AIA CA Issuers uses LDAP and cannot be downloaded by this script: %s\n' "${url}" >&2
        printf '  Export the company root CA from OS/browser trust store or ask IT for a .crt file.\n' >&2
        return 1
        ;;
      *)
        printf '  Unsupported AIA CA Issuers URI scheme: %s\n' "${url}" >&2
        return 1
        ;;
    esac

    raw_download="${tmp_dir}/aia-${label}-${depth}.raw"
    pem_download="${tmp_dir}/aia-${label}-${depth}.pem"

    printf '  Following AIA for %s: %s\n' "${label}" "${url}"
    if ! download_url "${url}" "${raw_download}"; then
      printf '  Failed to download AIA URL: %s\n' "${url}" >&2
      return 1
    fi

    if ! to_pem "${raw_download}" "${pem_download}"; then
      printf '  Failed to decode AIA certificate from: %s\n' "${url}" >&2
      return 1
    fi

    current="${pem_download}"
    depth=$((depth + 1))
  done

  printf '  Reached maximum AIA depth for %s without finding a root CA.\n' "${label}" >&2
  return 1
}

copy_first_cert_only() {
  local prefix="$1"
  local output="$2"
  local first=""

  for cert in "${prefix}"-*.crt; do
    [[ -f "${cert}" ]] || continue
    first="${cert}"
    break
  done

  if [[ -z "${first}" ]]; then
    return 1
  fi

  cp "${first}" "${output}"
}

copy_last_cert_only() {
  local prefix="$1"
  local output="$2"
  local last=""

  for cert in "${prefix}"-*.crt; do
    [[ -f "${cert}" ]] || continue
    last="${cert}"
  done

  if [[ -z "${last}" ]]; then
    return 1
  fi

  cp "${last}" "${output}"
}

total_written=0
found_self_signed=0
found_intermediate=0
aia_candidates=()

printf 'Writing observed certificates to: %s\n' "${OUTPUT_DIR}"

for target in "${targets[@]}"; do
  host="${target%%:*}"
  port="${target##*:}"
  if [[ "${host}" == "${port}" ]]; then
    port="443"
  fi

  raw="${tmp_dir}/$(safe_name "${host}-${port}").pem"
  err="${tmp_dir}/$(safe_name "${host}-${port}").err"
  prefix="${OUTPUT_DIR}/auto-$(safe_name "${host}-${port}")"

  printf 'Probing %s:%s\n' "${host}" "${port}"
  # 許多 registry 位在共享 TLS endpoint 後方，所以需要 SNI (-servername) 才會拿到
  # 正確的 certificate chain。這裡只解析輸出內容，不要求 OpenSSL verification 成功。
  if ! openssl s_client -connect "${host}:${port}" -servername "${host}" -showcerts < /dev/null > "${raw}" 2> "${err}"; then
    printf '  Failed to read certificate chain from %s:%s\n' "${host}" "${port}" >&2
    sed 's/^/  /' "${err}" >&2
    continue
  fi

  rm -f "${prefix}"-*.crt
  count="$(split_chain "${raw}" "${prefix}")"

  if [[ "${count}" -eq 0 ]]; then
    printf '  No certificates were found in the TLS response.\n' >&2
    continue
  fi

  original_certs=()
  for cert in "${prefix}"-[0-9][0-9].crt; do
    [[ -f "${cert}" ]] || continue
    original_certs+=("${cert}")
  done

  if [[ "${save_leaf}" -eq 1 ]]; then
    output="${prefix}-first.crt"
    rm -f "${output}"
    if ! copy_first_cert_only "${prefix}" "${output}"; then
      printf '  Failed to save first certificate.\n' >&2
      continue
    fi
    rm -f "${prefix}"-[0-9][0-9].crt
    count=1
    printf '  Wrote leaf/debug certificate only.\n'
  elif [[ "${save_chain_top}" -eq 1 ]]; then
    output="${prefix}-chain-top.crt"
    rm -f "${output}"
    if ! copy_last_cert_only "${prefix}" "${output}"; then
      printf '  Failed to save chain-top certificate.\n' >&2
      continue
    fi
    rm -f "${prefix}"-[0-9][0-9].crt
    count=1
    printf '  Wrote chain-top certificate only.\n'
  elif [[ "${save_chain}" -eq 1 ]]; then
    printf '  Wrote full observed chain: %s certificate(s).\n' "${count}"
  else
    ca_count=0
    for cert in "${original_certs[@]}"; do
      [[ -f "${cert}" ]] || continue
      # 移除 output directory 裡的 leaf 前，先留一份暫存檔給 AIA 使用。
      # 某些 corporate TLS inspection 環境中，leaf 反而可能是唯一帶有可用
      # AIA CA Issuers URL 的憑證。
      if [[ "${fetch_aia}" -eq 1 ]]; then
        aia_copy="${tmp_dir}/aia-candidate-$(safe_name "${host}-${port}")-${ca_count}-$(basename "${cert}")"
        cp "${cert}" "${aia_copy}"
        aia_candidates+=("${aia_copy}:$(safe_name "${host}-${port}")")
      fi
      if cert_is_ca "${cert}"; then
        ca_count=$((ca_count + 1))
        mv "${cert}" "${prefix}-ca-${ca_count}.crt"
      else
        rm -f "${cert}"
      fi
    done
    count="${ca_count}"
    if [[ "${count}" -eq 0 ]]; then
      printf '  No CA:TRUE certificate was found in this TLS response.\n' >&2
      continue
    fi
    printf '  Wrote observed CA certificate(s): %s\n' "${count}"
  fi

  total_written=$((total_written + count))

  for cert in "${prefix}"-*.crt; do
    [[ -f "${cert}" ]] || continue
    printf '  %s\n' "${cert#${SCRIPT_DIR}/}"
    describe_cert "${cert}"

    if cert_is_self_signed "${cert}"; then
      found_self_signed=1
    elif cert_is_ca "${cert}"; then
      found_intermediate=1
    fi
  done
done

if [[ "${total_written}" -eq 0 ]]; then
  printf 'No certificates were collected.\n' >&2
  if [[ "${fetch_aia}" -eq 0 ]]; then
    exit 1
  fi
fi

printf 'Collected %d certificate(s).\n' "${total_written}"

if [[ "${fetch_aia}" -eq 1 && "${save_chain}" -eq 0 && "${save_leaf}" -eq 0 && "${save_chain_top}" -eq 0 && "${found_self_signed}" -eq 0 ]]; then
  printf 'Trying AIA CA Issuers URLs to retrieve a self-signed root CA.\n'

  # AIA 下載需要 HTTP client。這裡刻意讓它是 optional：沒有 curl/wget 時，
  # script 仍會保留 TLS handshake 中觀察到的 CA:TRUE 憑證，再提示使用者手動匯出
  # root CA。
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    printf 'Cannot fetch AIA URLs: neither curl nor wget is available.\n' >&2
  else
    for candidate in "${aia_candidates[@]}"; do
      cert_path="${candidate%%:*}"
      cert_label="${candidate#*:}"
      if fetch_root_via_aia "${cert_path}" "${cert_label}"; then
        found_self_signed=1
        total_written=$((total_written + 1))
        break
      fi
    done
  fi
fi

if [[ "${total_written}" -eq 0 ]]; then
  printf 'No CA certificates or root CA certificates were collected.\n' >&2
  exit 1
fi

if [[ "${save_leaf}" -eq 1 ]]; then
  printf 'WARNING: --save-leaf is for debugging. Leaf/server certificates are usually not suitable as CA trust anchors.\n' >&2
elif [[ "${found_self_signed}" -eq 0 ]]; then
  if [[ "${found_intermediate}" -eq 1 ]]; then
    printf 'Only intermediate CA certificate(s) were observed; no self-signed root CA was sent in the TLS response.\n' >&2
  else
    printf 'No self-signed root CA was observed in the TLS response.\n' >&2
  fi
  printf 'Export the company root CA from your OS/browser trust store or ask IT for it, then place it under admin/ca/ manually.\n' >&2
fi

printf 'Next step: run ./admin/ca/build-ca-image.sh\n'
