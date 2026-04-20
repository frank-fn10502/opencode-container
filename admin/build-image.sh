#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEVCONTAINER_DIR="${PROJECT_ROOT}/.devcontainer"
IMAGE_PROFILE="${DEVCONTAINER_DIR}/image.profile"
IMAGE_REPOSITORY="localhost/opencode-dev-yuta"
OPENCODE_VERSION=""
ENV_REVISION=""
IMAGE_TAG=""

if [[ -f "${IMAGE_PROFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${IMAGE_PROFILE}"
fi

usage() {
  cat <<'USAGE'
Usage: admin/build-image.sh [--dockerfile FILE] [--build-arg KEY=VALUE]...

Build the OpenCode dev image from the version pinned in image.profile, verify
the installed OpenCode version, tag the image as
localhost/opencode-dev-yuta:<opencode-version>-env.<revision>, and save it
under .docker_imgs/.

Options:
  --dockerfile FILE
              Build from a Dockerfile under .devcontainer/.
              Default: Dockerfile.insecure
  --build-arg KEY=VALUE
              Pass through one build arg. Repeatable.
  -h, --help    Show this help.
USAGE
}

extract_version() {
  grep -Eo '[0-9]+(\.[0-9]+)+([-+._A-Za-z0-9]*)?' | head -n 1
}

dockerfile_name="Dockerfile.insecure"
build_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dockerfile)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --dockerfile\n' >&2
        exit 2
      fi
      dockerfile_name="$2"
      shift 2
      ;;
    --build-arg)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --build-arg\n' >&2
        exit 2
      fi
      build_args+=("--build-arg" "$2")
      shift 2
      ;;
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

dockerfile_name="${dockerfile_name:-Dockerfile}"
dockerfile_path="${DEVCONTAINER_DIR}/${dockerfile_name}"

if [[ ! -f "${dockerfile_path}" ]]; then
  printf 'Dockerfile not found: %s\n' "${dockerfile_path}" >&2
  exit 1
fi

if [[ -z "${OPENCODE_VERSION:-}" ]]; then
  printf 'OPENCODE_VERSION is not set in %s\n' "${IMAGE_PROFILE}" >&2
  printf 'Run update-opencode-version.sh on the release host, or set it manually.\n' >&2
  exit 1
fi

if [[ -z "${ENV_REVISION:-}" ]]; then
  printf 'ENV_REVISION is not set in %s\n' "${IMAGE_PROFILE}" >&2
  exit 1
fi

IMAGE_TAG="${OPENCODE_VERSION}-env.${ENV_REVISION}"
temp_tag="${IMAGE_REPOSITORY}:build-temp"

cleanup() {
  docker image rm "${temp_tag}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'Building %s from %s\n' "${temp_tag}" "${dockerfile_path}"
docker_build_cmd=(
  docker build
  --tag "${temp_tag}"
  --file "${dockerfile_path}"
)

if (( ${#build_args[@]} > 0 )); then
  docker_build_cmd+=("${build_args[@]}")
fi

docker_build_cmd+=("--build-arg" "OPENCODE_VERSION=${OPENCODE_VERSION}")
docker_build_cmd+=("${DEVCONTAINER_DIR}")

"${docker_build_cmd[@]}"

version_output="$(docker run --rm "${temp_tag}" opencode --version)"
detected_version="$(printf '%s\n' "${version_output}" | extract_version)"

if [[ -z "${detected_version}" ]]; then
  printf 'Unable to detect OpenCode version from: %s\n' "${version_output}" >&2
  exit 1
fi

if [[ "${detected_version}" != "${OPENCODE_VERSION}" ]]; then
  printf 'OpenCode version mismatch.\n' >&2
  printf '  image.profile: %s\n' "${OPENCODE_VERSION}" >&2
  printf '  built image:    %s\n' "${detected_version}" >&2
  exit 1
fi

image_name="${IMAGE_REPOSITORY}:${IMAGE_TAG}"
base_alias="${IMAGE_REPOSITORY}:base"
docker tag "${temp_tag}" "${image_name}"
docker tag "${image_name}" "${base_alias}"

mkdir -p "${PROJECT_ROOT}/.docker_imgs"
tar_path="${PROJECT_ROOT}/.docker_imgs/opencode-dev-yuta-${IMAGE_TAG}.tar"

cat > "${IMAGE_PROFILE}" <<EOF
IMAGE_REPOSITORY=${IMAGE_REPOSITORY}
OPENCODE_VERSION=${OPENCODE_VERSION}
ENV_REVISION=${ENV_REVISION}
IMAGE_TAG=${IMAGE_TAG}
OPENCODE_DEV_IMAGE=${image_name}
EOF
printf 'Saving %s to %s\n' "${image_name}" "${tar_path}"
docker save --output "${tar_path}" "${image_name}"

printf 'Built image: %s\n' "${image_name}"
printf 'Updated base alias: %s\n' "${base_alias}"
printf 'Wrote image profile: %s\n' "${IMAGE_PROFILE}"
printf 'Wrote tar: %s\n' "${tar_path}"
