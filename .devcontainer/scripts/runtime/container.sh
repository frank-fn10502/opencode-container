#!/usr/bin/env bash

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

compose_run_base() {
  local project_dir="$1"
  local image="$2"
  shift
  shift

  ensure_compose_env

  OPENCODE_DEV_IMAGE="${image}" \
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
  local image
  shift

  image="$(active_image_for_project "${project_dir}")"
  compose_run_base "${project_dir}" "${image}" opencode "$@"
}

run_shell() {
  local project_dir="$1"
  local image

  image="$(active_image_for_project "${project_dir}")"
  compose_run_base "${project_dir}" "${image}" bash
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
