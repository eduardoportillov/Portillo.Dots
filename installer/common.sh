#!/usr/bin/env bash
# Shared helpers; sourcing this file has no side effects.
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

detect_platform() {
  case "$(uname -s)" in
    Linux) PLATFORM=linux ;;
    Darwin) PLATFORM=mac ;;
    *) die 'Supported systems: Linux and macOS' ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) ARCH=x86_64 ;;
    aarch64|arm64) ARCH=aarch64 ;;
    *) die 'Supported architectures: x86_64 and ARM64' ;;
  esac
  CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
  if [[ "$PLATFORM" == mac ]]; then
    [[ "$PACKAGE_MANAGER" != native ]] || die 'macOS requires Homebrew'
    PACKAGE_MANAGER=brew
  elif [[ "$PACKAGE_MANAGER" == auto ]]; then
    # Native packages avoid a second package stack on headless servers.
    if [[ "$PROFILE" == workstation ]] && command -v brew >/dev/null 2>&1; then
      PACKAGE_MANAGER=brew
    else
      PACKAGE_MANAGER=native
    fi
  fi
}

initialize_state() {
  STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/portillo-dots"
  mkdir -p "$STATE_DIR"
  chmod 0700 "$STATE_DIR"
  BACKUP_DIR="$(mktemp -d "$STATE_DIR/backup.XXXXXXXX")"
  WORK_DIR="$(mktemp -d "$STATE_DIR/setup.XXXXXXXX")"
  LOG="$STATE_DIR/setup.log"
  touch "$LOG"
  chmod 0600 "$LOG"
}

cleanup_setup() {
  # Temporary downloads only; never remove backups or user state.
  if [[ -n "${WORK_DIR:-}" && "$WORK_DIR" == "$STATE_DIR"/setup.* && -d "$WORK_DIR" && ! -L "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}

backup() {
  local path="$1" destination
  [[ -e "$path" || -L "$path" ]] || return 0
  destination="$BACKUP_DIR/${path#/}"
  mkdir -p "$(dirname "$destination")"
  [[ ! -e "$destination" && ! -L "$destination" ]] || die "Backup collision: $destination"
  mv "$path" "$destination"
  info "Backup: $destination"
}

symlink_file() {
  local source="$1" destination="$2"
  [[ -e "$source" ]] || die "Missing config: $source"
  mkdir -p "$(dirname "$destination")"
  if [[ -L "$destination" && "$(readlink "$destination")" == "$source" ]]; then
    return 0
  fi
  backup "$destination"
  ln -s "$source" "$destination"
}

run_installer() {
  local name="$1" url="$2"
  shift 2
  local script="$WORK_DIR/$name.sh"
  curl --proto '=https' --tlsv1.2 -fsSL --connect-timeout 15 --max-time 300 "$url" -o "$script"
  # Explicitly unprivileged; failed downloads can never execute partial input.
  bash "$script" "$@" >>"$LOG" 2>&1 || die "$name installer failed; see $LOG"
}

sync_git_dependency() {
  local repository="$1" destination="$2"
  if [[ ! -d "$destination" ]]; then
    git clone --depth 1 "$repository" "$destination" >>"$LOG" 2>&1
  elif [[ "$UPGRADE" == true && -d "$destination/.git" ]]; then
    if [[ -z "$(git -C "$destination" status --porcelain)" ]]; then
      git -C "$destination" pull --ff-only >>"$LOG" 2>&1
    else
      warn "Preserving modified dependency: $destination"
    fi
  fi
}

preflight() {
  if [[ "$CONFIG_ONLY" == true ]]; then
    # No privileged phase is used; Python is needed only for OpenCode config.
    command -v python3 >/dev/null 2>&1 || die 'Install python3 before --config-only'
    return 0
  fi
  command -v sudo >/dev/null 2>&1 || die 'sudo is required for the single system phase'
  if [[ "$PLATFORM" == linux && "$PACKAGE_MANAGER" == brew ]]; then
    command -v brew >/dev/null 2>&1 || die 'Install Homebrew first, or use --package-manager native'
  fi
  if [[ "$PLATFORM" == linux ]]; then
    command -v apt-get >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 || command -v pacman >/dev/null 2>&1 \
      || die 'Supported native package managers: apt, dnf, pacman'
  fi
  if [[ "$OPENCODE_TEMPLATE" == true ]]; then
    [[ -f "$REPO_DIR/opencode/.env" ]] || die 'Create opencode/.env before using --opencode-template'
  fi
}
