#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${DEVCONTAINER_DIR}/docker-compose.yml"
COMPOSE_ENV="${DEVCONTAINER_DIR}/compose.env"
INIT_SCRIPT="${SCRIPT_DIR}/init-opencode-dev.sh"
IMAGE_PROFILE="${DEVCONTAINER_DIR}/image.profile"

CONTAINER_NAME="opencode-dev-yuta"
USER_CONFIG_DIR="${HOME}/.opencode-dev-yuta"
PROJECT_CONFIG_DIR_NAME=".opencode-dev-yuta"
PROFILE_CONFIG_FILE="config.env"
DEFAULT_PROFILE="default"
PROJECT_IMAGE_REPOSITORY="localhost/opencode-dev-yuta-env"

IMAGE_REPOSITORY="localhost/opencode-dev-yuta"
IMAGE_TAG=""

if [[ -f "${IMAGE_PROFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${IMAGE_PROFILE}"
fi

usage() {
  cat <<'USAGE'
Usage: opencode-dev [path]
       opencode-dev profile set <name> [path]
       opencode-dev profile status [path]
       opencode-dev --uninstall
       opencode-dev --admin-help

Common usage:
  opencode-dev               Open the current directory with OpenCode.
  opencode-dev /some/project Open that project directory with OpenCode.
  opencode-dev profile set python
                             Select the python profile for this project and open it.

Commands:
  profile set <name> [path]
            Select a profile for the current or specified project, then open OpenCode.
  profile status [path]
            Show the selected profile and available user/project profiles.
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

  opencode-dev profile set <name> [path]
      Save <name> as the selected profile for the current or specified project,
      then open OpenCode with that profile.

Only one container named opencode-dev-yuta is allowed at a time. If one already
exists, this script asks whether to close it. Refusing leaves it untouched and
exits.

Implementation details:
  The base Docker image is fixed by compose.env as OPENCODE_DEV_IMAGE.
  User profiles live at ~/.opencode-dev-yuta/Dockerfile.<profile>.
  Project profiles live at <project>/.opencode-dev-yuta/Dockerfile.<profile>.
  Selected profiles are stored in config.env beside the relevant profile files.
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

base_image_ref() {
  local image

  image="$(sed -n 's/^OPENCODE_DEV_IMAGE=//p' "${COMPOSE_ENV}" | head -n 1)"
  if [[ -z "${image}" ]]; then
    printf 'compose.env does not contain OPENCODE_DEV_IMAGE: %s\n' "${COMPOSE_ENV}" >&2
    exit 1
  fi

  printf '%s\n' "${image}"
}

base_alias_ref() {
  printf '%s:base\n' "${IMAGE_REPOSITORY}"
}

ensure_base_alias() {
  local base_image base_alias

  base_image="$(base_image_ref)"
  base_alias="$(base_alias_ref)"

  if docker image inspect "${base_image}" >/dev/null 2>&1; then
    docker tag "${base_image}" "${base_alias}" >/dev/null
    return
  fi

  printf 'Docker image not found: %s\n' "${base_image}" >&2
  printf 'Run ./init.sh after placing the image tar under .docker_imgs/.\n' >&2
  exit 1
}

write_default_user_profile() {
  local profile_path="$1"
  local base_alias

  base_alias="$(base_alias_ref)"

  cat > "${profile_path}" <<EOF
FROM ${base_alias}

USER opencode
EOF
}

ensure_user_config() {
  local default_profile

  mkdir -p "${USER_CONFIG_DIR}"
  default_profile="${USER_CONFIG_DIR}/Dockerfile.${DEFAULT_PROFILE}"
  if [[ ! -f "${default_profile}" ]]; then
    write_default_user_profile "${default_profile}"
  fi
}

project_config_dir() {
  local project_dir="$1"

  printf '%s/%s\n' "${project_dir}" "${PROJECT_CONFIG_DIR_NAME}"
}

profile_config_file() {
  local project_dir="$1"

  if is_home_project "${project_dir}"; then
    printf '%s/%s\n' "${USER_CONFIG_DIR}" "${PROFILE_CONFIG_FILE}"
  else
    printf '%s/%s\n' "$(project_config_dir "${project_dir}")" "${PROFILE_CONFIG_FILE}"
  fi
}

profile_warning_marker() {
  local project_dir="$1"
  local profile="$2"

  printf '%s/.warned-project-overrides.%s\n' "$(project_config_dir "${project_dir}")" "${profile}"
}

is_home_project() {
  local project_dir="$1"
  local home_dir

  home_dir="$(cd "${HOME}" && pwd -P)"
  [[ "${project_dir}" == "${home_dir}" ]]
}

ensure_project_config() {
  local project_dir="$1"

  if is_home_project "${project_dir}"; then
    return
  fi

  mkdir -p "$(project_config_dir "${project_dir}")"
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

validate_profile_name() {
  local profile="$1"

  case "${profile}" in
    ""|*/*|*\\*|.*|*..*|*[^A-Za-z0-9_.-]*)
      printf 'Invalid profile name: %s\n' "${profile}" >&2
      printf 'Use letters, numbers, dot, underscore, or hyphen.\n' >&2
      exit 2
      ;;
  esac
}

selected_profile_name() {
  local project_dir="$1"
  local config_file profile

  config_file="$(profile_config_file "${project_dir}")"
  if [[ -f "${config_file}" ]]; then
    profile="$(sed -n 's/^SELECTED_PROFILE=//p' "${config_file}" | head -n 1)"
    if [[ -n "${profile}" ]]; then
      validate_profile_name "${profile}"
      printf '%s\n' "${profile}"
      return
    fi
  fi

  printf '%s\n' "${DEFAULT_PROFILE}"
}

write_selected_profile() {
  local project_dir="$1"
  local profile="$2"
  local config_file

  validate_profile_name "${profile}"
  ensure_user_config
  ensure_project_config "${project_dir}"
  if [[ "${profile}" != "${DEFAULT_PROFILE}" ]]; then
    profile_dockerfile "${project_dir}" "${profile}" >/dev/null
  fi

  config_file="$(profile_config_file "${project_dir}")"
  cat > "${config_file}" <<EOF
SELECTED_PROFILE=${profile}
EOF
  printf 'Selected profile for %s: %s\n' "${project_dir}" "${profile}"
}

profile_name_from_path() {
  local path="$1"
  local filename

  filename="$(basename "${path}")"
  printf '%s\n' "${filename#Dockerfile.}"
}

profile_label_prefix() {
  local scope="$1"
  local project_dir="${2:-}"
  local owner

  case "${scope}" in
    user)
      owner="$(id -un 2>/dev/null || printf '%s' "${USER:-user}")"
      ;;
    project)
      owner="$(basename "${project_dir}")"
      ;;
    *)
      owner="unknown"
      ;;
  esac

  printf '%s\n' "${owner}"
}

sanitize_image_tag() {
  tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//' \
    | cut -c 1-120
}

project_image_name() {
  local scope="$1"
  local project_dir="$2"
  local profile="$3"
  local prefix tag

  prefix="$(profile_label_prefix "${scope}" "${project_dir}")"
  tag="$(printf '%s-Dockerfile.%s' "${prefix}" "${profile}" | sanitize_image_tag)"
  if [[ -z "${tag}" ]]; then
    tag="Dockerfile.${profile}"
  fi

  printf '%s:%s\n' "${PROJECT_IMAGE_REPOSITORY}" "${tag}"
}

warn_project_profile_overrides_user_once() {
  local project_dir="$1"
  local profile="$2"
  local marker

  if is_home_project "${project_dir}"; then
    return
  fi

  marker="$(profile_warning_marker "${project_dir}" "${profile}")"
  if [[ -f "${marker}" ]]; then
    return
  fi

  printf 'Profile "%s" exists in both project and user configs; using project profile first.\n' "${profile}" >&2
  printf 'Project profile: %s/Dockerfile.%s\n' "$(basename "${project_dir}")" "${profile}" >&2
  printf 'User profile: %s/Dockerfile.%s\n' "$(profile_label_prefix user)" "${profile}" >&2
  : > "${marker}"
}

profile_dockerfile() {
  local project_dir="$1"
  local profile="$2"
  local project_profile
  local user_profile

  project_profile="$(project_config_dir "${project_dir}")/Dockerfile.${profile}"
  user_profile="${USER_CONFIG_DIR}/Dockerfile.${profile}"

  if ! is_home_project "${project_dir}" && [[ -f "${project_profile}" ]]; then
    if [[ -f "${user_profile}" ]]; then
      warn_project_profile_overrides_user_once "${project_dir}" "${profile}"
    fi
    printf 'project:%s\n' "${project_profile}"
    return
  fi

  if [[ -f "${user_profile}" ]]; then
    printf 'user:%s\n' "${user_profile}"
    return
  fi

  printf 'Profile not found: %s\n' "${profile}" >&2
  printf 'Run: opencode-dev profile status\n' >&2
  exit 1
}

file_sha256() {
  local file="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{ print $1 }'
  else
    sha256sum "${file}" | awk '{ print $1 }'
  fi
}

docker_label() {
  local image="$1"
  local label="$2"

  docker image inspect "${image}" \
    --format "{{ index .Config.Labels \"${label}\" }}" 2>/dev/null || true
}

project_image_current() {
  local image="$1"
  local base_id="$2"
  local dockerfile_sha="$3"
  local source_path="$4"
  local profile="$5"

  [[ "$(docker_label "${image}" "opencode-dev-yuta.base.id")" == "${base_id}" ]] || return 1
  [[ "$(docker_label "${image}" "opencode-dev-yuta.dockerfile.sha")" == "${dockerfile_sha}" ]] || return 1
  [[ "$(docker_label "${image}" "opencode-dev-yuta.profile.path")" == "${source_path}" ]] || return 1
  [[ "$(docker_label "${image}" "opencode-dev-yuta.profile.name")" == "${profile}" ]] || return 1
}

project_image_rebuild_reason() {
  local image="$1"
  local base_id="$2"
  local dockerfile_sha="$3"
  local source_path="$4"
  local profile="$5"

  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    printf 'profile image does not exist'
    return
  fi

  if [[ "$(docker_label "${image}" "opencode-dev-yuta.base.id")" != "${base_id}" ]]; then
    printf 'base image was updated'
    return
  fi

  if [[ "$(docker_label "${image}" "opencode-dev-yuta.dockerfile.sha")" != "${dockerfile_sha}" ]]; then
    printf 'profile Dockerfile changed'
    return
  fi

  if [[ "$(docker_label "${image}" "opencode-dev-yuta.profile.path")" != "${source_path}" ]]; then
    printf 'profile source changed'
    return
  fi

  if [[ "$(docker_label "${image}" "opencode-dev-yuta.profile.name")" != "${profile}" ]]; then
    printf 'selected profile changed'
    return
  fi

  printf 'profile image is outdated'
}

confirm_rebuild_for_base_update() {
  local base_image="$1"
  local answer

  printf 'Base image was updated: %s\n' "${base_image}" >&2
  printf 'Rebuild this profile image now? [Yes/No] ' >&2
  read -r answer

  case "${answer}" in
    Yes)
      return 0
      ;;
    *)
      printf 'Skipped rebuild. Using the existing profile image for this run.\n' >&2
      return 1
      ;;
  esac
}

ensure_profile_image() {
  local project_dir="$1"
  local profile="$2"
  local profile_spec scope dockerfile image base_alias base_image base_id dockerfile_sha context_dir reason

  ensure_compose_env
  ensure_base_alias

  profile_spec="$(profile_dockerfile "${project_dir}" "${profile}")"
  scope="${profile_spec%%:*}"
  dockerfile="${profile_spec#*:}"
  image="$(project_image_name "${scope}" "${project_dir}" "${profile}")"
  base_alias="$(base_alias_ref)"
  base_image="$(base_image_ref)"
  base_id="$(docker image inspect "${base_alias}" --format '{{.Id}}')"
  dockerfile_sha="$(file_sha256 "${dockerfile}")"

  if docker image inspect "${image}" >/dev/null 2>&1 \
    && project_image_current "${image}" "${base_id}" "${dockerfile_sha}" "${dockerfile}" "${profile}"; then
    printf '%s\n' "${image}"
    return
  fi

  reason="$(project_image_rebuild_reason "${image}" "${base_id}" "${dockerfile_sha}" "${dockerfile}" "${profile}")"
  if [[ "${reason}" == "base image was updated" && "${profile}" != "${DEFAULT_PROFILE}" ]]; then
    if ! confirm_rebuild_for_base_update "${base_image}"; then
      printf '%s\n' "${image}"
      return
    fi
  fi

  printf 'Preparing OpenCode dev environment: %s/Dockerfile.%s\n' \
    "$(profile_label_prefix "${scope}" "${project_dir}")" "${profile}" >&2
  printf 'Reason: %s.\n' "${reason}" >&2
  if [[ "${reason}" == "base image was updated" ]]; then
    printf 'Current base image: %s\n' "${base_image}" >&2
    printf 'Rebuilding the profile image before opening OpenCode.\n' >&2
  fi

  context_dir="$(dirname "${dockerfile}")"
  docker build \
    --tag "${image}" \
    --label "opencode-dev-yuta.base.id=${base_id}" \
    --label "opencode-dev-yuta.profile.name=${profile}" \
    --label "opencode-dev-yuta.profile.scope=${scope}" \
    --label "opencode-dev-yuta.profile.path=${dockerfile}" \
    --label "opencode-dev-yuta.dockerfile.sha=${dockerfile_sha}" \
    --file "${dockerfile}" \
    "${context_dir}" >&2

  printf '%s\n' "${image}"
}

active_image_for_project() {
  local project_dir="$1"
  local profile

  ensure_user_config
  ensure_project_config "${project_dir}"
  profile="$(selected_profile_name "${project_dir}")"

  if [[ "${profile}" == "${DEFAULT_PROFILE}" ]]; then
    ensure_compose_env
    ensure_base_alias
    base_alias_ref
    return
  fi

  ensure_profile_image "${project_dir}" "${profile}"
}

list_dockerfile_profiles() {
  local scope="$1"
  local dir="$2"
  local owner="$3"
  local found=0
  local file profile

  printf '%s profiles:\n' "${scope}"
  for file in "${dir}"/Dockerfile.*; do
    if [[ ! -f "${file}" ]]; then
      continue
    fi
    profile="$(profile_name_from_path "${file}")"
    printf '  %s/Dockerfile.%s\n' "${owner}" "${profile}"
    found=1
  done

  if [[ "${found}" -eq 0 ]]; then
    printf '  (none)\n'
  fi
}

show_profile_status() {
  local project_dir="$1"
  local user_name project_name
  local config_file

  ensure_user_config
  ensure_project_config "${project_dir}"

  user_name="$(profile_label_prefix user)"
  project_name="$(profile_label_prefix project "${project_dir}")"
  config_file="$(profile_config_file "${project_dir}")"

  printf 'Path: %s\n' "${project_dir}"
  printf 'Selected profile: %s\n' "$(selected_profile_name "${project_dir}")"
  if [[ -f "${config_file}" ]]; then
    printf 'Profile config: %s\n' "${config_file}"
  else
    printf 'Profile config: %s (not created; using default)\n' "${config_file}"
  fi
  printf 'User profile dir: %s\n' "${USER_CONFIG_DIR}"
  if is_home_project "${project_dir}"; then
    printf 'Project profile dir: (home directory uses user profiles)\n\n'
  else
    printf 'Project profile dir: %s\n\n' "$(project_config_dir "${project_dir}")"
  fi
  list_dockerfile_profiles "user" "${USER_CONFIG_DIR}" "${user_name}"
  printf '\n'
  if is_home_project "${project_dir}"; then
    printf 'project profiles:\n'
    printf '  (none)\n'
  else
    list_dockerfile_profiles "project" "$(project_config_dir "${project_dir}")" "${project_name}"
  fi
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

  profile)
    shift || true
    profile_command="${1:-}"
    case "${profile_command}" in
      set)
        shift || true
        if [[ $# -lt 1 ]]; then
          printf 'Usage: opencode-dev profile set <name> [path]\n' >&2
          exit 2
        fi
        profile_name="$1"
        shift || true
        project_arg=""
        if [[ $# -gt 0 && "${1}" != "--" ]]; then
          project_arg="$1"
          shift || true
        fi
        if [[ $# -gt 0 && "${1}" == "--" ]]; then
          shift || true
        fi
        project_dir="$(resolve_project_dir "${project_arg}")"
        write_selected_profile "${project_dir}" "${profile_name}"
        remove_existing_container_if_allowed
        run_opencode "${project_dir}" "$@"
        ;;
      status)
        shift || true
        show_profile_status "$(resolve_project_dir "${1:-}")"
        ;;
      ""|-h|--help)
        printf 'Usage: opencode-dev profile set <name> [path]\n'
        printf '       opencode-dev profile status [path]\n'
        ;;
      *)
        printf 'Unknown profile command: %s\n' "${profile_command}" >&2
        printf 'Usage: opencode-dev profile set <name> [path]\n' >&2
        printf '       opencode-dev profile status [path]\n' >&2
        exit 2
        ;;
    esac
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
