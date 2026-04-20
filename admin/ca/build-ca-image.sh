#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CA_DIR="${SCRIPT_DIR}"

usage() {
  cat <<'USAGE'
Usage: admin/ca/build-ca-image.sh [--dockerfile FILE] [--build-arg KEY=VALUE]...

Build the CA-aware OpenCode dev image. Place one or more .crt files under
admin/ca/ before running this script.

Options:
  --dockerfile FILE
              Build from a Dockerfile under .devcontainer/.
              Default: Dockerfile
  --build-arg KEY=VALUE
              Pass through one build arg. Repeatable.
  -h, --help  Show this help.
USAGE
}

dockerfile_name="Dockerfile"
build_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dockerfile)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --dockerfile\n' >&2
        exit 2
      fi
      dockerfile_name="$2"
      shift 2
      ;;
    --build-arg)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --build-arg\n' >&2
        exit 2
      fi
      build_args+=("--build-arg" "$2")
      shift 2
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

crt_files=()
for candidate in "${CA_DIR}"/*.crt; do
  if [[ -f "${candidate}" ]]; then
    crt_files+=("${candidate}")
  fi
done

if [[ "${#crt_files[@]}" -eq 0 ]]; then
  printf 'Cannot build CA image: no .crt files were found under %s\n' "${CA_DIR}" >&2
  printf 'Place company CA certificate files under admin/ca/, then run this script again.\n' >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
bundle="${tmp_dir}/company-ca.crt"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

for crt in "${crt_files[@]}"; do
  cat "${crt}" >> "${bundle}"
  printf '\n' >> "${bundle}"
done

ca_b64="$(base64 < "${bundle}" | tr -d '\n')"

printf 'Using CA certificates:\n'
for crt in "${crt_files[@]}"; do
  printf '  %s\n' "${crt#${SCRIPT_DIR}/}"
done

build_cmd=(
  "${ADMIN_DIR}/build-image.sh"
  --dockerfile "${dockerfile_name}"
  --build-arg "COMPANY_CA_CERT_B64=${ca_b64}"
)

if (( ${#build_args[@]} > 0 )); then
  build_cmd+=("${build_args[@]}")
fi

"${build_cmd[@]}"
