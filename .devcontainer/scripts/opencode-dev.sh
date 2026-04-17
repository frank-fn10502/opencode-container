#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${DEVCONTAINER_DIR}/docker-compose.yml"
COMPOSE_ENV="${DEVCONTAINER_DIR}/compose.env"
INIT_SCRIPT="${SCRIPT_DIR}/init-opencode-dev.sh"

CONTAINER_NAME="opencode-dev-yuta"

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
  The Docker image is fixed by compose.env as OPENCODE_DEV_IMAGE.
  Container settings are defined in docker-compose.yml.
  The selected project directory is mounted into the container at /workspace.
  OpenCode runs inside a short-lived Docker container named opencode-dev-yuta.
  OpenCode state is stored in Docker named volumes, not in the project directory.
USAGE
}

ensure_compose_env() {
  if [[ ! -f "${COMPOSE_ENV}" ]]; then
    printf 'Cannot find compose env: %s\n' "${COMPOSE_ENV}" >&2
    printf 'Run ./init.sh to install opencode-dev with a fixed image setting.\n' >&2
    exit 1
  fi

  if ! grep -Eq '^OPENCODE_DEV_IMAGE=.+:.+' "${COMPOSE_ENV}"; then
    printf 'compose.env does not contain a fixed OPENCODE_DEV_IMAGE value: %s\n' "${COMPOSE_ENV}" >&2
    printf 'Run ./init.sh after placing the image tar under .docker_imgs/.\n' >&2
    exit 1
  fi
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

compose_run_base() {
  local project_dir="$1"
  shift

  ensure_compose_env

  OPENCODE_DEV_WORKSPACE="${project_dir}" \
  docker compose \
    --env-file "${COMPOSE_ENV}" \
    --file "${COMPOSE_FILE}" \
    run \
    --rm \
    --name "${CONTAINER_NAME}" \
    opencode \
    "$@"
}

run_opencode() {
  local project_dir="$1"
  shift

  compose_run_base "${project_dir}" opencode "$@"
}

run_shell() {
  local project_dir="$1"

  compose_run_base "${project_dir}" bash
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
    remove_existing_container_if_allowed
    run_opencode "$(resolve_project_dir "")"
    ;;

  --)
    shift || true
    remove_existing_container_if_allowed
    run_opencode "$(resolve_project_dir "")" "$@"
    ;;

  *)
    project_arg="${command_name}"
    shift || true
    if [[ $# -gt 0 && "${1}" == "--" ]]; then
      shift
    fi
    remove_existing_container_if_allowed
    run_opencode "$(resolve_project_dir "${project_arg}")" "$@"
    ;;
esac
