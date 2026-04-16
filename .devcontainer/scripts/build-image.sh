#!/usr/bin/env bash

set -euo pipefail

# Resolve the script directory so the command works from any current path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Allow callers to override the image tag, but keep a predictable default.
# The localhost prefix makes it explicit that compose should only use a local
# image reference and never fall back to Docker Hub semantics.
IMAGE_NAME="${1:-localhost/opencode-dev:local}"

echo "Building ${IMAGE_NAME} from ${DEVCONTAINER_DIR}/Dockerfile"

# Build using .devcontainer as the context so all container assets stay inside
# that directory, matching the repository layout requested for this project.
docker build \
  --tag "${IMAGE_NAME}" \
  --file "${DEVCONTAINER_DIR}/Dockerfile" \
  "${DEVCONTAINER_DIR}"
