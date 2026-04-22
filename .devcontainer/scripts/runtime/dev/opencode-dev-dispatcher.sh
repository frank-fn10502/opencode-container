#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin/opencode-dev-yuta"
INSTALL_MARKER="${INSTALL_DIR}/.opencode-dev-managed"
OPENCODE_DEV_SCRIPT="${INSTALL_DIR}/runtime/dev/opencode-dev.sh"

not_installed() {
  printf '%s\n' "opencode-dev is not installed at ${INSTALL_DIR}." >&2
  printf '%s\n' "Run ./init.sh again to reinstall it." >&2
  exit 127
}

[[ -f "${INSTALL_MARKER}" && -f "${OPENCODE_DEV_SCRIPT}" ]] || not_installed
exec bash "${OPENCODE_DEV_SCRIPT}" "$@"
