install_dev_runtime() {
  mkdir -p "${INSTALL_DIR}/bin" "${INSTALL_DIR}/runtime/dev"

  cp "${INIT_RUNTIME_SCRIPT_DIR}/dev/opencode-dev-dispatcher.sh" "${INSTALL_DIR}/bin/opencode-dev"
  cp "${INIT_RUNTIME_SCRIPT_DIR}/dev/opencode-dev.sh" "${INSTALL_DIR}/runtime/dev/opencode-dev.sh"
  cp "${INIT_RUNTIME_SCRIPT_DIR}/dev/profiles.sh" "${INSTALL_DIR}/runtime/dev/profiles.sh"
  cp "${INIT_RUNTIME_SCRIPT_DIR}/dev/container.sh" "${INSTALL_DIR}/runtime/dev/container.sh"
  cp "${INIT_RUNTIME_SCRIPT_DIR}/dev/image.sh" "${INSTALL_DIR}/runtime/dev/image.sh"

  chmod 755 "${INSTALL_DIR}/bin/opencode-dev"
  chmod 755 "${INSTALL_DIR}/runtime/dev/opencode-dev.sh"
  chmod 644 "${INSTALL_DIR}/runtime/dev/profiles.sh"
  chmod 644 "${INSTALL_DIR}/runtime/dev/container.sh"
  chmod 755 "${INSTALL_DIR}/runtime/dev/image.sh"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'init-opencode-dev.sh is an init module. Run ./init.sh instead.\n' >&2
  exit 2
fi
