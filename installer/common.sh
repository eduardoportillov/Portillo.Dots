#!/usr/bin/env bash
# Globals are shared with the other sourced installer modules.
# shellcheck disable=SC2034
# Shared helpers; sourcing this file has no side effects.
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# Extract a canonical X.Y.Z from arbitrary version text ("tmux 3.6b" -> 3.6.0).
extract_version() {
  local text="$1"
  if [[ "$text" =~ ([0-9]+)\.([0-9]+)([.]([0-9]+))? ]]; then
    printf '%s.%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]:-0}"
    return 0
  fi
  return 1
}

# Pure-bash comparison so it works on BSD/macOS where `sort -V` is unavailable.
version_at_least() {
  local have="$1" want="$2" i have_part want_part
  local have_parts=() want_parts=()
  IFS='.' read -r -a have_parts <<< "$have"
  IFS='.' read -r -a want_parts <<< "$want"
  for (( i = 0; i < 3; i++ )); do
    have_part="${have_parts[i]:-0}"
    want_part="${want_parts[i]:-0}"
    [[ "$have_part" =~ ^[0-9]+$ ]] || have_part=0
    [[ "$want_part" =~ ^[0-9]+$ ]] || want_part=0
    if (( 10#$have_part > 10#$want_part )); then return 0; fi
    if (( 10#$have_part < 10#$want_part )); then return 1; fi
  done
  return 0
}

# Print the reported version of a tool, or fail when it cannot be determined.
# A directory result (macOS app bundle without CLI) has no parseable version.
tool_version() {
  local command="$1" executable flag output
  executable="$(tool_executable "$command")" || return 1
  [[ -f "$executable" ]] || return 1
  flag="$(tool_version_flag "$command")"
  output="$("$executable" "$flag" 2>/dev/null | head -n 1)" || return 1
  extract_version "$output"
}

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

# Root is only needed for Linux system packages, hardware tuning and a login
# shell change. macOS installs packages through user-level Homebrew, so a normal
# macOS install must not prompt for a password at all.
needs_privileged_phase() {
  [[ "$HARDWARE" == true || "$CHANGE_SHELL" == true ]] && return 0
  [[ "$PLATFORM" == linux && "$CONFIG_ONLY" == false ]]
}

preflight() {
  if [[ "$CONFIG_ONLY" == true ]]; then
    # No privileged phase is used; Python is needed only for OpenCode config.
    command -v python3 >/dev/null 2>&1 || die 'Install python3 before --config-only'
    return 0
  fi
  if needs_privileged_phase; then
    command -v sudo >/dev/null 2>&1 || die 'sudo is required for the single system phase'
  fi
  if [[ "$PLATFORM" == linux && "$PACKAGE_MANAGER" == brew ]]; then
    command -v brew >/dev/null 2>&1 || die 'Install Homebrew first, or use --package-manager native'
  fi
  if [[ "$PLATFORM" == linux ]]; then
    command -v apt-get >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 || command -v pacman >/dev/null 2>&1 \
      || die 'Supported native package managers: apt, dnf, pacman'
  fi
  if [[ "$PLATFORM" == mac ]]; then
    # Homebrew and most toolchains compile against the Apple Command Line Tools.
    command -v xcode-select >/dev/null 2>&1 && xcode-select -p >/dev/null 2>&1 \
      || die 'Apple Command Line Tools are required on macOS: xcode-select --install'
  fi
  if [[ "$OPENCODE_TEMPLATE" == true ]]; then
    [[ -f "$REPO_DIR/opencode/.env" ]] || die 'Create opencode/.env before using --opencode-template'
  fi
}
