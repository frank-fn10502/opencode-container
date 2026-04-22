#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VM_SCRIPT="${PROJECT_ROOT}/.devcontainer/scripts/runtime/vm/opencode-vm.sh"
SETUP_SCRIPT="${SCRIPT_DIR}/setup_opencode_vm_runner.sh"
PYTHON_SCRIPT="${SCRIPT_DIR}/run_cpp_opencode_monitor.py"
DUMP_DIR="${PROJECT_ROOT}/.tmp/cpptest"

vm_name="${OPENCODE_TEST_VM_NAME:-test-cpp}"
port_base="${OPENCODE_TEST_VM_PORT_BASE:-2600}"
container_name="opencode-vm-yuta-${vm_name}"

usage() {
  printf 'Usage: %s [--name NAME] [--port-base N] [python monitor args...]\n' "$(basename "$0")"
  printf '\n'
  printf 'Ensures the test opencode-vm exists, runs the C++ OpenCode monitor, then dumps /workspace to .tmp/cpptest.\n'
}

python_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      [[ $# -ge 2 ]] || { printf 'Missing value for --name.\n' >&2; exit 2; }
      vm_name="$2"
      container_name="opencode-vm-yuta-${vm_name}"
      shift 2
      ;;
    --port-base)
      [[ $# -ge 2 ]] || { printf 'Missing value for --port-base.\n' >&2; exit 2; }
      port_base="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      python_args+=("$1")
      shift
      ;;
  esac
done

if [[ ! -f "${VM_SCRIPT}" ]]; then
  printf 'opencode-vm script not found: %s\n' "${VM_SCRIPT}" >&2
  exit 2
fi

if [[ ! -f "${SETUP_SCRIPT}" ]]; then
  printf 'setup script not found: %s\n' "${SETUP_SCRIPT}" >&2
  exit 2
fi

if [[ ! -f "${PYTHON_SCRIPT}" ]]; then
  printf 'Python monitor script not found: %s\n' "${PYTHON_SCRIPT}" >&2
  exit 2
fi

if ! docker inspect "${container_name}" >/dev/null 2>&1; then
  printf 'Test VM does not exist; setting up %s.\n' "${vm_name}"
  bash "${SETUP_SCRIPT}" --name "${vm_name}" --port-base "${port_base}"
elif ! docker inspect -f '{{.State.Running}}' "${container_name}" 2>/dev/null | grep -qx true; then
  printf 'Test VM exists but is stopped; starting %s.\n' "${vm_name}"
  bash "${VM_SCRIPT}" start "${vm_name}" --port-base "${port_base}"
else
  printf 'Using existing test VM: %s\n' "${vm_name}"
fi

python3 "${PYTHON_SCRIPT}" \
  --vm-name "${vm_name}" \
  --port-base "${port_base}" \
  --skip-setup \
  "${python_args[@]}"

bash "${VM_SCRIPT}" dump "${vm_name}" "${DUMP_DIR}"
printf 'Dumped test VM workspace back to %s\n' "${DUMP_DIR}"
printf 'Test VM is still running. Stop it manually with: test_opencode/stop_opencode_runner.sh\n'
