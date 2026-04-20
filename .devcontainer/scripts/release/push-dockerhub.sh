#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IMAGE_PROFILE="${DEVCONTAINER_DIR}/image.profile"

DEFAULT_SOURCE_REPO="localhost/opencode-dev-yuta"
DEFAULT_TARGET_REPO="frank10502/opencode-dev-yuta"

if [[ -f "${IMAGE_PROFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${IMAGE_PROFILE}"
fi

SOURCE_REPO="${IMAGE_REPOSITORY:-${DEFAULT_SOURCE_REPO}}"
TARGET_REPO="${DEFAULT_TARGET_REPO}"
PUSH_LATEST=0
TAG=""

usage() {
  cat <<'USAGE'
Usage: .devcontainer/scripts/release/push-dockerhub.sh <tag> [--latest] [--target-repo REPO]

Tag and push local image to Docker Hub.

Defaults:
  source repo: localhost/opencode-dev-yuta (or IMAGE_REPOSITORY from .devcontainer/image.profile)
  target repo: frank10502/opencode-dev-yuta

Examples:
  ./.devcontainer/scripts/release/push-dockerhub.sh 1.4.7
  ./.devcontainer/scripts/release/push-dockerhub.sh 1.4.7 --latest
  ./.devcontainer/scripts/release/push-dockerhub.sh 1.4.7 --target-repo frank10502/opencode-dev-yuta
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --latest)
      PUSH_LATEST=1
      shift
      ;;
    --target-repo)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --target-repo\n' >&2
        exit 2
      fi
      TARGET_REPO="$2"
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

SOURCE_IMAGE="${SOURCE_REPO}:${TAG}"
TARGET_IMAGE="${TARGET_REPO}:${TAG}"

printf 'Checking local image: %s\n' "${SOURCE_IMAGE}"
if ! docker image inspect "${SOURCE_IMAGE}" >/dev/null 2>&1; then
  printf 'Local image not found: %s\n' "${SOURCE_IMAGE}" >&2
  printf 'Tip: build image first, or verify the tag with: docker images\n' >&2
  exit 1
fi

printf 'Tagging %s -> %s\n' "${SOURCE_IMAGE}" "${TARGET_IMAGE}"
docker tag "${SOURCE_IMAGE}" "${TARGET_IMAGE}"

printf 'Pushing %s\n' "${TARGET_IMAGE}"
docker push "${TARGET_IMAGE}"

if [[ "${PUSH_LATEST}" -eq 1 ]]; then
  TARGET_LATEST_IMAGE="${TARGET_REPO}:latest"
  printf 'Tagging %s -> %s\n' "${TARGET_IMAGE}" "${TARGET_LATEST_IMAGE}"
  docker tag "${TARGET_IMAGE}" "${TARGET_LATEST_IMAGE}"

  printf 'Pushing %s\n' "${TARGET_LATEST_IMAGE}"
  docker push "${TARGET_LATEST_IMAGE}"
fi

printf 'Done.\n'
