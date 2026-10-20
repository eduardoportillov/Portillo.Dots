#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIRECTORY="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" == /* ]] || SOURCE="$DIRECTORY/$SOURCE"
done
REPO_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
source "$REPO_DIR/installer/components.sh"
source "$REPO_DIR/installer/common.sh"
source "$REPO_DIR/installer/profiles.sh"
source "$REPO_DIR/installer/workstation.sh"
source "$REPO_DIR/installer/opencode.sh"

PROFILE=""
CONFIG_ONLY=false
CHECK_ONLY=false
CHECK_SUDO=false
HARDEN_EXISTING_SERVICE=false
DRY_RUN=false
UPGRADE=false
HARDWARE=false
HARDWARE_ONLY=false
CHANGE_SHELL=false
INTERACTIVE=false
PACKAGE_MANAGER=auto
OPENCODE_TEMPLATE=false

usage() {
  cat <<'EOF'
Usage: bash setup.sh --profile workstation|server [OPTIONS]

Profiles (not OpenCode versions):
  workstation  Dev Workstation: development tools, shell, editors and desktop
  server       Remote Server: CLI essentials, lightweight Neovim/tmux, OpenCode

Options:
  --config-only         Apply user configurations only (no packages or sudo)
  --check               Read-only verification of the selected profile
  --check-sudo          Authenticate once and verify root identity; no system changes
  --harden-existing-service  Replace the matching legacy Linux service script link only
  --dry-run             Show actions without writing files or using the network
  --upgrade             Update installed tools explicitly
  --package-manager     auto|native|brew (brew must already exist on Linux)
  --hardware            Opt in to Linux hardware settings (workstation only)
  --apply-linux, -L     Apply only those hardware settings (workstation only)
  --change-shell        Opt in to changing the login shell to Zsh
  --opencode-template   Use the custom template + opencode/.env (manual V2 plugin review)
  --interactive, -i     Confirm the installation summary before proceeding
  --yes, -y             Accept the summary (never bypasses sudo authentication)
  --help, -h            Show this help

No profile: offer a menu in a terminal; require --profile in automation.
One privileged phase; no new sudoers privileges. A matching legacy rule may be retired.
EOF
}

require_value() {
  [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "Missing value for $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        require_value "$@"; PROFILE="$2"; shift 2
        case "$PROFILE" in workstation|server) ;; *) die "Invalid profile: $PROFILE" ;; esac
        ;;
      --package-manager)
        require_value "$@"; PACKAGE_MANAGER="$2"; shift 2
        case "$PACKAGE_MANAGER" in auto|native|brew) ;; *) die "Invalid package manager: $PACKAGE_MANAGER" ;; esac
        ;;
      --config-only) CONFIG_ONLY=true; shift ;;
      --check) CHECK_ONLY=true; shift ;;
      --check-sudo) CHECK_SUDO=true; shift ;;
      --harden-existing-service) HARDEN_EXISTING_SERVICE=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --upgrade) UPGRADE=true; shift ;;
      --hardware) HARDWARE=true; shift ;;
      --apply-linux|-L) HARDWARE=true; HARDWARE_ONLY=true; shift ;;
      --change-shell) CHANGE_SHELL=true; shift ;;
      --opencode-template) OPENCODE_TEMPLATE=true; shift ;;
      --interactive|-i) INTERACTIVE=true; shift ;;
      --yes|-y) INTERACTIVE=false; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
}

