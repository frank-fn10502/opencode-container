#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPENCODE_DEV_SCRIPT="${SCRIPT_DIR}/opencode-dev.sh"
MARKER_BEGIN="# >>> opencode-dev >>>"
MARKER_END="# <<< opencode-dev <<<"

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

install_shell_function() {
  local profile="$1"
  local tmp

  mkdir -p "$(dirname "${profile}")"
  touch "${profile}"
  tmp="$(mktemp)"

  awk -v begin="${MARKER_BEGIN}" -v end="${MARKER_END}" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "${profile}" > "${tmp}"

  {
    cat "${tmp}"
    printf '\n%s\n' "${MARKER_BEGIN}"
    printf 'opencode-dev() {\n'
    printf '  "%s" "$@"\n' "${OPENCODE_DEV_SCRIPT}"
    printf '}\n'
    printf '%s\n' "${MARKER_END}"
  } > "${profile}"

  rm -f "${tmp}"
}

chmod +x "${OPENCODE_DEV_SCRIPT}"

profile="${1:-$(detect_shell_profile)}"
install_shell_function "${profile}"

printf 'Registered opencode-dev in %s\n' "${profile}"
printf 'Open a new shell or run: source "%s"\n' "${profile}"
