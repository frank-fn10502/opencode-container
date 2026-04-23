#!/usr/bin/env bash

INIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_INSTALL_OR_SCRIPTS_DIR="$(cd "${INIT_SCRIPT_DIR}/.." && pwd)"
if [[ -d "${INIT_INSTALL_OR_SCRIPTS_DIR}/compose" ]]; then
  INIT_DEVCONTAINER_DIR="${INIT_INSTALL_OR_SCRIPTS_DIR}"
  INIT_RUNTIME_SCRIPT_DIR="${INIT_DEVCONTAINER_DIR}/runtime"
else
  INIT_DEVCONTAINER_DIR="$(cd "${INIT_SCRIPT_DIR}/../.." && pwd)"
  INIT_RUNTIME_SCRIPT_DIR="${INIT_DEVCONTAINER_DIR}/scripts/runtime"
fi

INSTALL_DIR="${HOME}/.local/bin/opencode-dev-yuta"
INSTALL_MARKER="${INSTALL_DIR}/.opencode-dev-managed"
INSTALL_PROFILE="${INSTALL_DIR}/.profile"
IMAGE_PROFILE="${INIT_DEVCONTAINER_DIR}/image.profile"
MARKER_BEGIN="# >>> opencode-dev >>>"
MARKER_END="# <<< opencode-dev <<<"

detect_shell_profile() {
  local shell_name

  shell_name="$(basename "${SHELL:-}")"
  case "${shell_name}" in
    zsh)
      printf '%s/.zshrc' "${HOME}"
      ;;
    bash)
      if [[ "$(uname -s)" == "Darwin" ]]; then
        printf '%s/.bash_profile' "${HOME}"
      else
        printf '%s/.bashrc' "${HOME}"
      fi
      ;;
    *)
      printf '%s/.profile' "${HOME}"
      ;;
  esac
}

expand_profile_path() {
  local path="$1"

  case "${path}" in
    \~)
      printf '%s\n' "${HOME}"
      ;;
    \~/*)
      printf '%s/%s\n' "${HOME}" "${path#"~/"}"
      ;;
    *)
      printf '%s\n' "${path}"
      ;;
  esac
}

strip_installed_block() {
  local profile="$1"
  local output="$2"

  awk -v begin="${MARKER_BEGIN}" -v end="${MARKER_END}" '
    $0 == begin { skip = 1; found = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
    END { exit found ? 0 : 2 }
  ' "${profile}" > "${output}"
}

installed_profile_or_detect() {
  if [[ -f "${INSTALL_PROFILE}" ]]; then
    sed -n '1p' "${INSTALL_PROFILE}"
  else
    detect_shell_profile
  fi
}

remove_profile_block() {
  local profile="$1"
  local tmp

  if [[ -f "${profile}" ]]; then
    tmp="$(mktemp)"
    if strip_installed_block "${profile}" "${tmp}"; then
      cat "${tmp}" > "${profile}"
      printf 'Removed opencode-dev profile block from %s\n' "${profile}"
    else
      printf 'No opencode-dev profile block found in %s\n' "${profile}"
    fi
    rm -f "${tmp}"
  else
    printf 'No profile found at %s\n' "${profile}"
  fi
}

remove_managed_install_dir() {
  if [[ -e "${INSTALL_DIR}" && ! -f "${INSTALL_MARKER}" ]]; then
    printf 'Refusing to manage existing unmarked directory: %s\n' "${INSTALL_DIR}" >&2
    printf 'Move it away or remove it before installing or uninstalling opencode-dev.\n' >&2
    exit 1
  fi

  if [[ -f "${INSTALL_MARKER}" ]]; then
    if ! rm -rf "${INSTALL_DIR}"; then
      printf 'Failed to remove managed install directory: %s\n' "${INSTALL_DIR}" >&2
      exit 1
    fi
    return 0
  fi

  if [[ -e "${INSTALL_DIR}" ]]; then
    printf 'Skipped unmarked install directory at %s\n' "${INSTALL_DIR}" >&2
    exit 1
  fi

  return 1
}

reset_install_dir() {
  remove_managed_install_dir || true

  mkdir -p \
    "${INSTALL_DIR}/bin" \
    "${INSTALL_DIR}/runtime" \
    "${INSTALL_DIR}/runtime/dev" \
    "${INSTALL_DIR}/runtime/vm" \
    "${INSTALL_DIR}/init" \
    "${INSTALL_DIR}/compose" \
    "${INSTALL_DIR}/config" \
    "${INSTALL_DIR}/profile"
}

install_common_runtime() {
  cp "${INIT_RUNTIME_SCRIPT_DIR}/common.sh" "${INSTALL_DIR}/runtime/common.sh"
  cp "${INIT_SCRIPT_DIR}/init-common.sh" "${INSTALL_DIR}/init/init-common.sh"
  cp "${INIT_SCRIPT_DIR}/init-opencode.sh" "${INSTALL_DIR}/init/init-opencode.sh"
  cp "${INIT_SCRIPT_DIR}/init-opencode-dev.sh" "${INSTALL_DIR}/init/init-opencode-dev.sh"
  cp "${INIT_SCRIPT_DIR}/init-opencode-vm.sh" "${INSTALL_DIR}/init/init-opencode-vm.sh"
  cp "${INIT_SCRIPT_DIR}/install-image.sh" "${INSTALL_DIR}/init/install-image.sh"
  cp "${INIT_DEVCONTAINER_DIR}/compose/docker-compose.dev.yml" "${INSTALL_DIR}/compose/docker-compose.dev.yml"
  cp "${INIT_DEVCONTAINER_DIR}/compose/docker-compose.vm.yml" "${INSTALL_DIR}/compose/docker-compose.vm.yml"
  cp "${INIT_DEVCONTAINER_DIR}/config/opencode.json" "${INSTALL_DIR}/config/opencode.json"
  cp "${INIT_DEVCONTAINER_DIR}/config/AGENTS.md" "${INSTALL_DIR}/config/AGENTS.md"
  cp -R "${INIT_DEVCONTAINER_DIR}/config/command" "${INSTALL_DIR}/config/command"
  cp "${INIT_DEVCONTAINER_DIR}/profile/profile-dockerfile-guide.md" "${INSTALL_DIR}/profile/profile-dockerfile-guide.md"
  cp "${INIT_DEVCONTAINER_DIR}/profile/project-profile-readme.md" "${INSTALL_DIR}/profile/project-profile-readme.md"
  cp -R "${INIT_DEVCONTAINER_DIR}/profile/user-profiles" "${INSTALL_DIR}/profile/user-profiles"
  cp "${IMAGE_PROFILE}" "${INSTALL_DIR}/image.profile"

  chmod 644 "${INSTALL_DIR}/runtime/common.sh"
  chmod 755 "${INSTALL_DIR}/init/init-opencode.sh"
  chmod 644 "${INSTALL_DIR}/init/init-opencode-dev.sh"
  chmod 644 "${INSTALL_DIR}/init/init-opencode-vm.sh"
  chmod 755 "${INSTALL_DIR}/init/install-image.sh"
}

write_install_marker() {
  local profile="$1"

  printf '%s\n' "${profile}" > "${INSTALL_PROFILE}"
  printf 'managed by init-opencode.sh\n' > "${INSTALL_MARKER}"
}
