#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../common.sh
source "${SCRIPT_DIR}/../common.sh"

image_usage() {
  cat <<'USAGE'
Usage: opencode-dev image list
       opencode-dev image rm [--yes] <name:tag>

Commands:
  list
      List local opencode-dev images.

  rm <name:tag>
      Remove one explicitly named image.
      Example: opencode-dev image rm localhost/opencode-dev-yuta:1.4.7

Options:
  -y, --yes
      Do not ask for confirmation before docker image rm.
USAGE
}

image_in_use_count() {
  local image="$1"

  docker ps -a --filter "ancestor=${image}" --format '{{.ID}}' | wc -l | tr -d '[:space:]'
}

image_full_id() {
  local image="$1"

  docker image inspect "${image}" --format '{{.Id}}' 2>/dev/null || true
}

append_note() {
  local existing="$1"
  local addition="$2"

  if [[ -n "${existing}" ]]; then
    printf '%s,%s\n' "${existing}" "${addition}"
  else
    printf '%s\n' "${addition}"
  fi
}

image_note() {
  local image="$1"
  local current_image base_alias vm_image vm_alias current_id base_alias_id vm_id vm_alias_id image_id in_use notes

  current_image="$(base_image_ref)"
  base_alias="$(base_alias_ref)"
  vm_image="$(vm_image_ref 2>/dev/null || true)"
  vm_alias="$(vm_alias_ref)"
  current_id="$(image_full_id "${current_image}")"
  base_alias_id="$(image_full_id "${base_alias}")"
  vm_id="$(image_full_id "${vm_image}")"
  vm_alias_id="$(image_full_id "${vm_alias}")"
  image_id="$(image_full_id "${image}")"
  in_use="$(image_in_use_count "${image}")"
  notes=""

  if [[ "${image}" == "${current_image}" ]]; then
    notes="$(append_note "${notes}" "protected")"
    notes="$(append_note "${notes}" "current-base")"
    if [[ -n "${base_alias_id}" && "${image_id}" == "${base_alias_id}" ]]; then
      notes="$(append_note "${notes}" "alias=${base_alias}")"
    fi
  fi
  if [[ "${image}" == "${base_alias}" ]]; then
    notes="$(append_note "${notes}" "protected")"
    notes="$(append_note "${notes}" "base-alias")"
    if [[ -n "${current_id}" && "${image_id}" == "${current_id}" ]]; then
      notes="$(append_note "${notes}" "current=${current_image}")"
    fi
  fi
  if [[ -n "${vm_image}" && "${image}" == "${vm_image}" ]]; then
    notes="$(append_note "${notes}" "protected")"
    notes="$(append_note "${notes}" "current-vm")"
    if [[ -n "${vm_alias_id}" && "${image_id}" == "${vm_alias_id}" ]]; then
      notes="$(append_note "${notes}" "alias=${vm_alias}")"
    fi
  fi
  if [[ "${image}" == "${vm_alias}" ]]; then
    notes="$(append_note "${notes}" "protected")"
    notes="$(append_note "${notes}" "vm-alias")"
    if [[ -n "${vm_id}" && "${image_id}" == "${vm_id}" ]]; then
      notes="$(append_note "${notes}" "current=${vm_image}")"
    fi
  fi
  if [[ "${in_use}" != "0" ]]; then
    notes="$(append_note "${notes}" "containers=${in_use}")"
  fi

  printf '%s\n' "${notes:-"-"}"
}

list_images() {
  local line image image_id created size note found=0

  ensure_image_profile
  printf 'Repository: %s\n' "${IMAGE_REPOSITORY}"
  printf 'Configured image: %s\n\n' "$(base_image_ref)"
  printf '%-44s %-12s %-22s %-10s %s\n' "IMAGE" "IMAGE ID" "CREATED" "SIZE" "NOTE"

  while IFS=$'\t' read -r image image_id created size; do
    if [[ -z "${image}" ]]; then
      continue
    fi
    note="$(image_note "${image}")"
    printf '%-44s %-12s %-22s %-10s %s\n' "${image}" "${image_id}" "${created}" "${size}" "${note}"
    found=1
  done < <(
    docker image ls "${IMAGE_REPOSITORY}" \
      --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}' \
      | awk -F '\t' '$1 !~ /:<none>$/'
  )

  if [[ "${found}" -eq 0 ]]; then
    printf '(none)\n'
  fi
}

validate_image_ref() {
  local image="$1"
  local repo tag

  case "${image}" in
    *:*)
      ;;
    *)
      printf 'Image must be a full name:tag reference, for example %s:1.4.7\n' "${IMAGE_REPOSITORY}" >&2
      exit 2
      ;;
  esac

  repo="${image%:*}"
  tag="${image##*:}"
  if [[ "${repo}" != "${IMAGE_REPOSITORY}" || -z "${tag}" || "${tag}" == "${image}" ]]; then
    printf 'Refusing to manage image outside %s: %s\n' "${IMAGE_REPOSITORY}" "${image}" >&2
    exit 2
  fi
}

