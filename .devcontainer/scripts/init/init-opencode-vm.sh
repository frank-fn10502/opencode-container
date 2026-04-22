install_vm_runtime() {
  mkdir -p "${INSTALL_DIR}/bin" "${INSTALL_DIR}/runtime/vm"

  cp "${INIT_RUNTIME_SCRIPT_DIR}/vm/opencode-vm-dispatcher.sh" "${INSTALL_DIR}/bin/opencode-vm"
  cp "${INIT_RUNTIME_SCRIPT_DIR}/vm/opencode-vm.sh" "${INSTALL_DIR}/runtime/vm/opencode-vm.sh"

  chmod 755 "${INSTALL_DIR}/bin/opencode-vm"
  chmod 755 "${INSTALL_DIR}/runtime/vm/opencode-vm.sh"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'init-opencode-vm.sh is an init module. Run ./init.sh instead.\n' >&2
  exit 2
fi
