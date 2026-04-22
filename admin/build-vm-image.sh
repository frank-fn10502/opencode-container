#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEVCONTAINER_DIR="${PROJECT_ROOT}/.devcontainer"
DOCKERFILE_DIR="${DEVCONTAINER_DIR}/docker"
IMAGE_PROFILE="${DEVCONTAINER_DIR}/image.profile"
IMAGE_REPOSITORY="localhost/opencode-dev-yuta"
OPENCODE_VERSION=""
ENV_REVISION=""
IMAGE_TAG=""
OPENCODE_DEV_IMAGE=""
VM_REVISION=""

if [[ -f "${IMAGE_PROFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${IMAGE_PROFILE}"
fi

usage() {
  cat <<'USAGE'
Usage: admin/build-vm-image.sh [--dockerfile FILE] [--vm-revision N] [--build-arg KEY=VALUE]...

Build the OpenCode VM image as a thin layer on top of
localhost/opencode-dev-yuta:base, tag it as
localhost/opencode-dev-yuta:<opencode-version>-env.<revision>-vm.<vm-revision>,
and save it under .docker_imgs/.

Options:
  --dockerfile FILE
              Build from a Dockerfile under .devcontainer/docker/.
              Default: Dockerfile.vm
  --vm-revision N
              Set the VM image revision. Default: keep image.profile VM_REVISION,
              or use 1 if it is not set.
  --build-arg KEY=VALUE
              Pass through one build arg. Repeatable.
  -h, --help  Show this help.
USAGE
}

extract_version() {
  grep -Eo '[0-9]+(\.[0-9]+)+([-+._A-Za-z0-9]*)?' | head -n 1
}

dockerfile_name="Dockerfile.vm"
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
    --vm-revision)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --vm-revision\n' >&2
        exit 2
      fi
      VM_REVISION="$2"
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

dockerfile_path="${DOCKERFILE_DIR}/${dockerfile_name}"
if [[ ! -f "${dockerfile_path}" ]]; then
  printf 'Dockerfile not found: %s\n' "${dockerfile_path}" >&2
  exit 1
fi

if [[ -z "${OPENCODE_VERSION:-}" || -z "${ENV_REVISION:-}" || -z "${IMAGE_TAG:-}" || -z "${OPENCODE_DEV_IMAGE:-}" ]]; then
  printf 'image.profile is missing OPENCODE_VERSION, ENV_REVISION, IMAGE_TAG, or OPENCODE_DEV_IMAGE.\n' >&2
  printf 'Build the base image first with: ./admin/build-image.sh\n' >&2
  exit 1
fi

VM_REVISION="${VM_REVISION:-1}"
VM_IMAGE_TAG="${IMAGE_TAG}-vm.${VM_REVISION}"
vm_image_name="${IMAGE_REPOSITORY}:${VM_IMAGE_TAG}"
vm_alias="${IMAGE_REPOSITORY}:vm"
base_alias="${IMAGE_REPOSITORY}:base"
temp_tag="${IMAGE_REPOSITORY}:build-vm-temp"

if ! docker image inspect "${OPENCODE_DEV_IMAGE}" >/dev/null 2>&1; then
  printf 'Base image not found: %s\n' "${OPENCODE_DEV_IMAGE}" >&2
  printf 'Load or build the base image before building the VM image.\n' >&2
  exit 1
fi

docker tag "${OPENCODE_DEV_IMAGE}" "${base_alias}" >/dev/null

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

docker_build_cmd+=("${DEVCONTAINER_DIR}")
"${docker_build_cmd[@]}"

version_output="$(docker run --rm "${temp_tag}" opencode --version)"
detected_version="$(printf '%s\n' "${version_output}" | extract_version)"

if [[ "${detected_version}" != "${OPENCODE_VERSION}" ]]; then
  printf 'OpenCode version mismatch.\n' >&2
  printf '  image.profile: %s\n' "${OPENCODE_VERSION}" >&2
  printf '  VM image:      %s\n' "${detected_version:-unknown}" >&2
  exit 1
fi

docker tag "${temp_tag}" "${vm_image_name}"
docker tag "${vm_image_name}" "${vm_alias}"

mkdir -p "${PROJECT_ROOT}/.docker_imgs"
tar_path="${PROJECT_ROOT}/.docker_imgs/opencode-dev-yuta-${VM_IMAGE_TAG}.tar"

cat > "${IMAGE_PROFILE}" <<EOF
IMAGE_REPOSITORY=${IMAGE_REPOSITORY}
OPENCODE_VERSION=${OPENCODE_VERSION}
ENV_REVISION=${ENV_REVISION}
IMAGE_TAG=${IMAGE_TAG}
OPENCODE_DEV_IMAGE=${OPENCODE_DEV_IMAGE}
VM_REVISION=${VM_REVISION}
VM_IMAGE_TAG=${VM_IMAGE_TAG}
OPENCODE_VM_IMAGE=${vm_image_name}
EOF

printf 'Saving %s to %s\n' "${vm_image_name}" "${tar_path}"
docker save --output "${tar_path}" "${vm_image_name}"

printf 'Built VM image: %s\n' "${vm_image_name}"
printf 'Updated VM alias: %s\n' "${vm_alias}"
printf 'Wrote image profile: %s\n' "${IMAGE_PROFILE}"
printf 'Wrote tar: %s\n' "${tar_path}"
