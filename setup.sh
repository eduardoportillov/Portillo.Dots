#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIRECTORY="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" == /* ]] || SOURCE="$DIRECTORY/$SOURCE"
done
REPO_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
source "$REPO_DIR/installer/common.sh"
source "$REPO_DIR/installer/profiles.sh"
source "$REPO_DIR/installer/workstation.sh"
source "$REPO_DIR/installer/opencode.sh"

PROFILE=""
CONFIG_ONLY=false
CHECK_ONLY=false
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
One privileged phase, at most one sudo authentication; never edits sudoers.
EOF
}

require_value() {
  [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "Missing value for $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile) require_value "$@"; PROFILE="$2"; shift 2 ;;
      --package-manager) require_value "$@"; PACKAGE_MANAGER="$2"; shift 2 ;;
      --config-only) CONFIG_ONLY=true; shift ;;
      --check) CHECK_ONLY=true; shift ;;
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
  [[ "$PROFILE" != server || ( "$HARDWARE" == false && "$CHANGE_SHELL" == false ) ]] \
    || die 'Server never changes hardware settings or the login shell'
  [[ "$CONFIG_ONLY" == false || ( "$UPGRADE" == false && "$HARDWARE" == false && "$CHANGE_SHELL" == false ) ]] \
    || die '--config-only cannot install, upgrade or change system settings'
  [[ "$CHECK_ONLY" == false || ( "$CONFIG_ONLY" == false && "$UPGRADE" == false && "$HARDWARE" == false && "$CHANGE_SHELL" == false ) ]] \
    || die '--check cannot be combined with modifying options'
  [[ "$HARDWARE_ONLY" == false || ( "$CONFIG_ONLY" == false && "$CHECK_ONLY" == false && "$UPGRADE" == false && "$CHANGE_SHELL" == false ) ]] \
    || die '--apply-linux cannot be combined with other operation modes'
  detect_platform
  [[ "$HARDWARE" == false || "$PLATFORM" == linux ]] || die 'Hardware settings require Linux'
  if [[ "$CHECK_ONLY" == true ]]; then
    verify_profile
    return
  fi
  show_actions
  [[ "$DRY_RUN" == false ]] || return 0
  [[ "$EUID" -ne 0 ]] || die 'Run setup as your normal user, not root'
  if [[ "$INTERACTIVE" == true ]]; then
    read -r -p 'Proceed? [y/N]: ' answer
    [[ "$answer" =~ ^[Yy]$ ]] || return 0
  fi
  initialize_state
  trap cleanup_setup EXIT
  preflight
  if [[ "$CONFIG_ONLY" == false ]]; then
    privileged_phase
    [[ "$HARDWARE_ONLY" == false ]] || return 0
    install_profile
  fi
  configure_profile
  if [[ "$CONFIG_ONLY" == false ]]; then
    verify_profile
  else
    verify_configs
  fi
  info "Completed: $PROFILE. Log: $LOG"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