confirm_image_rm() {
  local image="$1"
  local answer

  printf 'Remove Docker image %s? [Yes/No] ' "${image}" >&2
  read -r answer
  case "${answer}" in
    Yes)
      return 0
      ;;
    No|"")
      printf 'Aborted. Image was left untouched: %s\n' "${image}" >&2
      return 1
      ;;
    *)
      printf 'Please type Yes or No. Image was left untouched: %s\n' "${image}" >&2
      return 1
      ;;
  esac
}

rm_image() {
  local assume_yes=0
  local image=""
  local current_image base_alias vm_image vm_alias current_id base_alias_id vm_id vm_alias_id image_id

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)
        assume_yes=1
        shift
        ;;
      -h|--help)
        image_usage
        exit 0
        ;;
      -*)
        printf 'Unknown option for image rm: %s\n' "$1" >&2
        image_usage >&2
        exit 2
        ;;
      *)
        if [[ -n "${image}" ]]; then
          printf 'Too many image arguments for image rm.\n' >&2
          image_usage >&2
          exit 2
        fi
        image="$1"
        shift
        ;;
    esac
  done

  if [[ -z "${image}" ]]; then
    printf 'Missing image for image rm.\n' >&2
    image_usage >&2
    exit 2
  fi

  ensure_image_profile
  validate_image_ref "${image}"
  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    printf 'Image not found: %s\n' "${image}" >&2
    exit 1
  fi

  current_image="$(base_image_ref)"
  base_alias="$(base_alias_ref)"
  vm_image="$(vm_image_ref 2>/dev/null || true)"
  vm_alias="$(vm_alias_ref)"
  current_id="$(image_full_id "${current_image}")"
  base_alias_id="$(image_full_id "${base_alias}")"
  vm_id="$(image_full_id "${vm_image}")"
  vm_alias_id="$(image_full_id "${vm_alias}")"
  image_id="$(image_full_id "${image}")"
  if [[ "${image}" == "${current_image}" ]]; then
    printf 'Refusing to remove current base image: %s\n' "${image}" >&2
    printf 'Reason: this Docker image is the base of the current opencode virtual environment.\n' >&2
    if [[ -n "${base_alias_id}" && "${image_id}" == "${base_alias_id}" ]]; then
      printf 'Relation: %s and %s refer to the same Docker image.\n' "${current_image}" "${base_alias}" >&2
    fi
    printf 'Remove an older image tag instead.\n' >&2
    exit 2
  fi
  if [[ "${image}" == "${base_alias}" ]]; then
    printf 'Refusing to remove base alias: %s\n' "${image}" >&2
    printf 'Reason: this Docker image is the stable base alias for opencode virtual environments.\n' >&2
    if [[ -n "${current_id}" && "${image_id}" == "${current_id}" ]]; then
      printf 'Relation: %s and %s refer to the same Docker image.\n' "${base_alias}" "${current_image}" >&2
    fi
    printf 'Remove an older image tag instead.\n' >&2
    exit 2
  fi
  if [[ -n "${vm_image}" && "${image}" == "${vm_image}" ]]; then
    printf 'Refusing to remove current VM image: %s\n' "${image}" >&2
    printf 'Reason: this Docker image is used by opencode-vm.\n' >&2
    if [[ -n "${vm_alias_id}" && "${image_id}" == "${vm_alias_id}" ]]; then
      printf 'Relation: %s and %s refer to the same Docker image.\n' "${vm_image}" "${vm_alias}" >&2
    fi
    printf 'Remove an older image tag instead.\n' >&2
    exit 2
  fi
  if [[ "${image}" == "${vm_alias}" ]]; then
    printf 'Refusing to remove VM alias: %s\n' "${image}" >&2
    printf 'Reason: this Docker image is the stable VM alias for opencode-vm.\n' >&2
    if [[ -n "${vm_id}" && "${image_id}" == "${vm_id}" ]]; then
      printf 'Relation: %s and %s refer to the same Docker image.\n' "${vm_alias}" "${vm_image}" >&2
    fi
    printf 'Remove an older image tag instead.\n' >&2
    exit 2
  fi

  if [[ "${assume_yes}" -ne 1 ]]; then
    confirm_image_rm "${image}" || exit 1
  fi

  docker image rm "${image}"
}

command_name="${1:-}"
case "${command_name}" in
  list)
    shift || true
    if [[ $# -gt 0 ]]; then
      printf 'opencode-dev image list does not accept extra arguments.\n' >&2
      image_usage >&2
      exit 2
    fi
    list_images
    ;;
  rm)
    shift || true
    rm_image "$@"
    ;;
  ""|-h|--help)
    image_usage
    ;;
  *)
    printf 'Unknown image command: %s\n' "${command_name}" >&2
    image_usage >&2
    exit 2
    ;;
esac
