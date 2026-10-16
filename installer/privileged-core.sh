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

root_copy() (
  # Subshell traps clean only the staging file, not the original or its backup.
  local source="$1" destination="$2" mode="$3" temporary='' parent saved status name owner existing_mode
  trap 'status=$?; if [[ -n "$temporary" ]]; then rm -f -- "$temporary"; fi; exit "$status"' EXIT
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
  temporary="$(mktemp "$parent/.portillo.XXXXXXXX")" || return 1
  # EUID is 0 in production; using the actual caller also allows unprivileged
  # filesystem tests. The public entrypoint never permits a non-root execution.
  install -o "$EUID" -g "$(id -g)" -m "$mode" "$source" "$temporary" || return 1
  mv -f "$temporary" "$destination" || return 1
  temporary=''
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

install_packages() {
  local profile="$1" manager="$2" upgrade="$3" pm package
  local required=(git curl unzip zip rsync tmux neovim ripgrep fzf python3 jq htop)
  local optional=() build=() warnings=()
  if [[ "$manager" == brew ]]; then required=(git curl unzip zip rsync python3); fi
  if command -v apt-get >/dev/null 2>&1; then
    pm=apt
    required+=(ca-certificates openssh-client)
    [[ "$manager" != native ]] || required+=(fd-find bat)
    [[ "$profile" != workstation ]] || build+=(build-essential zsh ffmpeg alacritty xclip wl-clipboard copyq fontconfig)
    [[ "$profile:$manager" != workstation:native ]] || build+=(golang-go)
    optional=(lazygit lazydocker zoxide atuin tree-sitter-cli)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || return $?
    local apt_options=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    [[ "$upgrade" == true ]] || apt_options+=(--no-upgrade)
    apt-get install "${apt_options[@]}" "${required[@]}" ${build[@]+"${build[@]}"} || return $?
  elif command -v dnf >/dev/null 2>&1; then
    pm=dnf
    required+=(ca-certificates openssh-clients)
    [[ "$manager" != native ]] || required+=(fd-find bat)
    [[ "$profile" != workstation ]] || build+=(gcc gcc-c++ make zsh ffmpeg-free alacritty xclip wl-clipboard copyq fontconfig)
    [[ "$profile:$manager" != workstation:native ]] || build+=(golang)
    optional=(lazygit lazydocker zoxide atuin tree-sitter-cli)
    dnf install -y "${required[@]}" ${build[@]+"${build[@]}"} || return $?
    if [[ "$upgrade" == true ]]; then dnf upgrade -y "${required[@]}" ${build[@]+"${build[@]}"} || return $?; fi
  elif command -v pacman >/dev/null 2>&1; then
    pm=pacman
    required+=(ca-certificates openssh)
    [[ "$manager" != native ]] || required+=(fd bat)
    [[ "$profile" != workstation ]] || build+=(base-devel zsh ffmpeg alacritty xclip wl-clipboard copyq fontconfig)
    [[ "$profile:$manager" != workstation:native ]] || build+=(go)
    optional=(lazygit lazydocker zoxide atuin tree-sitter)
    # Syncing Arch's metadata requires a full upgrade, never a partial one.
    pacman -Syu --needed --noconfirm "${required[@]}" ${build[@]+"${build[@]}"} || return $?
  else
    printf 'Unsupported package manager\n' >&2; return 1
  fi
  if [[ "$profile" == workstation && "$manager" == native ]]; then
    for package in "${optional[@]}"; do
      case "$pm" in
        apt) apt-get install "${apt_options[@]}" "$package" || warnings+=("$package") ;;
        dnf) dnf install -y "$package" || warnings+=("$package") ;;
        pacman) pacman -S --needed --noconfirm "$package" || warnings+=("$package") ;;
      esac
    done
  fi
  if [[ ${#warnings[@]} -gt 0 ]]; then printf 'Optional packages unavailable: %s\n' "${warnings[*]}" >&2; fi
  return 0
}
