#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_OR_SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -f "${INSTALL_OR_SCRIPTS_DIR}/docker-compose.yml" ]]; then
  DEVCONTAINER_DIR="${INSTALL_OR_SCRIPTS_DIR}"
  RUNTIME_SCRIPT_DIR="${DEVCONTAINER_DIR}/runtime"
else
  DEVCONTAINER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
  RUNTIME_SCRIPT_DIR="${DEVCONTAINER_DIR}/scripts/runtime"
fi
INSTALL_DIR="${HOME}/.local/bin/opencode-dev-yuta"
INSTALL_MARKER="${INSTALL_DIR}/.opencode-dev-managed"
INSTALL_PROFILE="${INSTALL_DIR}/.profile"
IMAGE_PROFILE="${DEVCONTAINER_DIR}/image.profile"
MARKER_BEGIN="# >>> opencode-dev >>>"
MARKER_END="# <<< opencode-dev <<<"

usage() {
  cat <<'USAGE'
Usage: init-opencode-dev.sh [--profile /path/to/profile]
       init-opencode-dev.sh --uninstall [--profile /path/to/profile]

Default behavior:
  Ensure the local Docker image exists, install the opencode-dev runtime under
  ~/.local/bin/opencode-dev-yuta, and register an opencode-dev shell function in
  the detected shell profile.

Commands:
  --uninstall   Remove the shell profile block and ~/.local/bin/opencode-dev-yuta.
                After install, this is also available as opencode-dev --uninstall.

Options:
  --profile     Override the detected shell profile path.
  -h, --help    Show this help.
USAGE
}

detect_shell_profile() {
  local shell_name

  shell_name="$(basename "${SHELL:-}")"
  case "${shell_name}" in
    zsh)
      printf '%s/.zshrc' "${HOME}"
      ;;
    bash)
      if [[ "$(uname -s)" == "Darwin" ]]; then
        printf '%s/.bash_profile' "${HOME}"
      else
        printf '%s/.bashrc' "${HOME}"
      fi
      ;;
    *)
      printf '%s/.profile' "${HOME}"
      ;;
  esac
}

