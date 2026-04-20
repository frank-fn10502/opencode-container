#!/usr/bin/env bash

copy_user_profile_templates() {
  local template
  local target

  if [[ ! -d "${USER_PROFILE_TEMPLATE_DIR}" ]]; then
    printf 'Cannot find user profile template dir: %s\n' "${USER_PROFILE_TEMPLATE_DIR}" >&2
    exit 1
  fi

  for template in "${USER_PROFILE_TEMPLATE_DIR}"/Dockerfile.*; do
    if [[ ! -f "${template}" ]]; then
      continue
    fi

    target="${USER_CONFIG_DIR}/$(basename "${template}")"
    cp "${template}" "${target}"
  done
}

ensure_user_config() {
  mkdir -p "${USER_CONFIG_DIR}"
  copy_profile_readme "${USER_CONFIG_DIR}" "${USER_PROFILE_README_SOURCE}"
  copy_user_profile_templates
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
