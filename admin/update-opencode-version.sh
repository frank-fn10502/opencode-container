#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEVCONTAINER_DIR="${PROJECT_ROOT}/.devcontainer"
IMAGE_PROFILE="${DEVCONTAINER_DIR}/image.profile"
IMAGE_REPOSITORY="localhost/opencode-dev-yuta"
OPENCODE_VERSION=""
ENV_REVISION="1"
VM_REVISION=""

if [[ -f "${IMAGE_PROFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${IMAGE_PROFILE}"
fi

usage() {
  cat <<'USAGE'
Usage: admin/update-opencode-version.sh [--dockerfile FILE] [--env-revision N] [--build-arg KEY=VALUE]...

Build a temporary OpenCode dev image with OPENCODE_VERSION=latest, detect the
installed OpenCode version, and write that pinned version back to image.profile.
This is intended for the release host only. Normal hosts should run
build-image.sh, which uses the pinned version from image.profile.

Options:
  --dockerfile FILE
              Build from a Dockerfile under .devcontainer/.
              Default: Dockerfile.insecure
  --env-revision N
              Set the environment revision for the resolved OpenCode version.
              Default: keep the current revision if the OpenCode version is
              unchanged; otherwise reset to 1.
  --build-arg KEY=VALUE
              Pass through one build arg. Repeatable.
  -h, --help  Show this help.
USAGE
}

extract_version() {
  grep -Eo '[0-9]+(\.[0-9]+)+([-+._A-Za-z0-9]*)?' | head -n 1
}

dockerfile_name="Dockerfile.insecure"
requested_env_revision=""
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
    --env-revision)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --env-revision\n' >&2
        exit 2
      fi
      requested_env_revision="$2"
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

if [[ -n "${requested_env_revision}" && ! "${requested_env_revision}" =~ ^[1-9][0-9]*$ ]]; then
  printf 'ENV revision must be a positive integer: %s\n' "${requested_env_revision}" >&2
  exit 2
fi

dockerfile_path="${DEVCONTAINER_DIR}/${dockerfile_name}"
if [[ ! -f "${dockerfile_path}" ]]; then
  printf 'Dockerfile not found: %s\n' "${dockerfile_path}" >&2
  exit 1
fi

temp_tag="${IMAGE_REPOSITORY}:resolve-opencode-version"

cleanup() {
  docker image rm "${temp_tag}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'Building temporary image %s from %s\n' "${temp_tag}" "${dockerfile_path}"
docker_build_cmd=(
  docker build
  --tag "${temp_tag}"
  --file "${dockerfile_path}"
)

if (( ${#build_args[@]} > 0 )); then
  docker_build_cmd+=("${build_args[@]}")
fi

docker_build_cmd+=("--build-arg" "OPENCODE_VERSION=latest")
docker_build_cmd+=("${DEVCONTAINER_DIR}")

"${docker_build_cmd[@]}"

version_output="$(docker run --rm "${temp_tag}" opencode --version)"
detected_version="$(printf '%s\n' "${version_output}" | extract_version)"

if [[ -z "${detected_version}" ]]; then
  printf 'Unable to detect OpenCode version from: %s\n' "${version_output}" >&2
  exit 1
fi

if [[ -n "${requested_env_revision}" ]]; then
  next_env_revision="${requested_env_revision}"
elif [[ "${detected_version}" == "${OPENCODE_VERSION:-}" ]]; then
  next_env_revision="${ENV_REVISION:-1}"
else
  next_env_revision="1"
fi

image_tag="${detected_version}-env.${next_env_revision}"
VM_REVISION="${VM_REVISION:-1}"
vm_image_tag="${image_tag}-vm.${VM_REVISION}"

cat > "${IMAGE_PROFILE}" <<EOF
IMAGE_REPOSITORY=${IMAGE_REPOSITORY}
OPENCODE_VERSION=${detected_version}
ENV_REVISION=${next_env_revision}
IMAGE_TAG=${image_tag}
OPENCODE_DEV_IMAGE=${IMAGE_REPOSITORY}:${image_tag}
VM_REVISION=${VM_REVISION}
VM_IMAGE_TAG=${vm_image_tag}
OPENCODE_VM_IMAGE=${IMAGE_REPOSITORY}:${vm_image_tag}
EOF

printf 'Detected OpenCode version: %s\n' "${detected_version}"
printf 'Set environment revision: %s\n' "${next_env_revision}"
printf 'Updated image tag: %s\n' "${image_tag}"
printf 'Wrote image profile: %s\n' "${IMAGE_PROFILE}"