expand_profile_path() {
  local path="$1"

  case "${path}" in
    \~)
      printf '%s\n' "${HOME}"
      ;;
    \~/*)
      printf '%s/%s\n' "${HOME}" "${path#"~/"}"
      ;;
    *)
      printf '%s\n' "${path}"
      ;;
  esac
}

strip_installed_block() {
  local profile="$1"
  local output="$2"

  awk -v begin="${MARKER_BEGIN}" -v end="${MARKER_END}" '
    $0 == begin { skip = 1; found = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
    END { exit found ? 0 : 2 }
  ' "${profile}" > "${output}"
}

install_runtime() {
  local profile="$1"

  if [[ -e "${INSTALL_DIR}" && ! -f "${INSTALL_MARKER}" ]]; then
    printf 'Refusing to manage existing unmarked directory: %s\n' "${INSTALL_DIR}" >&2
    printf 'Move it away or remove it before installing opencode-dev.\n' >&2
    exit 1
  fi

  if [[ -f "${INSTALL_MARKER}" ]]; then
    rm -rf "${INSTALL_DIR}"
  fi

  mkdir -p "${INSTALL_DIR}/bin" "${INSTALL_DIR}/runtime" "${INSTALL_DIR}/init" "${INSTALL_DIR}/config"
  cp "${RUNTIME_SCRIPT_DIR}/opencode-dev-dispatcher.sh" "${INSTALL_DIR}/bin/opencode-dev"
  cp "${RUNTIME_SCRIPT_DIR}/opencode-dev.sh" "${INSTALL_DIR}/runtime/opencode-dev.sh"
  cp "${RUNTIME_SCRIPT_DIR}/common.sh" "${INSTALL_DIR}/runtime/common.sh"
  cp "${RUNTIME_SCRIPT_DIR}/profiles.sh" "${INSTALL_DIR}/runtime/profiles.sh"
  cp "${RUNTIME_SCRIPT_DIR}/container.sh" "${INSTALL_DIR}/runtime/container.sh"
  cp "${SCRIPT_DIR}/init-opencode-dev.sh" "${INSTALL_DIR}/init/init-opencode-dev.sh"
  cp "${SCRIPT_DIR}/install-image.sh" "${INSTALL_DIR}/init/install-image.sh"
  cp "${DEVCONTAINER_DIR}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
  cp "${DEVCONTAINER_DIR}/compose.env" "${INSTALL_DIR}/compose.env"
  cp "${DEVCONTAINER_DIR}/config/opencode.json" "${INSTALL_DIR}/config/opencode.json"
  cp "${DEVCONTAINER_DIR}/config/profile-dockerfile-guide.md" "${INSTALL_DIR}/config/profile-dockerfile-guide.md"
  cp "${DEVCONTAINER_DIR}/config/project-profile-readme.md" "${INSTALL_DIR}/config/project-profile-readme.md"
  cp "${IMAGE_PROFILE}" "${INSTALL_DIR}/image.profile"
  chmod 755 "${INSTALL_DIR}/bin/opencode-dev"
  chmod 755 "${INSTALL_DIR}/runtime/opencode-dev.sh"
  chmod 644 "${INSTALL_DIR}/runtime/common.sh"
  chmod 644 "${INSTALL_DIR}/runtime/profiles.sh"
  chmod 644 "${INSTALL_DIR}/runtime/container.sh"
  chmod 755 "${INSTALL_DIR}/init/init-opencode-dev.sh"
  chmod 755 "${INSTALL_DIR}/init/install-image.sh"
  printf '%s\n' "${profile}" > "${INSTALL_PROFILE}"
  printf 'managed by init-opencode-dev.sh\n' > "${INSTALL_MARKER}"
}

write_profile_block() {
  local output="$1"

  cat >> "${output}" <<'EOF'
# >>> opencode-dev >>>
opencode-dev() {
  "${HOME}/.local/bin/opencode-dev-yuta/bin/opencode-dev" "$@"
}
# <<< opencode-dev <<<
EOF
}

install_opencode_dev() {
  local profile="$1"
  local tmp

  bash "${SCRIPT_DIR}/install-image.sh"
  install_runtime "${profile}"

  mkdir -p "$(dirname "${profile}")"
  touch "${profile}"
  tmp="$(mktemp)"

  strip_installed_block "${profile}" "${tmp}" || true
  printf '\n' >> "${tmp}"
  write_profile_block "${tmp}"

  if cmp -s "${profile}" "${tmp}"; then
    printf 'opencode-dev is already registered in %s\n' "${profile}"
  else
    cat "${tmp}" > "${profile}"
    printf 'Registered opencode-dev in %s\n' "${profile}"
  fi

  rm -f "${tmp}"
  printf 'Installed opencode-dev runtime at %s\n' "${INSTALL_DIR}"
  printf 'Open a new shell or run: source "%s"\n' "${profile}"
}

uninstall_opencode_dev() {
  local profile="$1"
  local tmp

  if [[ -f "${profile}" ]]; then
    tmp="$(mktemp)"
    if strip_installed_block "${profile}" "${tmp}"; then
      cat "${tmp}" > "${profile}"
      printf 'Removed opencode-dev profile block from %s\n' "${profile}"
    else
      printf 'No opencode-dev profile block found in %s\n' "${profile}"
    fi
    rm -f "${tmp}"
  else
    printf 'No profile found at %s\n' "${profile}"
  fi

  if [[ -f "${INSTALL_MARKER}" ]]; then
    rm -rf "${INSTALL_DIR}"
    printf 'Removed %s\n' "${INSTALL_DIR}"
  elif [[ -e "${INSTALL_DIR}" ]]; then
    printf 'Skipped unmarked install directory at %s\n' "${INSTALL_DIR}"
  else
    printf 'No install directory found at %s\n' "${INSTALL_DIR}"
  fi
}

mode="install"
profile=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall)
      mode="uninstall"
      shift
      ;;
    --profile)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --profile\n' >&2
        exit 2
      fi
      profile="$(expand_profile_path "$2")"
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

installed_profile_or_detect() {
  if [[ -f "${INSTALL_PROFILE}" ]]; then
    sed -n '1p' "${INSTALL_PROFILE}"
  else
    detect_shell_profile
  fi
}

case "${mode}" in
  install)
    install_opencode_dev "${profile:-$(detect_shell_profile)}"
    ;;
  uninstall)
    uninstall_opencode_dev "${profile:-$(installed_profile_or_detect)}"
    ;;
esac
