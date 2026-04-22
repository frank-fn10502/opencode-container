#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VM_SCRIPT="${PROJECT_ROOT}/.devcontainer/scripts/runtime/vm/opencode-vm.sh"
VM_NAME="${OPENCODE_TEST_VM_NAME:-test-cpp}"

usage() {
  printf 'Usage: %s [--remove] [--volumes]\n' "$(basename "$0")"
  printf '\n'
  printf '  no args     Stop the existing opencode-vm test runner.\n'
  printf '  --remove    Stop and remove the test VM and its volumes.\n'
  printf '  --volumes   Accepted for old callers; opencode-vm rm always removes VM volumes.\n'
}

remove_container=0
remove_volumes=0

for arg in "$@"; do
  case "$arg" in
    --remove)
      remove_container=1
      ;;
    --volumes)
      remove_volumes=1
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

container="opencode-vm-yuta-${VM_NAME}"
if ! docker inspect "${container}" >/dev/null 2>&1; then
  printf 'No opencode-vm test runner exists: %s\n' "${VM_NAME}"
  exit 0
fi

if docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null | grep -qx true; then
  docker exec "${container}" sh -lc \
    "pkill -TERM -f 'opencode.* run ' 2>/dev/null || true; sleep 1; pkill -KILL -f 'opencode.* run ' 2>/dev/null || true" || true
fi

if [[ "${remove_container}" -eq 1 ]]; then
  bash "${VM_SCRIPT}" rm --yes "${VM_NAME}"
else
  bash "${VM_SCRIPT}" stop "${VM_NAME}"
fi
