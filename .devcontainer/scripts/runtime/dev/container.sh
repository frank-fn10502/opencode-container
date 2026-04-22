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
  printf '%s' "Close it before starting a new ${CONTAINER_NAME}? [Yes/No] "
  read -r answer

  case "${answer}" in
    Yes)
      return 0
      ;;
    No|"")
      printf '%s\n' "Aborted. The existing ${CONTAINER_NAME} container was left untouched."
      return 1
      ;;
    *)
      printf '%s\n' "Please type Yes or No."
      printf '%s\n' "Aborted. The existing ${CONTAINER_NAME} container was left untouched."
      return 1
      ;;
  esac
}

remove_container() {
  local id="$1"

  if container_running "${id}"; then
    if ! docker stop --time 5 "${id}" >/dev/null; then
      printf 'Container did not stop cleanly; forcing removal: %s\n' "${CONTAINER_NAME}" >&2
      docker rm --force "${id}" >/dev/null
      return
    fi
  fi

  if container_running "${id}"; then
    printf 'Container is still running after stop; forcing removal: %s\n' "${CONTAINER_NAME}" >&2
    docker rm --force "${id}" >/dev/null
    return
  fi

  docker rm "${id}" >/dev/null
}

remove_existing_container_if_allowed() {
  local id

  id="$(container_id)"
  if [[ -z "${id}" ]]; then
    return
  fi

  confirm_close_existing || exit 1
  remove_container "${id}"
}

compose_run_base() {
  local project_dir="$1"
  local image="$2"
  shift
  shift

  ensure_image_profile

  OPENCODE_DEV_IMAGE="${image}" \
  OPENCODE_DEV_WORKSPACE="${project_dir}" \
  OPENCODE_DEV_USER_CONFIG="${USER_CONFIG_DIR}" \
  docker compose \
    --env-file "${IMAGE_PROFILE}" \
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

  image="$(active_image_for_project "${project_dir}")"
  compose_run_base "${project_dir}" "${image}" opencode
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

  remove_container "${id}"
  printf 'Removed opencode-dev-yuta container.\n'
}

uninstall_opencode_dev() {
  if [[ ! -f "${INIT_SCRIPT}" ]]; then
    printf 'Cannot find uninstall script: %s\n' "${INIT_SCRIPT}" >&2
    exit 1
  fi

  bash "${INIT_SCRIPT}" --uninstall
}