main() {
  parse_args "$@"
  if [[ -z "$PROFILE" ]]; then
    [[ -t 0 ]] || die "Choose --profile workstation or --profile server"
    printf '1. Dev Workstation — complete development environment\n2. Remote Server — tools for SSH servers\n'
    read -r -p 'Profile [1/2]: ' choice
    case "$choice" in 1) PROFILE=workstation ;; 2) PROFILE=server ;; *) die 'Invalid profile' ;; esac
  fi
  case "$PROFILE" in workstation|server) ;; *) die "Invalid profile: $PROFILE" ;; esac
  case "$PACKAGE_MANAGER" in auto|native|brew) ;; *) die "Invalid package manager: $PACKAGE_MANAGER" ;; esac
  [[ "$PROFILE" != server || "$HARDWARE" == false ]] \
    || die 'Server never changes hardware settings'
  [[ "$CONFIG_ONLY" == false || ( "$UPGRADE" == false && "$HARDWARE" == false && "$CHANGE_SHELL" == false ) ]] \
    || die '--config-only cannot install, upgrade or change system settings'
  [[ "$CHECK_ONLY" == false || ( "$CONFIG_ONLY" == false && "$UPGRADE" == false && "$HARDWARE" == false && "$CHANGE_SHELL" == false ) ]] \
    || die '--check cannot be combined with modifying options'
  [[ "$HARDWARE_ONLY" == false || ( "$CONFIG_ONLY" == false && "$CHECK_ONLY" == false && "$UPGRADE" == false && "$CHANGE_SHELL" == false ) ]] \
    || die '--apply-linux cannot be combined with other operation modes'
  [[ "$CHECK_SUDO" == false || ( "$CONFIG_ONLY" == false && "$CHECK_ONLY" == false && "$UPGRADE" == false && "$HARDWARE" == false && "$CHANGE_SHELL" == false && "$OPENCODE_TEMPLATE" == false && "$HARDEN_EXISTING_SERVICE" == false ) ]] \
    || die '--check-sudo cannot be combined with modifying or other checking options'
  [[ "$HARDEN_EXISTING_SERVICE" == false || ( "$PROFILE" == workstation && "$CONFIG_ONLY" == false && "$CHECK_ONLY" == false && "$UPGRADE" == false && "$HARDWARE" == false && "$CHANGE_SHELL" == false && "$OPENCODE_TEMPLATE" == false ) ]] \
    || die '--harden-existing-service requires workstation and cannot be combined with other operations'
  detect_platform
  [[ "$HARDWARE" == false || "$PLATFORM" == linux ]] || die 'Hardware settings require Linux'
  [[ "$HARDEN_EXISTING_SERVICE" == false || "$PLATFORM" == linux ]] || die 'Existing service hardening requires Linux'
  if [[ "$CHECK_ONLY" == true ]]; then
    local outcome=0
    verify_profile || outcome=1
    print_summary
    return "$outcome"
  fi
  show_actions
  [[ "$DRY_RUN" == false ]] || return 0
  [[ "$EUID" -ne 0 ]] || die 'Run setup as your normal user, not root'
  if [[ "$INTERACTIVE" == true ]]; then
    read -r -p 'Proceed? [y/N]: ' answer
    [[ "$answer" =~ ^[Yy]$ ]] || return 0
  fi
  if [[ "$CHECK_SUDO" == true || "$HARDEN_EXISTING_SERVICE" == true ]]; then
    command -v sudo >/dev/null 2>&1 || die 'sudo is required for this identity check'
    LOG=/dev/null
    if [[ "$CHECK_SUDO" == true ]]; then privileged_phase check; else privileged_phase harden; fi
    return
  fi
  initialize_state
  trap cleanup_setup EXIT
  preflight
  if [[ "$CONFIG_ONLY" == false ]]; then
    if needs_privileged_phase; then
      privileged_phase
    else
      info 'No privileged phase required for this platform/options; sudo is not invoked'
    fi
    [[ "$HARDWARE_ONLY" == false ]] || return 0
    install_profile
  fi
  configure_profile
  local outcome=0
  if [[ "$CONFIG_ONLY" == false ]]; then
    verify_profile || outcome=1
  else
    verify_configs || outcome=1
  fi
  print_summary
  if [[ "$outcome" -eq 0 ]]; then
    info "Completed: $PROFILE. Log: $LOG"
  else
    warn "Completed WITH FAILURES: $PROFILE. Log: $LOG"
  fi
  return "$outcome"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
