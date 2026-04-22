#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../common.sh
source "${SCRIPT_DIR}/../common.sh"
# shellcheck source=../dev/profiles.sh
source "${SCRIPT_DIR}/../dev/profiles.sh"

VM_DEFAULT_NAME="default"
VM_PREFIX="opencode-vm-yuta"
VM_INTERNAL_PORT="8001"

usage() {
  cat <<'USAGE'
Usage: opencode-vm <command> [name] [options]

Commands:
  create [name]              Create the named VM volumes. Default name: default.
  start [name] [--port N]    Start the VM and OpenCode Web UI.
  stop [name]                Stop the VM container.
  restart [name] [--port N]  Restart the VM.
  status [name]              Show VM container status.
  list                       List opencode-vm containers and volumes.
  logs [name]                Stream VM logs.
  shell [name]               Open a shell inside the VM.
  run [name] -- <prompt...>  Run opencode inside the VM.
  exec [name] -- <cmd...>    Execute a command inside the VM.
  import [name] <path>       Copy a host directory into /workspace.
  dump [name] <path>         Copy /workspace to a host directory.
  rm [--yes] [name]          Stop the VM and remove its volumes.
  url [name]                 Print the Web UI URL.

Examples:
  opencode-vm start
  opencode-vm run -- "請檢查 /workspace"
  opencode-vm create main
  opencode-vm import main ./project
  opencode-vm start main --port 8002
USAGE
}

