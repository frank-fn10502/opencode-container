#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../common.sh
source "${SCRIPT_DIR}/../common.sh"
# shellcheck source=../dev/profiles.sh
source "${SCRIPT_DIR}/../dev/profiles.sh"

VM_DEFAULT_NAME="default"
VM_PREFIX="opencode-vm-yuta"
VM_DEFAULT_PORT_BASE="2500"
VM_PORT_STEP="10"

usage() {
  cat <<'USAGE'
Usage: opencode-vm <command> [name] [options]

Commands:
  create [name]              Create the named VM volumes. Default name: default.
  start [name] [--port-base N] [--webui-port N] [--ssh-port N]
                             Start the VM, OpenCode Web UI, and SSH.
  stop [name]                Stop the VM container.
  restart [name] [--port-base N] [--webui-port N] [--ssh-port N]
                             Restart the VM.
  status [name]              Show VM container status.
  list                       List opencode-vm containers and volumes.
  logs [name]                Stream VM logs.
  shell [name]               Open a shell inside the VM.
  run [name] -- <prompt...>  Run opencode inside the VM.
  exec [name] -- <cmd...>    Execute a command inside the VM.
  import [name] --src <host-path> --dist <vm-path>
                             Copy a host path into the VM workspace.
  dump [name] --src <vm-path> --dist <host-path>
                             Copy a VM workspace path to a host directory.
  rm [--yes] [name]          Stop the VM and remove its volumes.
  url [name]                 Print the Web UI URL.

Examples:
  opencode-vm start
  opencode-vm run -- "請檢查 /workspace"
  opencode-vm create main
  opencode-vm import main --src ./project --dist /workspace/project
  opencode-vm start main --port-base 2510
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
    printf 'Use 20 characters or fewer so the container hostname can be named opencode-vm-<name>.\n' >&2
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

vm_hostname() {
  local name="$1"

  printf 'opencode-vm-%s\n' "${name//[._]/-}"
}

vm_user() {
  printf 'opencode\n'
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

vm_ssh_volume() {
  printf '%s-ssh-%s\n' "${VM_PREFIX}" "$1"
}

vm_port_file() {
  printf '%s/vm-%s.env\n' "${USER_CONFIG_DIR}" "$1"
}

stored_vm_port() {
  local name="$1"
  local file

  file="$(vm_port_file "${name}")"
  if [[ -f "${file}" ]]; then
    sed -n 's/^WEBUI_PORT=//p' "${file}" | head -n 1
    return
  fi
}

stored_vm_ssh_port() {
  local name="$1"
  local file

  file="$(vm_port_file "${name}")"
  if [[ -f "${file}" ]]; then
    sed -n 's/^SSH_PORT=//p' "${file}" | head -n 1
    return
  fi
}

write_vm_ports() {
  local name="$1"
  local webui_port="$2"
  local ssh_port="$3"
  local file

  mkdir -p "${USER_CONFIG_DIR}"
  file="$(vm_port_file "${name}")"
  cat > "${file}" <<EOF
WEBUI_PORT=${webui_port}
SSH_PORT=${ssh_port}
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

port_in_use() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return
  fi

  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "${port}" >/dev/null 2>&1
    return
  fi

  return 1
}

find_available_port_pair() {
  local base="$1"
  local webui_port ssh_port

  validate_port "${base}"
  while true; do
    webui_port=$((base + 1))
    ssh_port=$((base + 2))
    validate_port "${webui_port}"
    validate_port "${ssh_port}"
    if ! port_in_use "${webui_port}" && ! port_in_use "${ssh_port}"; then
      VM_SUGGESTED_WEBUI_PORT="${webui_port}"
      VM_SUGGESTED_SSH_PORT="${ssh_port}"
      return
    fi
    base=$((base + VM_PORT_STEP))
  done
}

prompt_port() {
  local label="$1"
  local default_port="$2"
  local answer

  if [[ ! -t 0 ]]; then
    printf '%s\n' "${default_port}"
    return
  fi

  printf '%s [%s]: ' "${label}" "${default_port}" >&2
  read -r answer
  if [[ -z "${answer}" ]]; then
    printf '%s\n' "${default_port}"
    return
  fi
  validate_port "${answer}"
  printf '%s\n' "${answer}"
}

resolve_port_pair() {
  local name="$1"
  local requested_base="$2"
  local requested_webui_port="$3"
  local requested_ssh_port="$4"
  local stored_webui_port stored_ssh_port base
  local webui_port ssh_port

  stored_webui_port="$(stored_vm_port "${name}")"
  stored_ssh_port="$(stored_vm_ssh_port "${name}")"

  if [[ -n "${requested_base}" ]]; then
    base="${requested_base}"
  elif [[ -n "${stored_webui_port}" && -n "${stored_ssh_port}" ]]; then
    if container_running "${name}" || [[ ! -t 0 ]]; then
      VM_PARSED_WEBUI_PORT="${stored_webui_port}"
      VM_PARSED_SSH_PORT="${stored_ssh_port}"
      return
    fi
    base=$((stored_webui_port - 1))
    webui_port="${requested_webui_port:-$(prompt_port "Web UI port" "${stored_webui_port}")}"
    ssh_port="${requested_ssh_port:-$(prompt_port "SSH port" "${stored_ssh_port}")}"
  else
    base="${VM_DEFAULT_PORT_BASE}"
  fi

  if [[ -z "${webui_port:-}" && -n "${requested_webui_port}" && -n "${requested_ssh_port}" ]]; then
    webui_port="${requested_webui_port}"
    ssh_port="${requested_ssh_port}"
  elif [[ -z "${webui_port:-}" ]]; then
    find_available_port_pair "${base}"
    webui_port="${requested_webui_port:-$(prompt_port "Web UI port" "${VM_SUGGESTED_WEBUI_PORT}")}"
    ssh_port="${requested_ssh_port:-$(prompt_port "SSH port" "${VM_SUGGESTED_SSH_PORT}")}"
  fi

  validate_port "${webui_port}"
  validate_port "${ssh_port}"
  if [[ "${webui_port}" == "${ssh_port}" ]]; then
    printf 'Web UI port and SSH port must be different: %s\n' "${webui_port}" >&2
    exit 2
  fi

  if port_in_use "${webui_port}" || port_in_use "${ssh_port}"; then
    printf 'Requested ports are not both available: webui=%s ssh=%s\n' "${webui_port}" "${ssh_port}" >&2
    find_available_port_pair "${base}"
    webui_port="${VM_SUGGESTED_WEBUI_PORT}"
    ssh_port="${VM_SUGGESTED_SSH_PORT}"
    printf 'Using next available VM port pair: webui=%s ssh=%s\n' "${webui_port}" "${ssh_port}" >&2
  fi

  VM_PARSED_WEBUI_PORT="${webui_port}"
  VM_PARSED_SSH_PORT="${ssh_port}"
}

compose_vm() {
  local name="$1"
  local webui_port="$2"
  local ssh_port="$3"
  shift 3

  ensure_image_profile
  ensure_vm_image
  ensure_user_config

  OPENCODE_DEV_IMAGE="$(vm_image_ref)" \
  OPENCODE_DEV_WORKSPACE="/tmp" \
  OPENCODE_DEV_USER_CONFIG="${USER_CONFIG_DIR}" \
  OPENCODE_VM_CONTAINER="$(vm_container "${name}")" \
  OPENCODE_VM_HOSTNAME="$(vm_hostname "${name}")" \
  OPENCODE_VM_WORKSPACE_VOLUME="$(vm_workspace_volume "${name}")" \
  OPENCODE_VM_OPENCODE_HOME_VOLUME="$(vm_opencode_home_volume "${name}")" \
  OPENCODE_VM_STATE_VOLUME="$(vm_state_volume "${name}")" \
  OPENCODE_VM_CACHE_VOLUME="$(vm_cache_volume "${name}")" \
  OPENCODE_VM_SSH_VOLUME="$(vm_ssh_volume "${name}")" \
  OPENCODE_VM_WEBUI_PORT="${webui_port}" \
  OPENCODE_VM_SSH_PORT="${ssh_port}" \
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
  docker volume create "$(vm_ssh_volume "${name}")" >/dev/null
}

start_vm() {
  local name="$1"
  local webui_port="$2"
  local ssh_port="$3"

  ensure_vm_volumes "${name}"
  write_vm_ports "${name}" "${webui_port}" "${ssh_port}"
  compose_vm "${name}" "${webui_port}" "${ssh_port}" up -d --no-deps opencode-vm
  printf 'Started opencode-vm %s.\n' "${name}"
  printf 'Web UI: http://localhost:%s\n' "${webui_port}"
  printf 'SSH: ssh -p %s opencode@localhost\n' "${ssh_port}"
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
    "$(vm_cache_volume "${name}")" \
    "$(vm_ssh_volume "${name}")"
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
  local docker_exec_flags=(-i)

  ensure_running_vm "${name}"
  if [[ -t 0 && -t 1 ]]; then
    docker_exec_flags=(-it)
  fi
  docker exec "${docker_exec_flags[@]}" \
    -u "$(vm_user "${name}")" \
    -e HOME=/home/opencode \
    "$(vm_container "${name}")" \
    bash
}

exec_vm() {
  local name="$1"
  local docker_exec_flags=(-i)
  shift

  ensure_running_vm "${name}"
  if [[ $# -eq 0 ]]; then
    printf 'Missing command for opencode-vm exec.\n' >&2
    exit 2
  fi
  if [[ -t 0 && -t 1 ]]; then
    docker_exec_flags=(-it)
  fi
  docker exec "${docker_exec_flags[@]}" \
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
    -e TZ="${TZ:-Asia/Taipei}" \
    "$(vm_container "${name}")" \
    opencode run "$@"
}

workspace_relative_path() {
  local label="$1"
  local path="$2"

  case "${path}" in
    /workspace)
      printf '\n'
      ;;
    /workspace/*)
      path="${path#/workspace/}"
      if [[ "${path}" == *".."* ]]; then
        printf '%s must not contain .. path segments: /workspace/%s\n' "${label}" "${path}" >&2
        exit 2
      fi
      printf '%s\n' "${path}"
      ;;
    *)
      printf '%s must be /workspace or a path under /workspace: %s\n' "${label}" "${path}" >&2
      exit 2
      ;;
  esac
}

copy_into_workspace() {
  local name="$1"
  local source="$2"
  local dist="$3"
  local source_abs
  local source_base
  local source_parent
  local dist_rel

  if [[ ! -e "${source}" ]]; then
    printf 'Import source does not exist: %s\n' "${source}" >&2
    exit 1
  fi
  source_parent="$(cd "$(dirname "${source}")" && pwd -P)"
  source_base="$(basename "${source}")"
  source_abs="${source_parent}/${source_base}"
  dist_rel="$(workspace_relative_path "Import dist" "${dist}")"
  ensure_image_profile
  ensure_base_alias
  ensure_vm_volumes "${name}"
  docker run --rm \
    -u root \
    -v "${source_parent}:/host-source:ro" \
    -v "$(vm_workspace_volume "${name}"):/to" \
    -e VM_IMPORT_SOURCE_BASE="${source_base}" \
    -e VM_IMPORT_DIST_REL="${dist_rel}" \
    "$(base_alias_ref)" \
    bash -lc '
      set -euo pipefail
      target="/to"
      if [[ -n "${VM_IMPORT_DIST_REL}" ]]; then
        target="/to/${VM_IMPORT_DIST_REL}"
      fi
      mkdir -p "${target}"
      if [[ -d "/host-source/${VM_IMPORT_SOURCE_BASE}" ]]; then
        cp -a "/host-source/${VM_IMPORT_SOURCE_BASE}/." "${target}/"
      else
        cp -a "/host-source/${VM_IMPORT_SOURCE_BASE}" "${target}/"
      fi
      chown -R opencode:opencode "${target}"
    '
  printf 'Imported %s into opencode-vm %s:%s.\n' "${source_abs}" "${name}" "${dist}"
}

dump_workspace() {
  local name="$1"
  local source="$2"
  local output="$3"
  local source_rel
  local output_abs

  source_rel="$(workspace_relative_path "Dump src" "${source}")"
  mkdir -p "${output}"
  output_abs="$(cd "${output}" && pwd -P)"
  ensure_image_profile
  ensure_base_alias
  docker volume inspect "$(vm_workspace_volume "${name}")" >/dev/null
  docker run --rm \
    -u root \
    -v "$(vm_workspace_volume "${name}"):/from:ro" \
    -v "${output_abs}:/to" \
    -e VM_DUMP_SOURCE_REL="${source_rel}" \
    "$(base_alias_ref)" \
    bash -lc '
      set -euo pipefail
      if [[ -z "${VM_DUMP_SOURCE_REL}" ]]; then
        cp -a /from/. /to/
      elif [[ -d "/from/${VM_DUMP_SOURCE_REL}" ]]; then
        cp -a "/from/${VM_DUMP_SOURCE_REL}/." /to/
      elif [[ -f "/from/${VM_DUMP_SOURCE_REL}" ]]; then
        cp -a "/from/${VM_DUMP_SOURCE_REL}" /to/
      else
        printf "Dump source does not exist: /workspace/%s\n" "${VM_DUMP_SOURCE_REL}" >&2
        exit 1
      fi
    '
  printf 'Dumped opencode-vm %s:%s to %s.\n' "${name}" "${source}" "${output_abs}"
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
  local port_base=""
  local webui_port=""
  local ssh_port=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --webui-port)
        if [[ $# -lt 2 ]]; then
          printf 'Missing value for --webui-port.\n' >&2
          exit 2
        fi
        webui_port="$2"
        validate_port "${webui_port}"
        shift 2
        ;;
      --ssh-port)
        if [[ $# -lt 2 ]]; then
          printf 'Missing value for --ssh-port.\n' >&2
          exit 2
        fi
        ssh_port="$2"
        validate_port "${ssh_port}"
        shift 2
        ;;
      --port-base)
        if [[ $# -lt 2 ]]; then
          printf 'Missing value for --port-base.\n' >&2
          exit 2
        fi
        port_base="$2"
        validate_port "${port_base}"
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
          printf 'Unexpected positional argument: %s\n' "$1" >&2
          printf 'Use: [name] --src <path> --dist <path>.\n' >&2
          exit 2
        fi
        name="$1"
        shift
        ;;
    esac
  done

  name="$(vm_name_or_default "${name:-${default_name}}")"
  resolve_port_pair "${name}" "${port_base}" "${webui_port}" "${ssh_port}"
  VM_PARSED_NAME="${name}"
}

parse_transfer_args() {
  local default_name="${VM_DEFAULT_NAME}"
  local name=""
  local src=""
  local dist=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --src)
        if [[ $# -lt 2 ]]; then
          printf 'Missing value for --src.\n' >&2
          exit 2
        fi
        src="$2"
        shift 2
        ;;
      --dist)
        if [[ $# -lt 2 ]]; then
          printf 'Missing value for --dist.\n' >&2
          exit 2
        fi
        dist="$2"
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
          printf 'Unexpected positional argument: %s\n' "$1" >&2
          printf 'Use: [name] --src <path> --dist <path>.\n' >&2
          exit 2
        fi
        name="$1"
        shift
        ;;
    esac
  done

  if [[ -z "${src}" || -z "${dist}" ]]; then
    printf 'Expected [name] --src <path> --dist <path>.\n' >&2
    exit 2
  fi

  VM_PARSED_NAME="$(vm_name_or_default "${name:-${default_name}}")"
  VM_PARSED_SOURCE="${src}"
  VM_PARSED_DIST="${dist}"
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
    parse_start_args "$@"
    name="${VM_PARSED_NAME}"
    ensure_vm_volumes "${name}"
    write_vm_ports "${name}" "${VM_PARSED_WEBUI_PORT}" "${VM_PARSED_SSH_PORT}"
    printf 'Created opencode-vm %s.\n' "${name}"
    printf 'Web UI port: %s\n' "${VM_PARSED_WEBUI_PORT}"
    printf 'SSH port: %s\n' "${VM_PARSED_SSH_PORT}"
    ;;
  start)
    parse_start_args "$@"
    start_vm "${VM_PARSED_NAME}" "${VM_PARSED_WEBUI_PORT}" "${VM_PARSED_SSH_PORT}"
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
    start_vm "${VM_PARSED_NAME}" "${VM_PARSED_WEBUI_PORT}" "${VM_PARSED_SSH_PORT}"
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
    parse_transfer_args "$@"
    copy_into_workspace "${VM_PARSED_NAME}" "${VM_PARSED_SOURCE}" "${VM_PARSED_DIST}"
    ;;
  dump)
    parse_transfer_args "$@"
    dump_workspace "${VM_PARSED_NAME}" "${VM_PARSED_SOURCE}" "${VM_PARSED_DIST}"
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
    port="$(stored_vm_port "${name}")"
    if [[ -z "${port}" ]]; then
      find_available_port_pair "${VM_DEFAULT_PORT_BASE}"
      port="${VM_SUGGESTED_WEBUI_PORT}"
    fi
    printf 'http://localhost:%s\n' "${port}"
    ;;
  *)
    printf 'Unknown opencode-vm command: %s\n' "${command_name}" >&2
    usage >&2
    exit 2
    ;;
esac
