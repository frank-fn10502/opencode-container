#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${DEVCONTAINER_DIR}/config/opencode.json"
INIT_SCRIPT="${SCRIPT_DIR}/init-opencode-dev.sh"

IMAGE_NAME="localhost/opencode-dev:local"
CONTAINER_NAME="opencode-dev-yuta"
HOME_VOLUME="opencode-home-yuta"
STATE_VOLUME="opencode-state-yuta"

usage() {
  cat <<'USAGE'
Usage: opencode-dev [path]
       opencode-dev --uninstall
       opencode-dev --admin-help

Common usage:
  opencode-dev               Open the current directory with OpenCode.
  opencode-dev /some/project Open that project directory with OpenCode.

Commands:
  --uninstall
            Remove the opencode-dev shell profile block and installed runtime.
  --admin-help
            Show debug/admin commands and container details.
USAGE
}

admin_usage() {
  cat <<'USAGE'
Debug/Admin commands:
  opencode-dev shell
      Open a bash shell for the current directory at /workspace.

  opencode-dev status
      Show the existing opencode-dev-yuta container, if any.

  opencode-dev stop
      Stop and remove the existing opencode-dev-yuta container.

Only one container named opencode-dev-yuta is allowed at a time. If one already
exists, this script asks whether to close it. Refusing leaves it untouched and
exits.

Implementation details:
  The selected project directory is mounted into the container at /workspace.
  OpenCode runs inside a short-lived Docker container named opencode-dev-yuta.
  OpenCode state is stored in Docker named volumes, not in the project directory.
USAGE
}

ensure_external_volume() {
  local volume_name="$1"

  docker volume inspect "${volume_name}" >/dev/null 2>&1 || docker volume create "${volume_name}" >/dev/null
}

ensure_external_volumes() {
  ensure_external_volume "${HOME_VOLUME}"
  ensure_external_volume "${STATE_VOLUME}"
}

container_id() {
  docker ps -aq --filter "name=^/${CONTAINER_NAME}$" | head -n 1
}

container_running() {
  local id="$1"

  [[ -n "${id}" ]] && [[ "$(docker inspect -f '{{.State.Running}}' "${id}" 2>/dev/null || true)" == "true" ]]
}

confirm_close_existing() {
  printf '%s\n' "A container named ${CONTAINER_NAME} already exists."
  printf '%s' "Close it before starting a new ${CONTAINER_NAME}? [y/N] "
  read -r answer

  case "${answer}" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      printf '%s\n' "Aborted. The existing ${CONTAINER_NAME} container was left untouched."
      return 1
      ;;
  esac
}

remove_existing_container_if_allowed() {
  local id

  id="$(container_id)"
  if [[ -z "${id}" ]]; then
    return
  fi

  confirm_close_existing || exit 1
  if container_running "${id}"; then
    docker stop "${id}" >/dev/null
  fi
  docker rm "${id}" >/dev/null
}

resolve_project_dir() {
  local requested="$1"
  local target

  if [[ -z "${requested}" ]]; then
    target="${PWD}"
  else
    case "${requested}" in
      \~)
        target="${HOME}"
        ;;
      \~/*)
        target="${HOME}/${requested#"~/"}"
        ;;
      /*)
        target="${requested}"
        ;;
      *)
        target="${PWD}/${requested}"
        ;;
    esac
  fi

  mkdir -p "${target}"
  if [[ ! -d "${target}" ]]; then
    printf 'Path is not a directory: %s\n' "${target}" >&2
    exit 1
  fi

  (cd "${target}" && pwd -P)
}

docker_run_base() {
  local project_dir="$1"
  shift

  docker run --rm -it \
    --name "${CONTAINER_NAME}" \
    --workdir /workspace \
    --add-host host.docker.internal:host-gateway \
    --env "OLLAMA_API_KEY=${OLLAMA_API_KEY:-}" \
    --volume "${project_dir}:/workspace" \
    --volume "${CONFIG_FILE}:/home/node/.config/opencode/opencode.json:ro" \
    --volume "${HOME_VOLUME}:/home/node/.local/share/opencode" \
    --volume "${STATE_VOLUME}:/home/node/.local/state" \
    "${IMAGE_NAME}" \
    "$@"
}

run_opencode() {
  local project_dir="$1"
  shift

  docker_run_base "${project_dir}" opencode "$@"
}

run_shell() {
  local project_dir="$1"

  docker_run_base "${project_dir}" bash
}

show_status() {
  local id

  id="$(container_id)"
  if [[ -z "${id}" ]]; then
    printf 'No opencode-dev-yuta container exists.\n'
    return
  fi

  docker ps -a --filter "id=${id}" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}"
}

stop_existing() {
  local id
  id="$(container_id)"

  if [[ -z "${id}" ]]; then
    printf 'No opencode-dev-yuta container exists.\n'
    return
  fi

  if container_running "${id}"; then
    docker stop "${id}" >/dev/null
  fi
  docker rm "${id}" >/dev/null
  printf 'Removed opencode-dev-yuta container.\n'
}

uninstall_opencode_dev() {
  if [[ ! -f "${INIT_SCRIPT}" ]]; then
    printf 'Cannot find uninstall script: %s\n' "${INIT_SCRIPT}" >&2
    exit 1
  fi

  bash "${INIT_SCRIPT}" --uninstall
}

command_name="${1:-}"
case "${command_name}" in
  help|-h|--help)
    usage
    exit 0
    ;;
  --admin-help)
    admin_usage
    exit 0
    ;;
esac

case "${command_name}" in
  --uninstall)
    uninstall_opencode_dev
    ;;

  shell)
    shift || true
    ensure_external_volumes
    remove_existing_container_if_allowed
    run_shell "$(resolve_project_dir "")"
    ;;

  stop)
    stop_existing
    ;;

  status)
    show_status
    ;;

  "")
    ensure_external_volumes
    remove_existing_container_if_allowed
    run_opencode "$(resolve_project_dir "")"
    ;;

  --)
    shift || true
    ensure_external_volumes
    remove_existing_container_if_allowed
    run_opencode "$(resolve_project_dir "")" "$@"
    ;;

  *)
    project_arg="${command_name}"
    shift || true
    if [[ $# -gt 0 && "${1}" == "--" ]]; then
      shift
    fi
    ensure_external_volumes
    remove_existing_container_if_allowed
    run_opencode "$(resolve_project_dir "${project_arg}")" "$@"
    ;;
esac
