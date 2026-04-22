#!/usr/bin/env bash

set -euo pipefail

OPENCODE_USER="${OPENCODE_USER:-opencode}"
OPENCODE_BASE_USER="${OPENCODE_BASE_USER:-opencode}"
OPENCODE_HOME_DIR="${OPENCODE_HOME_DIR:-/home/opencode}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"

if [[ -n "${PYTHON_VENV:-}" && -d "${PYTHON_VENV}/bin" ]]; then
  export PATH="${PYTHON_VENV}/bin:${OPENCODE_HOME_DIR}/.local/bin:${PATH}"
fi

ensure_opencode_user() {
  if id -u "${OPENCODE_USER}" >/dev/null 2>&1; then
    return
  fi

  if ! id -u "${OPENCODE_BASE_USER}" >/dev/null 2>&1; then
    echo "[opencode-entrypoint] user not found: ${OPENCODE_USER}" >&2
    exit 1
  fi

  if getent group "${OPENCODE_BASE_USER}" >/dev/null 2>&1 \
    && ! getent group "${OPENCODE_USER}" >/dev/null 2>&1; then
    groupmod -n "${OPENCODE_USER}" "${OPENCODE_BASE_USER}"
  fi

  usermod -l "${OPENCODE_USER}" -d "${OPENCODE_HOME_DIR}" "${OPENCODE_BASE_USER}"
  usermod -aG sudo "${OPENCODE_USER}" >/dev/null 2>&1 || true
  echo "${OPENCODE_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${OPENCODE_USER}"
  chmod 0440 "/etc/sudoers.d/${OPENCODE_USER}"
}

find_available_uid() {
  local uid_candidate

  for uid_candidate in $(seq 2000 65000); do
    if ! getent passwd "${uid_candidate}" >/dev/null; then
      printf '%s\n' "${uid_candidate}"
      return 0
    fi
  done

  return 1
}

sync_workspace_identity() {
  local target_uid target_gid
  local current_uid current_gid
  local existing_user existing_group

  if [[ ! -e "${WORKSPACE_DIR}" ]]; then
    return
  fi

  if [[ "${OPENCODE_INIT_WORKSPACE_OWNERSHIP:-}" == "1" ]]; then
    chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "${WORKSPACE_DIR}" >/dev/null 2>&1 || true
    chown -R "${OPENCODE_USER}:$(id -gn "${OPENCODE_USER}")" \
      "${OPENCODE_HOME_DIR}/.local" \
      "${OPENCODE_HOME_DIR}/.cache" \
      "${OPENCODE_HOME_DIR}/.ssh" >/dev/null 2>&1 || true
    return
  fi

  target_uid="$(stat -c '%u' "${WORKSPACE_DIR}")"
  target_gid="$(stat -c '%g' "${WORKSPACE_DIR}")"

  if [[ "${target_uid}" == "0" || "${target_gid}" == "0" ]]; then
    echo "[opencode-entrypoint] skip uid/gid sync for root-owned ${WORKSPACE_DIR}" >&2
    return
  fi

  current_uid="$(id -u "${OPENCODE_USER}")"
  current_gid="$(id -g "${OPENCODE_USER}")"

  if [[ "${target_gid}" != "${current_gid}" ]]; then
    existing_group="$(getent group "${target_gid}" | cut -d: -f1 || true)"
    if [[ -n "${existing_group}" ]]; then
      usermod -g "${existing_group}" "${OPENCODE_USER}"
    else
      groupmod -g "${target_gid}" "${OPENCODE_USER}"
    fi
  fi

  if [[ "${target_uid}" != "${current_uid}" ]]; then
    existing_user="$(getent passwd "${target_uid}" | cut -d: -f1 || true)"
    if [[ -n "${existing_user}" && "${existing_user}" != "${OPENCODE_USER}" ]]; then
      if [[ "${existing_user}" == "node" ]]; then
        reassigned_uid="$(find_available_uid || true)"
        if [[ -z "${reassigned_uid}" ]]; then
          echo "[opencode-entrypoint] cannot find free uid for ${existing_user}; keep ${OPENCODE_USER} uid ${current_uid}" >&2
        else
          usermod -u "${reassigned_uid}" "${existing_user}"
          usermod -u "${target_uid}" "${OPENCODE_USER}"
          echo "[opencode-entrypoint] moved ${existing_user} uid ${target_uid} -> ${reassigned_uid}; set ${OPENCODE_USER} uid to ${target_uid}" >&2
        fi
      else
        echo "[opencode-entrypoint] uid ${target_uid} is used by ${existing_user}; keep ${OPENCODE_USER} uid ${current_uid}" >&2
      fi
    else
      usermod -u "${target_uid}" "${OPENCODE_USER}"
    fi
  fi

  chown -R "${OPENCODE_USER}:$(id -gn "${OPENCODE_USER}")" "${OPENCODE_HOME_DIR}" >/dev/null 2>&1 || true
}

if [[ "$(id -u)" -eq 0 ]]; then
  ensure_opencode_user

  if [[ "$#" -gt 0 ]]; then
    resolved_command="$(command -v "$1" 2>/dev/null || true)"
    if [[ -n "${resolved_command}" ]]; then
      set -- "${resolved_command}" "${@:2}"
    fi
  fi

  sync_workspace_identity
  exec sudo -EHu "${OPENCODE_USER}" env HOME="${OPENCODE_HOME_DIR}" PATH="${PATH}" "$@"
fi

exec "$@"
