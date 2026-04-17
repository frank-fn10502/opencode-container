#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${DEVCONTAINER_DIR}/.." && pwd)"
IMAGE_PROFILE="${DEVCONTAINER_DIR}/image.profile"
COMPOSE_ENV="${DEVCONTAINER_DIR}/compose.env"
IMAGE_REPOSITORY="localhost/opencode-dev-yuta"

if [[ -f "${IMAGE_PROFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${IMAGE_PROFILE}"
fi

usage() {
  cat <<'USAGE'
Usage: build-image.sh

Build the OpenCode dev image from .devcontainer/Dockerfile, detect the installed
OpenCode version, tag the image as localhost/opencode-dev-yuta:<version>, and
save it under .docker_imgs/.

Options:
  -h, --help    Show this help.
USAGE
}

extract_version() {
  grep -Eo '[0-9]+(\.[0-9]+)+([-+._A-Za-z0-9]*)?' | head -n 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

temp_tag="${IMAGE_REPOSITORY}:build-temp"

printf 'Building %s from %s\n' "${temp_tag}" "${DEVCONTAINER_DIR}/Dockerfile"
docker build \
  --tag "${temp_tag}" \
  --file "${DEVCONTAINER_DIR}/Dockerfile" \
  "${DEVCONTAINER_DIR}"

version_output="$(docker run --rm "${temp_tag}" opencode --version)"
version="$(printf '%s\n' "${version_output}" | extract_version)"

if [[ -z "${version}" ]]; then
  printf 'Unable to detect OpenCode version from: %s\n' "${version_output}" >&2
  exit 1
fi

image_name="${IMAGE_REPOSITORY}:${version}"
docker tag "${temp_tag}" "${image_name}"

mkdir -p "${PROJECT_ROOT}/.docker_imgs"
tar_path="${PROJECT_ROOT}/.docker_imgs/opencode-dev-yuta-${version}.tar"

cat > "${IMAGE_PROFILE}" <<EOF
IMAGE_REPOSITORY="${IMAGE_REPOSITORY}"
IMAGE_TAG="${version}"
EOF
cat > "${COMPOSE_ENV}" <<EOF
OPENCODE_DEV_IMAGE=${image_name}
EOF
printf 'Saving %s to %s\n' "${image_name}" "${tar_path}"
docker save --output "${tar_path}" "${image_name}"
docker image rm "${temp_tag}" >/dev/null 2>&1 || true

printf 'Built image: %s\n' "${image_name}"
printf 'Wrote image profile: %s\n' "${IMAGE_PROFILE}"
printf 'Wrote compose env: %s\n' "${COMPOSE_ENV}"
printf 'Wrote tar: %s\n' "${tar_path}"
