#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VM_SCRIPT="${PROJECT_ROOT}/.devcontainer/scripts/runtime/vm/opencode-vm.sh"
SOURCE_DIR="${PROJECT_ROOT}/.tmp/cpptest"
VM_IMPORT_DIST="${OPENCODE_TEST_VM_IMPORT_DIST:-/workspace/cpptest}"

vm_name="${OPENCODE_TEST_VM_NAME:-test-cpp}"
port_base="${OPENCODE_TEST_VM_PORT_BASE:-2600}"
reset_vm="${OPENCODE_TEST_VM_RESET:-1}"

usage() {
  printf 'Usage: %s [--name NAME] [--port-base N] [--keep-existing]\n' "$(basename "$0")"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      [[ $# -ge 2 ]] || { printf 'Missing value for --name.\n' >&2; exit 2; }
      vm_name="$2"
      shift 2
      ;;
    --port-base)
      [[ $# -ge 2 ]] || { printf 'Missing value for --port-base.\n' >&2; exit 2; }
      port_base="$2"
      shift 2
      ;;
    --keep-existing)
      reset_vm=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "${VM_SCRIPT}" ]]; then
  printf 'opencode-vm script not found: %s\n' "${VM_SCRIPT}" >&2
  exit 2
fi

if [[ ! -d "${SOURCE_DIR}" ]]; then
  printf 'C++ test source directory not found: %s\n' "${SOURCE_DIR}" >&2
  exit 2
fi

if [[ "${reset_vm}" == "1" ]]; then
  bash "${VM_SCRIPT}" rm --yes "${vm_name}" >/dev/null 2>&1 || true
fi

bash "${VM_SCRIPT}" create "${vm_name}" --port-base "${port_base}"
bash "${VM_SCRIPT}" import "${vm_name}" --src "${SOURCE_DIR}" --dist "${VM_IMPORT_DIST}"
bash "${VM_SCRIPT}" start "${vm_name}" --port-base "${port_base}"
bash "${VM_SCRIPT}" exec "${vm_name}" -- mkdir -p "${VM_IMPORT_DIST}/.opencode-test-results"

printf 'Ready opencode-vm test runner: %s\n' "${vm_name}"
