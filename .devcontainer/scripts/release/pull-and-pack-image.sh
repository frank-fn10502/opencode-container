#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROJECT_ROOT="$(cd "${DEVCONTAINER_DIR}/.." && pwd)"
IMAGE_PROFILE="${DEVCONTAINER_DIR}/image.profile"

DEFAULT_REMOTE_REPO="frank10502/opencode-dev-yuta"
DEFAULT_LOCAL_REPO="localhost/opencode-dev-yuta"

if [[ -f "${IMAGE_PROFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${IMAGE_PROFILE}"
fi

REMOTE_REPO="${DEFAULT_REMOTE_REPO}"
LOCAL_REPO="${IMAGE_REPOSITORY:-${DEFAULT_LOCAL_REPO}}"
TAG=""
OUTPUT_PATH=""

usage() {
  cat <<'USAGE'
Usage: .devcontainer/scripts/release/pull-and-pack-image.sh <tag> [--output PATH] [--remote-repo REPO] [--local-repo REPO]

Pull image from Docker Hub, retag to local repo naming, then save to tar.

Defaults:
  remote repo: frank10502/opencode-dev-yuta
  local repo:  localhost/opencode-dev-yuta (or IMAGE_REPOSITORY from .devcontainer/image.profile)
  output tar:  .docker_imgs/opencode-dev-yuta-<tag>.tar

Examples:
  ./.devcontainer/scripts/release/pull-and-pack-image.sh 1.4.7
  ./.devcontainer/scripts/release/pull-and-pack-image.sh 1.4.7 --output .docker_imgs/opencode-dev-yuta-1.4.7.tar
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --output\n' >&2
        exit 2
      fi
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --remote-repo)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --remote-repo\n' >&2
        exit 2
      fi
      REMOTE_REPO="$2"
      shift 2
      ;;
    --local-repo)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --local-repo\n' >&2
        exit 2
      fi
      LOCAL_REPO="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "${TAG}" ]]; then
        printf 'Only one tag is allowed. Got extra argument: %s\n' "$1" >&2
        usage >&2
        exit 2
      fi
      TAG="$1"
      shift
      ;;
  esac
done

if [[ -z "${TAG}" ]]; then
  printf 'Missing required <tag> argument\n' >&2
  usage >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  printf 'docker command not found\n' >&2
  exit 1
fi

if [[ -z "${OUTPUT_PATH}" ]]; then
  OUTPUT_PATH="${PROJECT_ROOT}/.docker_imgs/opencode-dev-yuta-${TAG}.tar"
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"

REMOTE_IMAGE="${REMOTE_REPO}:${TAG}"
LOCAL_IMAGE="${LOCAL_REPO}:${TAG}"

printf 'Pulling %s\n' "${REMOTE_IMAGE}"
docker pull "${REMOTE_IMAGE}"

printf 'Tagging %s -> %s\n' "${REMOTE_IMAGE}" "${LOCAL_IMAGE}"
docker tag "${REMOTE_IMAGE}" "${LOCAL_IMAGE}"

printf 'Saving %s to %s\n' "${LOCAL_IMAGE}" "${OUTPUT_PATH}"
docker save --output "${OUTPUT_PATH}" "${LOCAL_IMAGE}"

printf 'Done.\n'
printf 'Pulled image: %s\n' "${REMOTE_IMAGE}"
printf 'Restored local name: %s\n' "${LOCAL_IMAGE}"
printf 'Tar file: %s\n' "${OUTPUT_PATH}"
