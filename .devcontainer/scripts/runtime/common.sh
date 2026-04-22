#!/usr/bin/env bash

COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_OR_SCRIPTS_DIR="$(cd "${COMMON_SCRIPT_DIR}/.." && pwd)"
if [[ -d "${INSTALL_OR_SCRIPTS_DIR}/compose" ]]; then
  DEVCONTAINER_DIR="${INSTALL_OR_SCRIPTS_DIR}"
else
  DEVCONTAINER_DIR="$(cd "${COMMON_SCRIPT_DIR}/../.." && pwd)"
fi

COMPOSE_DIR="${DEVCONTAINER_DIR}/compose"
DEV_COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.dev.yml"
VM_COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.vm.yml"
IMAGE_PROFILE="${DEVCONTAINER_DIR}/image.profile"

if [[ -f "${DEVCONTAINER_DIR}/init/init-opencode.sh" ]]; then
  INIT_SCRIPT="${DEVCONTAINER_DIR}/init/init-opencode.sh"
else
  INIT_SCRIPT="${DEVCONTAINER_DIR}/scripts/init/init-opencode.sh"
fi

CONTAINER_NAME="opencode-dev-yuta"
USER_CONFIG_DIR="${HOME}/.opencode-dev-yuta"
PROJECT_CONFIG_DIR_NAME=".opencode-dev-yuta"
PROFILE_CONFIG_FILE="config.env"
PROFILE_README_FILE="README.md"
USER_PROFILE_README_SOURCE="${DEVCONTAINER_DIR}/config/profile-dockerfile-guide.md"
PROJECT_PROFILE_README_SOURCE="${DEVCONTAINER_DIR}/config/project-profile-readme.md"
USER_PROFILE_TEMPLATE_DIR="${DEVCONTAINER_DIR}/config/user-profiles"
IMAGE_REPOSITORY="localhost/opencode-dev-yuta"
PROJECT_IMAGE_REPOSITORY="localhost/opencode-dev-yuta"
DEFAULT_PROFILE="default"
IMAGE_TAG=""
VM_IMAGE_TAG=""
OPENCODE_VM_IMAGE=""

if [[ -f "${IMAGE_PROFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${IMAGE_PROFILE}"
fi

ensure_image_profile() {
  if [[ ! -f "${IMAGE_PROFILE}" ]]; then
    printf 'Cannot find image profile: %s\n' "${IMAGE_PROFILE}" >&2
    printf 'Run ./init.sh to install opencode-dev with a fixed image setting.\n' >&2
    exit 1
  fi

  if ! grep -Eq '^OPENCODE_DEV_IMAGE=.+:.+' "${IMAGE_PROFILE}"; then
    printf 'image.profile does not contain a fixed OPENCODE_DEV_IMAGE value: %s\n' "${IMAGE_PROFILE}" >&2
    printf 'Run ./init.sh after placing the image tar under .docker_imgs/.\n' >&2
    exit 1
  fi
}

base_image_ref() {
  local image

  image="$(sed -n 's/^OPENCODE_DEV_IMAGE=//p' "${IMAGE_PROFILE}" | head -n 1)"
  if [[ -z "${image}" ]]; then
    printf 'image.profile does not contain OPENCODE_DEV_IMAGE: %s\n' "${IMAGE_PROFILE}" >&2
    exit 1
  fi

  printf '%s\n' "${image}"
}

base_alias_ref() {
  printf '%s:base\n' "${IMAGE_REPOSITORY}"
}

vm_image_ref() {
  local image

  image="$(sed -n 's/^OPENCODE_VM_IMAGE=//p' "${IMAGE_PROFILE}" | head -n 1)"
  if [[ -z "${image}" ]]; then
    printf 'image.profile does not contain OPENCODE_VM_IMAGE: %s\n' "${IMAGE_PROFILE}" >&2
    printf 'Build the release images with: ./admin/build-image.sh\n' >&2
    exit 1
  fi

  printf '%s\n' "${image}"
}

vm_alias_ref() {
  printf '%s:vm\n' "${IMAGE_REPOSITORY}"
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

ensure_vm_image() {
  local image

  ensure_image_profile
  ensure_base_alias
  image="$(vm_image_ref)"

  if docker image inspect "${image}" >/dev/null 2>&1; then
    return
  fi

  printf 'Docker VM image not found: %s\n' "${image}" >&2
  printf 'Build the release images with: ./admin/build-image.sh\n' >&2
  printf 'Or place the matching tar under .docker_imgs/ and rerun ./init.sh.\n' >&2
  exit 1
}

is_home_project() {
  local project_dir="$1"
  local home_dir

  home_dir="$(cd "${HOME}" && pwd -P)"
  [[ "${project_dir}" == "${home_dir}" ]]
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

copy_profile_readme() {
  local config_dir="$1"
  local source="$2"
  local readme_path

  readme_path="${config_dir}/${PROFILE_README_FILE}"
  if [[ -f "${readme_path}" ]]; then
    return
  fi

  if [[ ! -f "${source}" ]]; then
    printf 'Cannot find profile README source: %s\n' "${source}" >&2
    exit 1
  fi

  cp "${source}" "${readme_path}"
}

ensure_project_config() {
  local project_dir="$1"
  local config_dir

  if is_home_project "${project_dir}"; then
    return
  fi

  config_dir="$(project_config_dir "${project_dir}")"
  mkdir -p "${config_dir}"
  copy_profile_readme "${config_dir}" "${PROJECT_PROFILE_README_SOURCE}"
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

file_sha256() {
  local file="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{ print $1 }'
  else
    sha256sum "${file}" | awk '{ print $1 }'
  fi
}
