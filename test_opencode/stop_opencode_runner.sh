#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/.devcontainer/compose.yaml"
RUNNER_SERVICE="opencode-cpp-runner"
RUNNER_CONTAINER="devcontainer-opencode-cpp-runner-1"

usage() {
  printf 'Usage: %s [--remove] [--volumes]\n' "$(basename "$0")"
  printf '\n'
  printf '  no args     Stop the existing opencode runner container.\n'
  printf '  --remove    Stop and remove the runner container.\n'
  printf '  --volumes   With --remove, also remove runner volumes.\n'
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

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  printf 'Compose file not found: %s\n' "${COMPOSE_FILE}" >&2
  exit 2
fi

runner_id=""
if docker inspect "${RUNNER_CONTAINER}" >/dev/null 2>&1; then
  runner_id="${RUNNER_CONTAINER}"
else
  runner_id="$(
    docker compose -f "${COMPOSE_FILE}" ps -q -a "${RUNNER_SERVICE}" 2>/dev/null || true
  )"
fi

if [[ -z "${runner_id}" ]]; then
  printf 'No opencode runner container exists.\n'
  exit 0
fi

if docker inspect -f '{{.State.Running}}' "${runner_id}" 2>/dev/null | grep -qx true; then
  docker exec "${runner_id}" sh -lc \
    "pkill -TERM -f 'opencode.* run ' 2>/dev/null || true; sleep 1; pkill -KILL -f 'opencode.* run ' 2>/dev/null || true"
fi

if [[ "${remove_container}" -eq 1 ]]; then
  rm_args=(rm --force --stop)
  if [[ "${remove_volumes}" -eq 1 ]]; then
    rm_args+=(-v)
  fi
  docker compose -f "${COMPOSE_FILE}" "${rm_args[@]}" "${RUNNER_SERVICE}"
  printf 'Removed opencode runner: %s\n' "${runner_id}"
else
  docker compose -f "${COMPOSE_FILE}" stop "${RUNNER_SERVICE}"
  printf 'Stopped opencode runner: %s\n' "${runner_id}"
fi
