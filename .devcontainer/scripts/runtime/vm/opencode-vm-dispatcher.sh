#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin/opencode-dev-yuta"
INSTALL_MARKER="${INSTALL_DIR}/.opencode-dev-managed"
OPENCODE_VM_SCRIPT="${INSTALL_DIR}/runtime/vm/opencode-vm.sh"

not_installed() {
  printf '%s\n' "opencode-vm is not installed at ${INSTALL_DIR}." >&2
  printf '%s\n' "Run init-opencode-dev.sh again to reinstall it." >&2
  exit 127
}

[[ -f "${INSTALL_MARKER}" && -f "${OPENCODE_VM_SCRIPT}" ]] || not_installed
exec bash "${OPENCODE_VM_SCRIPT}" "$@"
