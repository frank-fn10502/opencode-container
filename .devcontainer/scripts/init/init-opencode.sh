#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=init-common.sh
source "${SCRIPT_DIR}/init-common.sh"
# shellcheck source=init-opencode-dev.sh
source "${SCRIPT_DIR}/init-opencode-dev.sh"
# shellcheck source=init-opencode-vm.sh
source "${SCRIPT_DIR}/init-opencode-vm.sh"

usage() {
  cat <<'USAGE'
Usage: init-opencode.sh [--profile /path/to/profile]
       init-opencode.sh --uninstall [--profile /path/to/profile]

Default behavior:
  Ensure the local Docker images exist, install the opencode-dev and opencode-vm
  runtimes under ~/.local/bin/opencode-dev-yuta, and register both shell
  functions in the detected shell profile.

Commands:
  --uninstall   Remove the shell profile block and ~/.local/bin/opencode-dev-yuta.
                After install, this is also available as opencode-dev --uninstall.

Options:
  --profile     Override the detected shell profile path.
  -h, --help    Show this help.
USAGE
}

write_profile_block() {
  local output="$1"

  cat >> "${output}" <<'EOF'
# >>> opencode-dev >>>
opencode-dev() {
  "${HOME}/.local/bin/opencode-dev-yuta/bin/opencode-dev" "$@"
}
opencode-vm() {
  "${HOME}/.local/bin/opencode-dev-yuta/bin/opencode-vm" "$@"
}
# <<< opencode-dev <<<
EOF
}

install_opencode() {
  local profile="$1"
  local previous_profile
  local tmp

  bash "${SCRIPT_DIR}/install-image.sh"

  previous_profile="$(installed_profile_or_detect)"
  remove_profile_block "${previous_profile}"
  if [[ "${profile}" != "${previous_profile}" ]]; then
    remove_profile_block "${profile}"
  fi
  reset_install_dir
  install_common_runtime
  install_dev_runtime
  install_vm_runtime
  write_install_marker "${profile}"

  mkdir -p "$(dirname "${profile}")"
  touch "${profile}"
  tmp="$(mktemp)"

  strip_installed_block "${profile}" "${tmp}" || true
  printf '\n' >> "${tmp}"
  write_profile_block "${tmp}"

  if cmp -s "${profile}" "${tmp}"; then
    printf 'opencode-dev and opencode-vm are already registered in %s\n' "${profile}"
  else
    cat "${tmp}" > "${profile}"
    printf 'Registered opencode-dev and opencode-vm in %s\n' "${profile}"
  fi

  rm -f "${tmp}"
  printf '\n'
  printf 'opencode-dev/opencode-vm initialization completed.\n'
  printf 'Installed runtime: %s\n' "${INSTALL_DIR}"
  printf '\n'
  printf 'To use opencode-dev and opencode-vm in this terminal, run:\n'
  printf '  source "%s"\n' "${profile}"
  printf '\n'
  printf 'Or open a new terminal.\n'
}

uninstall_opencode() {
  local profile="$1"

  remove_profile_block "${profile}"

  if remove_managed_install_dir; then
    printf 'Removed %s\n' "${INSTALL_DIR}"
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

case "${mode}" in
  install)
    install_opencode "${profile:-$(detect_shell_profile)}"
    ;;
  uninstall)
    uninstall_opencode "${profile:-$(installed_profile_or_detect)}"
    ;;
esac