validate_vm_name() {
  local name="$1"

  case "${name}" in
    ""|*/*|*\\*|.*|*..*|*[^a-z0-9_.-]*)
      printf 'Invalid VM name: %s\n' "${name}" >&2
      printf 'Use lowercase letters, numbers, dot, underscore, or hyphen.\n' >&2
      exit 2
      ;;
  esac

  if [[ "${#name}" -gt 20 ]]; then
    printf 'Invalid VM name: %s\n' "${name}" >&2
    printf 'Use 20 characters or fewer so the container user can be named opencode-vm-<name>.\n' >&2
    exit 2
  fi
}

vm_name_or_default() {
  local name="${1:-${VM_DEFAULT_NAME}}"

  validate_vm_name "${name}"
  printf '%s\n' "${name}"
}

vm_container() {
  printf '%s-%s\n' "${VM_PREFIX}" "$1"
}

vm_user() {
  printf 'opencode-vm-%s\n' "$1"
}

vm_workspace_volume() {
  printf '%s-workspace-%s\n' "${VM_PREFIX}" "$1"
}

vm_opencode_home_volume() {
  printf '%s-opencode-home-%s\n' "${VM_PREFIX}" "$1"
}

vm_state_volume() {
  printf '%s-state-%s\n' "${VM_PREFIX}" "$1"
}

vm_cache_volume() {
  printf '%s-cache-%s\n' "${VM_PREFIX}" "$1"
}

vm_port_file() {
  printf '%s/vm-%s.env\n' "${USER_CONFIG_DIR}" "$1"
}

stored_vm_port() {
  local name="$1"
  local file

  file="$(vm_port_file "${name}")"
  if [[ -f "${file}" ]]; then
    sed -n 's/^PORT=//p' "${file}" | head -n 1
    return
  fi

  printf '%s\n' "${VM_INTERNAL_PORT}"
}

write_vm_port() {
  local name="$1"
  local port="$2"
  local file

  mkdir -p "${USER_CONFIG_DIR}"
  file="$(vm_port_file "${name}")"
  cat > "${file}" <<EOF
PORT=${port}
EOF
}

validate_port() {
  local port="$1"

  case "${port}" in
    ""|*[!0-9]*)
      printf 'Invalid port: %s\n' "${port}" >&2
      exit 2
      ;;
  esac
  if (( port < 1 || port > 65535 )); then
    printf 'Invalid port: %s\n' "${port}" >&2
    exit 2
  fi
}

compose_vm() {
  local name="$1"
  local port="$2"
  shift 2

  ensure_image_profile
  ensure_vm_image
  ensure_user_config

  OPENCODE_DEV_IMAGE="$(vm_image_ref)" \
  OPENCODE_DEV_USER_CONFIG="${USER_CONFIG_DIR}" \
  OPENCODE_VM_CONTAINER="$(vm_container "${name}")" \
  OPENCODE_VM_USER="$(vm_user "${name}")" \
  OPENCODE_VM_WORKSPACE_VOLUME="$(vm_workspace_volume "${name}")" \
  OPENCODE_VM_OPENCODE_HOME_VOLUME="$(vm_opencode_home_volume "${name}")" \
  OPENCODE_VM_STATE_VOLUME="$(vm_state_volume "${name}")" \
  OPENCODE_VM_CACHE_VOLUME="$(vm_cache_volume "${name}")" \
  OPENCODE_VM_PORT="${port}" \
  docker compose \
    --env-file "${IMAGE_PROFILE}" \
    --project-name "${VM_PREFIX}-${name}" \
    --file "${COMPOSE_FILE}" \
    "$@"
}

container_exists() {
  local name="$1"

  docker inspect "$(vm_container "${name}")" >/dev/null 2>&1
}

container_running() {
  local name="$1"

  [[ "$(docker inspect -f '{{.State.Running}}' "$(vm_container "${name}")" 2>/dev/null || true)" == "true" ]]
}

ensure_vm_volumes() {
  local name="$1"

  docker volume create "$(vm_workspace_volume "${name}")" >/dev/null
  docker volume create "$(vm_opencode_home_volume "${name}")" >/dev/null
  docker volume create "$(vm_state_volume "${name}")" >/dev/null
  docker volume create "$(vm_cache_volume "${name}")" >/dev/null
}

start_vm() {
  local name="$1"
  local port="$2"

  ensure_vm_volumes "${name}"
  write_vm_port "${name}" "${port}"
  compose_vm "${name}" "${port}" up -d --no-deps opencode-vm
  printf 'Started opencode-vm %s.\n' "${name}"
  printf 'Web UI: http://localhost:%s\n' "${port}"
}

stop_vm() {
  local name="$1"

  if ! container_exists "${name}"; then
    printf 'No opencode-vm container exists: %s\n' "${name}"
    return
  fi
  docker stop --time 5 "$(vm_container "${name}")" >/dev/null
  printf 'Stopped opencode-vm %s.\n' "${name}"
}

rm_vm() {
  local name="$1"
  local volume

  if container_exists "${name}"; then
    docker rm --force "$(vm_container "${name}")" >/dev/null
  fi

  for volume in \
    "$(vm_workspace_volume "${name}")" \
    "$(vm_opencode_home_volume "${name}")" \
    "$(vm_state_volume "${name}")" \
    "$(vm_cache_volume "${name}")"
  do
    docker volume rm "${volume}" >/dev/null 2>&1 || true
  done
  rm -f "$(vm_port_file "${name}")"
  printf 'Removed opencode-vm %s.\n' "${name}"
}

confirm_rm_vm() {
  local name="$1"
  local answer

  printf 'Remove opencode-vm %s and all of its volumes? [Yes/No] ' "${name}" >&2
  read -r answer
  case "${answer}" in
    Yes)
      return 0
      ;;
    No|"")
      printf 'Aborted. opencode-vm was left untouched: %s\n' "${name}" >&2
      return 1
      ;;
    *)
      printf 'Please type Yes or No. opencode-vm was left untouched: %s\n' "${name}" >&2
      return 1
      ;;
  esac
}

status_vm() {
  local name="$1"

  if ! container_exists "${name}"; then
    printf 'No opencode-vm container exists: %s\n' "${name}"
    return
  fi
  docker ps -a \
    --filter "name=^/$(vm_container "${name}")$" \
    --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"
}

list_vms() {
  printf 'Containers:\n'
  docker ps -a \
    --filter "name=^/${VM_PREFIX}-" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
  printf '\nVolumes:\n'
  docker volume ls \
    --filter "name=^${VM_PREFIX}-" \
    --format "table {{.Name}}" || true
}

logs_vm() {
  local name="$1"

  if ! container_exists "${name}"; then
    printf 'No opencode-vm container exists: %s\n' "${name}" >&2
    exit 1
  fi
  docker logs -f "$(vm_container "${name}")"
}

ensure_running_vm() {
  local name="$1"

  if ! container_running "${name}"; then
    printf 'opencode-vm is not running: %s\n' "${name}" >&2
    printf 'Run: opencode-vm start %s\n' "${name}" >&2
    exit 1
  fi
}

shell_vm() {
  local name="$1"

  ensure_running_vm "${name}"
  docker exec -it \
    -u "$(vm_user "${name}")" \
    -e HOME=/home/opencode \
    "$(vm_container "${name}")" \
    bash
}

exec_vm() {
  local name="$1"
  shift

  ensure_running_vm "${name}"
  if [[ $# -eq 0 ]]; then
    printf 'Missing command for opencode-vm exec.\n' >&2
    exit 2
  fi
  docker exec -it \
    -u "$(vm_user "${name}")" \
    -e HOME=/home/opencode \
    "$(vm_container "${name}")" \
    "$@"
}

run_vm() {
  local name="$1"
  shift

  ensure_running_vm "${name}"
  if [[ $# -eq 0 ]]; then
    printf 'Missing prompt for opencode-vm run.\n' >&2
    exit 2
  fi
  docker exec -i \
    -u "$(vm_user "${name}")" \
    -e HOME=/home/opencode \
    "$(vm_container "${name}")" \
    opencode run "$*"
}

copy_into_workspace() {
  local name="$1"
  local source="$2"
  local source_abs

  if [[ ! -d "${source}" ]]; then
    printf 'Import source is not a directory: %s\n' "${source}" >&2
    exit 1
  fi
  source_abs="$(cd "${source}" && pwd -P)"
  ensure_image_profile
  ensure_base_alias
  ensure_vm_volumes "${name}"
  docker run --rm \
    -u root \
    -v "${source_abs}:/from:ro" \
    -v "$(vm_workspace_volume "${name}"):/to" \
    "$(base_alias_ref)" \
    bash -lc 'cp -a /from/. /to/ && chown -R opencode:opencode /to'
  printf 'Imported %s into opencode-vm %s:/workspace.\n' "${source_abs}" "${name}"
}

dump_workspace() {
  local name="$1"
  local output="$2"
  local output_abs

  mkdir -p "${output}"
  output_abs="$(cd "${output}" && pwd -P)"
  ensure_image_profile
  ensure_base_alias
  docker volume inspect "$(vm_workspace_volume "${name}")" >/dev/null
  docker run --rm \
    -u root \
    -v "$(vm_workspace_volume "${name}"):/from:ro" \
    -v "${output_abs}:/to" \
    "$(base_alias_ref)" \
    bash -lc 'cp -a /from/. /to/'
  printf 'Dumped opencode-vm %s:/workspace to %s.\n' "${name}" "${output_abs}"
}

parse_name_and_rest() {
  local default_name="$1"
  shift

  if [[ $# -eq 0 || "${1:-}" == "--" || "${1:-}" == -* ]]; then
    VM_PARSED_NAME="${default_name}"
    VM_PARSED_REST=("$@")
    return
  fi

  VM_PARSED_NAME="$(vm_name_or_default "$1")"
  shift
  VM_PARSED_REST=("$@")
}

parse_start_args() {
  local default_name="${VM_DEFAULT_NAME}"
  local name=""
  local port=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        if [[ $# -lt 2 ]]; then
          printf 'Missing value for --port.\n' >&2
          exit 2
        fi
        port="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        printf 'Unknown option: %s\n' "$1" >&2
        exit 2
        ;;
      *)
        if [[ -n "${name}" ]]; then
          printf 'Too many VM names.\n' >&2
          exit 2
        fi
        name="$1"
        shift
        ;;
    esac
  done

  name="$(vm_name_or_default "${name:-${default_name}}")"
  port="${port:-$(stored_vm_port "${name}")}"
  validate_port "${port}"
  VM_PARSED_NAME="${name}"
  VM_PARSED_PORT="${port}"
}

parse_copy_args() {
  local default_name="${VM_DEFAULT_NAME}"

  if [[ $# -eq 1 ]]; then
    VM_PARSED_NAME="${default_name}"
    VM_PARSED_PATH="$1"
    return
  fi
  if [[ $# -eq 2 ]]; then
    VM_PARSED_NAME="$(vm_name_or_default "$1")"
    VM_PARSED_PATH="$2"
    return
  fi

  printf 'Expected [name] <path>.\n' >&2
  exit 2
}

command_name="${1:-}"
case "${command_name}" in
  ""|-h|--help|help)
    usage
    exit 0
    ;;
esac
shift || true

case "${command_name}" in
  create)
    name="$(vm_name_or_default "${1:-${VM_DEFAULT_NAME}}")"
    if [[ $# -gt 1 ]]; then
      printf 'Too many arguments for create.\n' >&2
      exit 2
    fi
    ensure_vm_volumes "${name}"
    write_vm_port "${name}" "$(stored_vm_port "${name}")"
    printf 'Created opencode-vm %s.\n' "${name}"
    ;;
  start)
    parse_start_args "$@"
    start_vm "${VM_PARSED_NAME}" "${VM_PARSED_PORT}"
    ;;
  stop)
    name="$(vm_name_or_default "${1:-${VM_DEFAULT_NAME}}")"
    [[ $# -le 1 ]] || { printf 'Too many arguments for stop.\n' >&2; exit 2; }
    stop_vm "${name}"
    ;;
  restart)
    parse_start_args "$@"
    if container_exists "${VM_PARSED_NAME}"; then
      docker rm --force "$(vm_container "${VM_PARSED_NAME}")" >/dev/null
    fi
    start_vm "${VM_PARSED_NAME}" "${VM_PARSED_PORT}"
    ;;
  status)
    name="$(vm_name_or_default "${1:-${VM_DEFAULT_NAME}}")"
    [[ $# -le 1 ]] || { printf 'Too many arguments for status.\n' >&2; exit 2; }
    status_vm "${name}"
    ;;
  list)
    [[ $# -eq 0 ]] || { printf 'list does not accept arguments.\n' >&2; exit 2; }
    list_vms
    ;;
  logs)
    name="$(vm_name_or_default "${1:-${VM_DEFAULT_NAME}}")"
    [[ $# -le 1 ]] || { printf 'Too many arguments for logs.\n' >&2; exit 2; }
    logs_vm "${name}"
    ;;
  shell)
    name="$(vm_name_or_default "${1:-${VM_DEFAULT_NAME}}")"
    [[ $# -le 1 ]] || { printf 'Too many arguments for shell.\n' >&2; exit 2; }
    shell_vm "${name}"
    ;;
  exec)
    parse_name_and_rest "${VM_DEFAULT_NAME}" "$@"
    set -- "${VM_PARSED_REST[@]}"
    [[ "${1:-}" == "--" ]] && shift
    exec_vm "${VM_PARSED_NAME}" "$@"
    ;;
  run)
    parse_name_and_rest "${VM_DEFAULT_NAME}" "$@"
    set -- "${VM_PARSED_REST[@]}"
    [[ "${1:-}" == "--" ]] && shift
    run_vm "${VM_PARSED_NAME}" "$@"
    ;;
  import)
    parse_copy_args "$@"
    copy_into_workspace "${VM_PARSED_NAME}" "${VM_PARSED_PATH}"
    ;;
  dump)
    parse_copy_args "$@"
    dump_workspace "${VM_PARSED_NAME}" "${VM_PARSED_PATH}"
    ;;
  rm)
    assume_yes=0
    if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
      assume_yes=1
      shift
    fi
    name="$(vm_name_or_default "${1:-${VM_DEFAULT_NAME}}")"
    [[ $# -le 1 ]] || { printf 'Too many arguments for rm.\n' >&2; exit 2; }
    if [[ "${assume_yes}" -ne 1 ]]; then
      confirm_rm_vm "${name}" || exit 1
    fi
    rm_vm "${name}"
    ;;
  url)
    name="$(vm_name_or_default "${1:-${VM_DEFAULT_NAME}}")"
    [[ $# -le 1 ]] || { printf 'Too many arguments for url.\n' >&2; exit 2; }
    printf 'http://localhost:%s\n' "$(stored_vm_port "${name}")"
    ;;
  *)
    printf 'Unknown opencode-vm command: %s\n' "${command_name}" >&2
    usage >&2
    exit 2
    ;;
esac
