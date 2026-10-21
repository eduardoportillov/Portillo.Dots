#!/usr/bin/env bash
# Function definitions only. The root entrypoint sets a trusted environment;
# isolated tests can source this file without sudo or system side effects.

system_metadata() {
  stat -c '%u %a' "$1" 2>/dev/null || stat -f '%u %Lp' "$1"
}

assert_system_directory() {
  local directory="$1" direct=true owner mode
  while :; do
    [[ -d "$directory" && ! -L "$directory" ]] || return 1
    read -r owner mode < <(system_metadata "$directory") || return 1
    [[ "$owner" == 0 || "$owner" == "$EUID" ]] || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    if (( (8#$mode & 0022) != 0 )); then
      # A sticky ancestor such as /tmp protects an owned private test directory.
      # The destination's immediate parent must never be publicly writable.
      [[ "$direct" == false && -k "$directory" ]] || return 1
    fi
    [[ "$directory" != / ]] || break
    directory="$(dirname "$directory")"
    direct=false
  done
}

prepare_system_parent() {
  local requested="$1" existing="$1" suffix='' part
  [[ "$requested" == /* ]] || return 1
  while [[ ! -e "$existing" && ! -L "$existing" ]]; do
    part="$(basename "$existing")"
    [[ "$part" != . && "$part" != .. ]] || return 1
    suffix="/$part$suffix"
    existing="$(dirname "$existing")"
  done
  existing="$(cd -P "$existing" && pwd -P)" || return 1
  assert_system_directory "$existing" || return 1
  while [[ -n "$suffix" ]]; do
    suffix="${suffix#/}"
    part="${suffix%%/*}"
    [[ "$part" != . && "$part" != .. && -n "$part" ]] || return 1
    mkdir -m 0755 "$existing/$part" || return 1
    existing="$existing/$part"
    if [[ "$suffix" == */* ]]; then suffix="/${suffix#*/}"; else suffix=''; fi
  done
  printf '%s\n' "$existing"
}

# EXIT traps in Bash 3.2 can outlive function-local variables. Keep only the
# staging path at subshell scope so INT/TERM cleanup works on macOS too.
ROOT_COPY_TEMP=''

root_copy() (
  # Subshell traps clean only the staging file, not the original or its backup.
  ROOT_COPY_TEMP=''
  local source="$1" destination="$2" mode="$3" parent saved status name owner existing_mode
  trap 'status=$?; if [[ -n "${ROOT_COPY_TEMP:-}" ]]; then rm -f -- "$ROOT_COPY_TEMP"; fi; exit "$status"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  [[ "$source" == /* && -f "$source" && ! -L "$source" ]] \
    || { printf 'Unsafe input: %s\n' "$source" >&2; return 1; }
  [[ "$mode" =~ ^0[0-7]{3}$ ]] || return 1
  name="$(basename "$destination")"
  [[ "$name" != . && "$name" != .. && "$name" != / ]] || return 1
  [[ "$destination" == /* && ! -d "$destination" ]] \
    || { printf 'Refusing a directory destination: %s\n' "$destination" >&2; return 1; }
  [[ ! -e "$destination" || -f "$destination" || -L "$destination" ]] \
    || { printf 'Refusing a non-file destination: %s\n' "$destination" >&2; return 1; }
  parent="$(prepare_system_parent "$(dirname "$destination")")" \
    || { printf 'Unsafe system directory: %s\n' "$(dirname "$destination")" >&2; return 1; }
  destination="$parent/$(basename "$destination")"
  if [[ -e "$destination" || -L "$destination" ]]; then
    if [[ ! -L "$destination" && -O "$destination" ]] && cmp -s "$source" "$destination"; then
      read -r owner existing_mode < <(system_metadata "$destination") || return 1
      if [[ "$owner" == "$EUID" && "$existing_mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$existing_mode & 0022) == 0 )); then
        chown "$EUID:$(id -g)" "$destination" || return 1
        chmod "$mode" "$destination" || return 1
        return 0
      fi
    fi
    saved="$(mktemp -d "$parent/.portillo-backup.XXXXXXXX")" || return 1
    cp -pP "$destination" "$saved/$(basename "$destination")" || return 1
    printf 'System backup: %s\n' "$saved"
  fi
  ROOT_COPY_TEMP="$(mktemp "$parent/.portillo.XXXXXXXX")" || return 1
  # EUID is 0 in production; using the actual caller also allows unprivileged
  # filesystem tests. The public entrypoint never permits a non-root execution.
  install -o "$EUID" -g "$(id -g)" -m "$mode" "$source" "$ROOT_COPY_TEMP" || return 1
  mv -f "$ROOT_COPY_TEMP" "$destination" || return 1
  ROOT_COPY_TEMP=''
)

retire_legacy_rule() (
  local legacy="$1" invoking_user="$2" candidate='' status
  trap 'status=$?; if [[ -n "$candidate" ]]; then rm -f -- "$candidate"; fi; exit "$status"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  [[ -e "$legacy" || -L "$legacy" ]] || return 0
  if [[ ! -f "$legacy" || -L "$legacy" || ! -O "$legacy" ]] \
    || [[ "$(cat "$legacy")" != "$invoking_user ALL=(ALL) NOPASSWD: ALL" ]]; then
    printf 'Legacy sudoers path is unrelated; preserved for manual review.\n' >&2
    return 0
  fi
  command -v visudo >/dev/null 2>&1 \
    || { printf 'visudo is required before retiring the matching legacy rule.\n' >&2; return 1; }
  local parent
  parent="$(prepare_system_parent "$(dirname "$legacy")")" || return 1
  legacy="$parent/$(basename "$legacy")"
  candidate="$(mktemp "$parent/.portillo-retired.XXXXXXXX")" || return 1
  printf '# Portillo.Dots: matching legacy blanket privilege rule retired.\n' > "$candidate" || return 1
  visudo -cf "$candidate" >/dev/null 2>&1 \
    || { printf 'Legacy rule retirement failed validation; original preserved.\n' >&2; return 1; }
  # Keep the filename as a valid comment-only fragment: explicit @include users
  # do not lose sudo due to a missing file. The original is backed up privately.
  root_copy "$candidate" "$legacy" 0440 || return 1
  printf 'Retired the matching legacy Portillo.Dots privilege rule.\n'
)

harden_existing_service() {
  local target="$1" unit="$2" source="$3" expected_unit="$4" owner mode
  [[ -f "$unit" && ! -L "$unit" && -O "$unit" && -f "$expected_unit" ]] \
    || { printf 'No owned managed service file; refusing changes.\n' >&2; return 1; }
  read -r owner mode < <(system_metadata "$unit") || return 1
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 )) || return 1
  cmp -s "$unit" "$expected_unit" \
    || { printf 'Service unit differs from the repository template; preserved for review.\n' >&2; return 1; }
  [[ -f "$source" && ! -L "$source" ]] || return 1
  /bin/bash -n "$source" || return 1
  if [[ -L "$target" ]]; then
    read -r owner mode < <(system_metadata "$target") || return 1
    [[ "$owner" == "$EUID" && "$(readlink "$target")" == "$source" ]] \
      || { printf 'Unrecognized service script link; preserved for review.\n' >&2; return 1; }
    root_copy "$source" "$target" 0755 || return 1
  elif [[ -f "$target" && -O "$target" ]] && cmp -s "$source" "$target"; then
    # Reapply safe ownership/mode without changing the file contents.
    root_copy "$source" "$target" 0755 || return 1
  else
    printf 'Service script is not the matching managed link/copy; refusing changes.\n' >&2
    return 1
  fi
  printf 'Existing service script hardened: uid=%s; regular file, no service restart or hardware changes.\n' "$EUID"
}

# Homebrew lives in a shared prefix whose root must exist before the
# unprivileged bootstrap clones into it. Prepared inside the single privileged
# phase so the bootstrap itself never needs sudo. privileged_main passes the
# fixed literal /home/linuxbrew; a static test pins that call site.
prepare_homebrew_prefix() {
  local root="$1" invoking_user="$2"
  [[ "$root" == /* && "$root" != / && -n "$invoking_user" ]] || return 2
  if [[ -e "$root" && ! -d "$root" ]]; then
    printf 'Homebrew prefix root exists and is not a directory; refusing changes.\n' >&2
    return 1
  fi
  if [[ ! -d "$root" ]]; then
    install -d -m 0755 -o "$invoking_user" -g "$(id -gn "$invoking_user")" "$root" || return 1
  fi
  return 0
}

# Apply a user-requested IANA timezone. The caller is root, but both the name
# grammar and the resolved zoneinfo path are validated again at this boundary.
set_system_timezone() {
  local zone="$1"
  [[ "$zone" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] || {
    printf 'Invalid IANA timezone name.\n' >&2
    return 2
  }
  [[ -f "/usr/share/zoneinfo/$zone" ]] || {
    printf 'Unknown IANA timezone: %s\n' "$zone" >&2
    return 1
  }
  command -v timedatectl >/dev/null 2>&1 || {
    printf 'timedatectl is required to set the system timezone.\n' >&2
    return 1
  }
  timedatectl set-timezone "$zone"
}

# Distribution plumbing the managed configuration needs beyond the manifest
# tools: archives for upstream installers and the TLS trust store. Tool
# packages themselves come from the components.sh catalog (tool_packages),
# which the privileged payload loads.
support_packages() {
  case "$1" in
    apt|dnf|pacman) printf '%s\n' unzip zip ca-certificates ;;
    *) return 2 ;;
  esac
}

install_packages() {
  local profile="$1" manager="$2" upgrade="$3" change_shell="${4:-false}" pm package kind name
  local packages=() optional=() warnings=()
  if command -v apt-get >/dev/null 2>&1; then
    pm=apt
  elif command -v dnf >/dev/null 2>&1; then
    pm=dnf
  elif command -v pacman >/dev/null 2>&1; then
    pm=pacman
  else
    printf 'Unsupported package manager\n' >&2; return 1
  fi
  declare -F profile_components tool_packages >/dev/null || {
    printf 'Incomplete privileged payload; use setup.sh.\n' >&2
    return 1
  }
  while read -r package; do
    append_unique packages "$package"
  done < <(support_packages "$pm")

  if [[ "$manager" == brew ]]; then
    # Homebrew provisions the tools as the invoking user; the native pass only
    # bootstraps what the remaining installer steps need.
    for name in git curl ssh rsync python3; do
      package="$(tool_packages "$name" "$pm")"
      if [[ -n "$package" ]]; then
        append_unique packages "$package"
      fi
    done
  else
    # The manifest drives installation: every required tool maps to its native
    # package through the catalog. Tools with no native package (or provided by
    # another channel, like opencode) contribute nothing here.
    while read -r kind name _; do
      [[ -n "$kind" && "$kind" == required ]] || continue
      package="$(tool_packages "$name" "$pm")"
      if [[ -n "$package" ]]; then
        append_unique packages "$package"
      fi
    done < <(profile_components "$profile" linux)
    if [[ "$profile" == workstation ]]; then
      while read -r kind name _; do
        [[ "$kind" == optional ]] || continue
        package="$(tool_packages "$name" "$pm")"
        if [[ -n "$package" ]]; then
          append_unique optional "$package"
        fi
      done < <(profile_components "$profile" linux)
    fi
    case "$pm" in
      pacman) append_unique optional tree-sitter ;;
      *)      append_unique optional tree-sitter-cli ;;
    esac
  fi
  # Both editor profiles compile Tree-sitter parsers.
  case "$pm" in
    apt) append_unique packages build-essential ;;
    dnf) append_unique packages gcc gcc-c++ make ;;
    pacman) append_unique packages base-devel ;;
  esac
  if [[ "$profile" == workstation ]]; then
    # Build support for workstation features (compilers for treesitter, desktop
    # clipboard helpers, fonts); not manifest tools themselves.
    case "$pm" in
      apt)    append_unique packages build-essential zsh ffmpeg alacritty xclip wl-clipboard copyq fontconfig ;;
      dnf)    append_unique packages gcc gcc-c++ make zsh ffmpeg-free alacritty xclip wl-clipboard copyq fontconfig ;;
      pacman) append_unique packages base-devel zsh ffmpeg alacritty xclip wl-clipboard copyq fontconfig ;;
    esac
  fi
  if [[ "$change_shell" == true ]]; then
    # The login shell changes inside this same privileged phase: zsh must be
    # resolvable before chsh runs, even when the toolchain channel (brew)
    # installs its own copy later in the user phase.
    append_unique packages "$(tool_packages zsh "$pm")"
  fi

  if [[ "$pm" == apt ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || return $?
    local apt_options=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    [[ "$upgrade" == true ]] || apt_options+=(--no-upgrade)
    apt-get install "${apt_options[@]}" "${packages[@]}" || return $?
    for package in ${optional[@]+"${optional[@]}"}; do
      apt-get install "${apt_options[@]}" "$package" || warnings+=("$package")
    done
  elif [[ "$pm" == dnf ]]; then
    dnf install -y "${packages[@]}" || return $?
    if [[ "$upgrade" == true ]]; then dnf upgrade -y "${packages[@]}" || return $?; fi
    for package in ${optional[@]+"${optional[@]}"}; do
      dnf install -y "$package" || warnings+=("$package")
    done
  elif [[ "$pm" == pacman ]]; then
    # Syncing Arch's metadata requires a full upgrade, never a partial one.
    pacman -Syu --needed --noconfirm "${packages[@]}" || return $?
    for package in ${optional[@]+"${optional[@]}"}; do
      pacman -S --needed --noconfirm "$package" || warnings+=("$package")
    done
  else
    printf 'Unsupported package manager\n' >&2; return 1
  fi
  if [[ ${#warnings[@]} -gt 0 ]]; then printf 'Optional packages unavailable: %s\n' "${warnings[*]}" >&2; fi
  return 0
}
