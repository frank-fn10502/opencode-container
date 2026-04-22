#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VM_SCRIPT="${PROJECT_ROOT}/.devcontainer/scripts/runtime/vm/opencode-vm.sh"
SETUP_SCRIPT="${SCRIPT_DIR}/setup_opencode_vm_runner.sh"
PYTHON_SCRIPT="${SCRIPT_DIR}/run_cpp_opencode_monitor.py"

VM_NAME="test-cpp"
PORT_BASE="2600"
MODEL="ollama/qwen3.5:9b"
ITERATIONS="1"
VM_DUMP_SOURCE="/workspace/cpptest"
HOST_DUMP_DIST="${PROJECT_ROOT}/.tmp/cpptest"

usage() {
  printf 'Usage: %s\n' "$(basename "$0")"
  printf '\n'
  printf 'Ensures the test opencode-vm exists, runs the C++ OpenCode monitor, then dumps the configured VM source to .tmp/cpptest.\n'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 0 ]]; then
  usage >&2
  exit 2
fi

container_name="opencode-vm-yuta-${VM_NAME}"

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
  printf 'Test VM does not exist; setting up %s.\n' "${VM_NAME}"
  bash "${SETUP_SCRIPT}" --name "${VM_NAME}" --port-base "${PORT_BASE}"
elif ! docker inspect -f '{{.State.Running}}' "${container_name}" 2>/dev/null | grep -qx true; then
  printf 'Test VM exists but is stopped; starting %s.\n' "${VM_NAME}"
  bash "${VM_SCRIPT}" start "${VM_NAME}" --port-base "${PORT_BASE}"
else
  printf 'Using existing test VM: %s\n' "${VM_NAME}"
fi

if ! bash "${VM_SCRIPT}" exec "${VM_NAME}" -- test -d "${VM_DUMP_SOURCE}" >/dev/null 2>&1; then
  printf 'Test project is missing in VM; importing %s to %s.\n' "${HOST_DUMP_DIST}" "${VM_DUMP_SOURCE}"
  bash "${VM_SCRIPT}" import "${VM_NAME}" --src "${HOST_DUMP_DIST}" --dist "${VM_DUMP_SOURCE}"
fi

python3 "${PYTHON_SCRIPT}" \
  --vm-name "${VM_NAME}" \
  --port-base "${PORT_BASE}" \
  --skip-setup \
  --workspace-dir "${VM_DUMP_SOURCE}" \
  --model "${MODEL}" \
  --iterations "${ITERATIONS}"

bash "${VM_SCRIPT}" dump "${VM_NAME}" --src "${VM_DUMP_SOURCE}" --dist "${HOST_DUMP_DIST}"
printf 'Dumped test VM source %s back to %s\n' "${VM_DUMP_SOURCE}" "${HOST_DUMP_DIST}"
printf 'Test VM is still running. Stop it manually with: test_opencode/stop_opencode_runner.sh\n'
