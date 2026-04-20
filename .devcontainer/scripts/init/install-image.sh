#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_OR_SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -f "${INSTALL_OR_SCRIPTS_DIR}/image.profile" ]]; then
  DEVCONTAINER_DIR="${INSTALL_OR_SCRIPTS_DIR}"
else
  DEVCONTAINER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi
PROJECT_ROOT="$(cd "${DEVCONTAINER_DIR}/.." && pwd)"
IMAGE_PROFILE="${DEVCONTAINER_DIR}/image.profile"
IMAGE_REPOSITORY="localhost/opencode-dev-yuta"
IMAGE_TAG=""
INSTALL_DIR="${HOME}/.local/bin/opencode-dev-yuta"
INSTALL_MARKER="${INSTALL_DIR}/.opencode-dev-managed"
INSTALL_IMAGE_PROFILE="${INSTALL_DIR}/image.profile"
INSTALL_COMPOSE_ENV="${INSTALL_DIR}/compose.env"

if [[ -f "${IMAGE_PROFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${IMAGE_PROFILE}"
fi

usage() {
  cat <<'USAGE'
Usage: install-image.sh
       install-image.sh .docker_imgs/opencode-dev-yuta-<version>.tar

Load an OpenCode dev Docker image into the local Docker daemon. Without an
argument, this script first checks whether the configured image already exists,
then looks for the matching tar under .docker_imgs/.

The image repository and optional tag are read from image.profile. If IMAGE_TAG
is set, the tar must contain exactly IMAGE_REPOSITORY:IMAGE_TAG.

Options:
  -h, --help    Show this help.
USAGE
}

existing_image_ref() {
  if [[ -n "${IMAGE_TAG:-}" ]]; then
    if docker image inspect "${IMAGE_REPOSITORY}:${IMAGE_TAG}" >/dev/null 2>&1; then
      printf '%s:%s\n' "${IMAGE_REPOSITORY}" "${IMAGE_TAG}"
    fi
    return
  fi

  docker image ls "${IMAGE_REPOSITORY}" --format '{{.Repository}}:{{.Tag}}' \
    | awk '$0 !~ /:<none>$/ { print; exit }'
}

find_image_tar() {
  local candidate
  local choice
  local index
  local tar_files=()

  if [[ -n "${IMAGE_TAG:-}" ]]; then
    candidate="${PROJECT_ROOT}/.docker_imgs/opencode-dev-yuta-${IMAGE_TAG}.tar"
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi

    printf 'Required image tar not found: .docker_imgs/opencode-dev-yuta-%s.tar\n' "${IMAGE_TAG}" >&2
    exit 1
  fi

  for candidate in \
    "${PROJECT_ROOT}"/.docker_imgs/opencode-dev-yuta-*.tar
  do
    if [[ -f "${candidate}" ]]; then
      tar_files+=("${candidate}")
    fi
  done

  if [[ "${#tar_files[@]}" -eq 1 ]]; then
    printf '%s\n' "${tar_files[0]}"
    return
  fi

  if [[ "${#tar_files[@]}" -gt 1 ]]; then
    printf 'Multiple image tar files were found under .docker_imgs/:\n' >&2
    for index in "${!tar_files[@]}"; do
      printf '  %d) %s\n' "$((index + 1))" "${tar_files[index]#${PROJECT_ROOT}/}" >&2
    done

    while true; do
      printf 'Select image tar [1-%d]: ' "${#tar_files[@]}" >&2
      read -r choice
      case "${choice}" in
        ''|*[!0-9]*)
          printf 'Enter a number from 1 to %d.\n' "${#tar_files[@]}" >&2
          ;;
        *)
          if (( choice >= 1 && choice <= ${#tar_files[@]} )); then
            printf '%s\n' "${tar_files[choice - 1]}"
            return
          fi
          printf 'Enter a number from 1 to %d.\n' "${#tar_files[@]}" >&2
          ;;
      esac
    done
  fi

  printf 'No local %s image exists, and no opencode-dev-yuta-*.tar was found.\n' "${IMAGE_REPOSITORY}" >&2
  printf 'Place the tar in .docker_imgs/.\n' >&2
  exit 1
}

assert_docker_imgs_tar() {
  local source="$1"
  local source_dir
  local filename

  case "${source}" in
    .docker_imgs/*)
      ;;
    *)
      printf 'Image tar must be under .docker_imgs/: %s\n' "${source}" >&2
      exit 1
      ;;
  esac

  source_dir="$(cd "$(dirname "${source}")" && pwd -P)"
  if [[ "${source_dir}" != "${PROJECT_ROOT}/.docker_imgs" ]]; then
    printf 'Image tar must be directly under .docker_imgs/: %s\n' "${source}" >&2
    exit 1
  fi

  filename="$(basename "${source}")"
  case "${filename}" in
    opencode-dev-yuta-*.tar)
      ;;
    *)
      printf 'Image tar filename must match opencode-dev-yuta-*.tar: %s\n' "${source}" >&2
      exit 1
      ;;
  esac

  if [[ ! -f "${source}" ]]; then
    printf 'Image tar not found: %s\n' "${source}" >&2
    exit 1
  fi
}

copy_tar() {
  local source="$1"
  local output="$2"

  cp "${source}" "${output}"
}

loaded_image_ref() {
  awk -v repo="${IMAGE_REPOSITORY}" -v expected="${IMAGE_REPOSITORY}:${IMAGE_TAG:-}" '
    /^Loaded image: / {
      ref = substr($0, 15)
      if (expected != repo ":" && ref == expected) {
        print ref
        exit
      }
      if (expected != repo ":") {
        next
      }
      if (index(ref, repo ":") == 1) {
        print ref
        exit
      }
    }
  '
}

tar_contains_expected_image() {
  local tar_path="$1"

  if [[ -z "${IMAGE_TAG:-}" ]]; then
    return 0
  fi

  tar -xOf "${tar_path}" manifest.json 2>/dev/null \
    | grep -F "\"${IMAGE_REPOSITORY}:${IMAGE_TAG}\"" >/dev/null
}

update_install_metadata() {
  local image_name="$1"
  local image_tag
  local base_alias

  image_tag="${image_name##*:}"
  base_alias="${IMAGE_REPOSITORY}:base"
  docker tag "${image_name}" "${base_alias}"

  if [[ ! -f "${INSTALL_MARKER}" ]]; then
    printf 'Updated base alias: %s\n' "${base_alias}"
    return
  fi

  cat > "${INSTALL_IMAGE_PROFILE}" <<EOF
IMAGE_REPOSITORY="${IMAGE_REPOSITORY}"
IMAGE_TAG="${image_tag}"
EOF
  cat > "${INSTALL_COMPOSE_ENV}" <<EOF
OPENCODE_DEV_IMAGE=${image_name}
EOF
  printf 'Updated base alias: %s\n' "${base_alias}"
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
fi

existing_image="$(existing_image_ref)"
if [[ -n "${existing_image}" ]]; then
  update_install_metadata "${existing_image}"
  printf 'Docker image already exists: %s\n' "${existing_image}"
  printf 'Skipped image tar load.\n'
  exit 0
fi

tmp_dir="$(mktemp -d)"
tar_path="${tmp_dir}/opencode-dev-yuta.tar"
load_log="${tmp_dir}/docker-load.log"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

if [[ $# -eq 1 ]]; then
  assert_docker_imgs_tar "$1"
  image_source="$1"
else
  image_source="$(find_image_tar)"
  printf 'Found image tar: %s\n' "${image_source}"
fi

copy_tar "${image_source}" "${tar_path}"

if ! tar_contains_expected_image "${tar_path}"; then
  printf 'Image tar does not contain the expected image: %s:%s\n' "${IMAGE_REPOSITORY}" "${IMAGE_TAG}" >&2
  exit 1
fi

docker load --input "${tar_path}" | tee "${load_log}"
image_name="$(loaded_image_ref < "${load_log}")"

if [[ -z "${image_name}" ]]; then
  if [[ -n "${IMAGE_TAG:-}" ]]; then
    printf 'The tar did not load the expected image: %s:%s\n' "${IMAGE_REPOSITORY}" "${IMAGE_TAG}" >&2
  else
    printf 'The tar did not load an image named %s:<version>.\n' "${IMAGE_REPOSITORY}" >&2
  fi
  exit 1
fi

docker image inspect "${image_name}" >/dev/null
update_install_metadata "${image_name}"

printf 'Installed image: %s\n' "${image_name}"
if [[ -f "${INSTALL_MARKER}" ]]; then
  printf 'Updated installed image profile: %s\n' "${INSTALL_IMAGE_PROFILE}"
  printf 'Updated installed compose env: %s\n' "${INSTALL_COMPOSE_ENV}"
fi
