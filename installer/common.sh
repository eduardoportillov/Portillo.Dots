#!/usr/bin/env bash
# Globals are shared with the other sourced installer modules.
# shellcheck disable=SC2034
# Shared helpers; sourcing this file has no side effects.
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# Outcome tracking. The summary reports what happened — installed, unchanged,
# preserved, restricted, skipped or failed — so a run never has to be inferred
# from scrolling logs.
EVENTS=()

record_event() {
  local status="$1"
  shift
  EVENTS+=("$status|$*")
}

print_summary() {
  local entry status message
  local installed=0 unchanged=0 preserved=0 restricted=0 skipped=0 failed=0
  for entry in "${EVENTS[@]}"; do
    status="${entry%%|*}"
    message="${entry#*|}"
    case "$status" in
      installed)  installed=$((installed + 1)) ;;
      unchanged)  unchanged=$((unchanged + 1)) ;;
      preserved)  preserved=$((preserved + 1)) ;;
      restricted) restricted=$((restricted + 1)) ;;
      skipped)    skipped=$((skipped + 1)) ;;
      failed)     failed=$((failed + 1)) ;;
    esac
  done

  echo ""
  info "Outcome for $PROFILE ($PLATFORM/$ARCH, $PACKAGE_MANAGER):"
  info "  created $installed | unchanged $unchanged | preserved $preserved | restricted $restricted | skipped $skipped | failed $failed"
  # Anything that is not a routine "unchanged" is worth naming explicitly.
  for entry in "${EVENTS[@]}"; do
    status="${entry%%|*}"
    message="${entry#*|}"
    case "$status" in
      installed)  printf '    [+] %s\n' "$message" ;;
      preserved)  printf '    [!] %s\n' "$message" ;;
      restricted) printf '    [k] %s\n' "$message" ;;
      skipped)    printf '    [-] %s\n' "$message" ;;
      failed)     printf '    [x] %s\n' "$message" ;;
    esac
  done
  [[ "$failed" -eq 0 ]] || printf '    [x] %d failure(s) above; see the log for detail\n' "$failed"
}

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
#
# Some CLIs are slow to report a version (opencode alone costs ~70 ms). Probe
# once and cache the answer keyed by the executable's mtime+size, so an upgrade
# invalidates the entry automatically. The cache holds no credentials and is
# derived data only; read-only modes may populate it.
TOOL_VERSION_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/portillo-dots/tool-versions.tsv"

tool_version() {
  local command="$1" executable flag output version key cached temporary
  executable="$(tool_executable "$command")" || return 1
  [[ -f "$executable" ]] || return 1
  key="$command|$executable|$(stat -c '%Y:%s' "$executable" 2>/dev/null \
    || stat -f '%m:%z' "$executable" 2>/dev/null || echo '?')"
  if [[ -r "$TOOL_VERSION_CACHE" ]]; then
    cached="$(awk -F'\t' -v key="$key" '$1 == key { print $2; exit }' "$TOOL_VERSION_CACHE")"
    if [[ -n "$cached" ]]; then
      printf '%s\n' "$cached"
      return 0
    fi
  fi
  flag="$(tool_version_flag "$command")"
  output="$("$executable" "$flag" 2>/dev/null | head -n 1)" || return 1
  version="$(extract_version "$output")" || return 1
  mkdir -p "$(dirname "$TOOL_VERSION_CACHE")" 2>/dev/null || true
  temporary="${TOOL_VERSION_CACHE}.tmp.$$"
  if {
    [[ ! -r "$TOOL_VERSION_CACHE" ]] || awk -F'\t' -v key="$key" '$1 != key' "$TOOL_VERSION_CACHE"
    printf '%s\t%s\n' "$key" "$version"
  } > "$temporary" 2>/dev/null; then
    chmod 0600 "$temporary" 2>/dev/null || true
    mv -f "$temporary" "$TOOL_VERSION_CACHE" 2>/dev/null || rm -f "$temporary" 2>/dev/null
  else
    rm -f "$temporary" 2>/dev/null
  fi
  printf '%s\n' "$version"
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

# Restrict a credential-bearing file to the owner. Only the mode is changed, only
# ever tightened, and never through a symlink or on a file we do not own.
secure_file() {
  local path="$1" mode="${2:-0600}" current
  [[ -e "$path" && ! -L "$path" && -O "$path" ]] || return 0
  current="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null || echo '')"
  [[ "$current" =~ ^[0-7]{3,4}$ ]] || return 0
  # Already private to the owner: nothing to tighten.
  (( (8#$current & 0077) == 0 )) && return 0
  chmod "$mode" "$path" || { warn "Could not restrict $path (still mode $current)"; record_event failed "restrict $path"; return 1; }
  info "Restricted $path: $current -> $mode"
  record_event restricted "$path ($current -> $mode)"
}

secure_dir() {
  local path="$1" current
  [[ -d "$path" && ! -L "$path" && -O "$path" ]] || return 0
  current="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null || echo '')"
  [[ "$current" =~ ^[0-7]{3,4}$ ]] || return 0
  (( (8#$current & 0077) == 0 )) && return 0
  chmod 0700 "$path" || { warn "Could not restrict directory $path"; record_event failed "restrict dir $path"; return 1; }
  info "Restricted $path: $current -> 0700"
  record_event restricted "$path ($current -> 0700)"
}

# Known credential locations: repo sources, generated config and the log.
# Anything we cannot verify is reported, never silently ignored.
known_secret_paths() {
  printf '%s\n' \
    "$REPO_DIR/opencode/.env" \
    "$REPO_DIR/opencode/opencode.jsonc" \
    "$REPO_DIR/logs" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/portillo-dots" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/secrets.env"
}

secure_known_secrets() {
  local path failed=0
  while read -r path; do
    [[ -n "$path" ]] || continue
    if [[ -L "$path" ]]; then
      warn "Credential path is a symlink, refusing to touch it: $path"
      failed=1
      continue
    fi
    if [[ -d "$path" ]]; then
      secure_dir "$path" || failed=1
    else
      secure_file "$path" || failed=1
    fi
  done < <(known_secret_paths)
  return "$failed"
}

# Report credential paths that are still group/world accessible. This is a check,
# not a mutation: --check must never change the system.
verify_secret_permissions() {
  local path failed=0 current
  while read -r path; do
    [[ -n "$path" && -e "$path" && ! -L "$path" ]] || continue
    current="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null || echo '')"
    [[ "$current" =~ ^[0-7]{3,4}$ ]] || continue
    if (( (8#$current & 0077) != 0 )); then
      warn "Credential path is group/world accessible ($current): $path"
      failed=1
    fi
  done < <(known_secret_paths)
  return "$failed"
}

symlink_file() {
  local source="$1" destination="$2"
  [[ -e "$source" ]] || die "Missing config: $source"
  mkdir -p "$(dirname "$destination")"
  if [[ -L "$destination" && "$(readlink "$destination")" == "$source" ]]; then
    record_event unchanged "link $destination"
    return 0
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    record_event preserved "$destination (previous version moved to the backup)"
  fi
  backup "$destination"
  ln -s "$source" "$destination"
  record_event installed "link $destination"
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
