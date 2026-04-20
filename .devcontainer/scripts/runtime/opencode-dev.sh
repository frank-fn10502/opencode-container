#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=profiles.sh
source "${SCRIPT_DIR}/profiles.sh"
# shellcheck source=container.sh
source "${SCRIPT_DIR}/container.sh"

usage() {
  cat <<'USAGE'
Usage: opencode-dev [path]
       opencode-dev profile set <name> [path]
       opencode-dev profile status [path]
       opencode-dev --uninstall
       opencode-dev --admin-help

Common usage:
  opencode-dev               Open the current directory with OpenCode.
  opencode-dev /some/project Open that project directory with OpenCode.
  opencode-dev profile set python
                             Select the python profile for this project and open it.

Commands:
  profile set <name> [path]
            Select a profile for the current or specified project, then open OpenCode.
  profile status [path]
            Show the selected profile and available user/project profiles.
  --uninstall
            Remove the opencode-dev shell profile block and installed runtime.
  --admin-help
            Show debug/admin commands and container details.
USAGE
}

admin_usage() {
  cat <<'USAGE'
Debug/Admin commands:
  opencode-dev shell
      Open a bash shell for the current directory at /workspace.

  opencode-dev status
      Show the existing opencode-dev-yuta container, if any.

  opencode-dev stop
      Stop and remove the existing opencode-dev-yuta container.

  opencode-dev profile set <name> [path]
      Save <name> as the selected profile for the current or specified project,
      then open OpenCode with that profile.

Only one container named opencode-dev-yuta is allowed at a time. If one already
exists, this script asks whether to close it. Refusing leaves it untouched and
exits.

Implementation details:
  The base Docker image is fixed by compose.env as OPENCODE_DEV_IMAGE.
  User profiles live at ~/.opencode-dev-yuta/Dockerfile.<profile>.
  Project profiles live at <project>/.opencode-dev-yuta/Dockerfile.<profile>.
  Selected profiles are stored in config.env beside the relevant profile files.
  Container settings are defined in docker-compose.yml.
  The selected project directory is mounted into the container at /workspace.
  OpenCode runs inside a short-lived Docker container named opencode-dev-yuta.
  OpenCode state is stored in Docker named volumes, not in the project directory.
USAGE
}

run_profile_command() {
  local profile_command profile_name project_arg project_dir

  profile_command="${1:-}"
  case "${profile_command}" in
    set)
      shift || true
      if [[ $# -lt 1 ]]; then
        printf 'Usage: opencode-dev profile set <name> [path]\n' >&2
        exit 2
      fi

      profile_name="$1"
      shift || true
      project_arg=""
      if [[ $# -gt 0 && "${1}" != "--" ]]; then
        project_arg="$1"
        shift || true
      fi
      if [[ $# -gt 0 && "${1}" == "--" ]]; then
        shift || true
      fi

      project_dir="$(resolve_project_dir "${project_arg}")"
      write_selected_profile "${project_dir}" "${profile_name}"
      remove_existing_container_if_allowed
      run_opencode "${project_dir}" "$@"
      ;;
    status)
      shift || true
      show_profile_status "$(resolve_project_dir "${1:-}")"
      ;;
    ""|-h|--help)
      printf 'Usage: opencode-dev profile set <name> [path]\n'
      printf '       opencode-dev profile status [path]\n'
      ;;
    *)
      printf 'Unknown profile command: %s\n' "${profile_command}" >&2
      printf 'Usage: opencode-dev profile set <name> [path]\n' >&2
      printf '       opencode-dev profile status [path]\n' >&2
      exit 2
      ;;
  esac
}

command_name="${1:-}"
case "${command_name}" in
  help|-h|--help)
    usage
    exit 0
    ;;
  --admin-help)
    admin_usage
    exit 0
    ;;
esac

case "${command_name}" in
  --uninstall)
    uninstall_opencode_dev
    ;;

  shell)
    shift || true
    remove_existing_container_if_allowed
    run_shell "$(resolve_project_dir "")"
    ;;

  profile)
    shift || true
    run_profile_command "$@"
    ;;

  stop)
    stop_existing
    ;;

  status)
    show_status
    ;;

  "")
    remove_existing_container_if_allowed
    run_opencode "$(resolve_project_dir "")"
    ;;

  --)
    shift || true
    remove_existing_container_if_allowed
    run_opencode "$(resolve_project_dir "")" "$@"
    ;;

  *)
    project_arg="${command_name}"
    shift || true
    if [[ $# -gt 0 && "${1}" == "--" ]]; then
      shift
    fi
    remove_existing_container_if_allowed
    run_opencode "$(resolve_project_dir "${project_arg}")" "$@"
    ;;
esac
