#!/usr/bin/env bash
# One bounded root process. No arbitrary command input and no downloaded scripts.
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
unset BASH_ENV ENV CDPATH

[[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]] || {
  printf 'Run this helper through setup.sh as a normal user.\n' >&2; exit 1;
}
[[ $# -eq 7 ]] || exit 2
profile="$1" manager="$2" hardware="$3" hardware_only="$4" change_shell="$5" upgrade="$6" repo="$7"
case "$profile:$manager" in workstation:native|workstation:brew|server:native|server:brew) ;; *) exit 2 ;; esac
for flag in "$hardware" "$hardware_only" "$change_shell" "$upgrade"; do
  case "$flag" in true|false) ;; *) exit 2 ;; esac
done
[[ "$profile" != server || ( "$hardware" == false && "$change_shell" == false ) ]] || exit 2
[[ "$repo" == /* && -d "$repo" && "$(id -u "$SUDO_USER")" == "${SUDO_UID:-}" ]] || exit 2
warnings=()

# Retire only the exact legacy rule created for this invoking user. Never delete
# an unrelated sudoers file and never create a replacement authentication rule.
legacy=/etc/sudoers.d/portillo-dots-setup
if [[ -f "$legacy" && ! -L "$legacy" ]] \
  && [[ "$(cat "$legacy")" == "$SUDO_USER ALL=(ALL) NOPASSWD: ALL" ]]; then
  rm -f "$legacy"
  printf 'Removed the matching legacy Portillo.Dots sudoers rule.\n'
elif [[ -e "$legacy" || -L "$legacy" ]]; then
  printf 'Existing legacy sudoers path is unrelated; review it manually.\n' >&2
fi

root_copy() {
  local source="$1" destination="$2" mode="$3" temporary
  [[ -f "$source" && ! -L "$source" ]] || { printf 'Unsafe input: %s\n' "$source" >&2; return 1; }
  [[ ! -e "$destination" || -f "$destination" || -L "$destination" ]] \
    || { printf 'Refusing to replace non-file system config: %s\n' "$destination" >&2; return 1; }
  mkdir -p "$(dirname "$destination")"
  if [[ -e "$destination" || -L "$destination" ]]; then
    if [[ ! -L "$destination" ]] && cmp -s "$source" "$destination"; then
      chown "root:$(id -gn root)" "$destination"
      chmod "$mode" "$destination"
      return 0
    fi
    local saved
    saved="$(mktemp -d "$(dirname "$destination")/.portillo-backup.XXXXXXXX")"
    cp -pP "$destination" "$saved/$(basename "$destination")"
    printf 'System backup: %s\n' "$saved"
  fi
  temporary="$(mktemp "$(dirname "$destination")/.portillo.XXXXXXXX")"
  install -o root -g "$(id -gn root)" -m "$mode" "$source" "$temporary"
  # Rename replaces a destination symlink itself, never writes through it.
  mv -f "$temporary" "$destination"
}

install_packages() {
  local required=(git curl unzip zip rsync tmux neovim ripgrep fzf python3 jq htop)
  local optional=() build=()
  if [[ "$manager" == brew ]]; then
    required=(git curl unzip zip rsync python3)
  fi
  if command -v apt-get >/dev/null 2>&1; then
    pm=apt
    required+=(ca-certificates openssh-client)
    [[ "$manager" != native ]] || required+=(fd-find bat)
    [[ "$profile" != workstation ]] || build+=(build-essential zsh ffmpeg alacritty xclip wl-clipboard copyq fontconfig)
    [[ "$profile:$manager" != workstation:native ]] || build+=(golang-go)
    optional=(lazygit lazydocker zoxide atuin tree-sitter-cli)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    local apt_options=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    [[ "$upgrade" == true ]] || apt_options+=(--no-upgrade)
    apt-get install "${apt_options[@]}" "${required[@]}" ${build[@]+"${build[@]}"}
  elif command -v dnf >/dev/null 2>&1; then
    pm=dnf
    required+=(ca-certificates openssh-clients)
    [[ "$manager" != native ]] || required+=(fd-find bat)
    [[ "$profile" != workstation ]] || build+=(gcc gcc-c++ make zsh ffmpeg-free alacritty xclip wl-clipboard copyq fontconfig)
    [[ "$profile:$manager" != workstation:native ]] || build+=(golang)
    optional=(lazygit lazydocker zoxide atuin tree-sitter-cli)
    dnf install -y "${required[@]}" ${build[@]+"${build[@]}"}
    [[ "$upgrade" == false ]] || dnf upgrade -y "${required[@]}" ${build[@]+"${build[@]}"}
  elif command -v pacman >/dev/null 2>&1; then
    pm=pacman
    required+=(ca-certificates openssh)
    [[ "$manager" != native ]] || required+=(fd bat)
    [[ "$profile" != workstation ]] || build+=(base-devel zsh ffmpeg alacritty xclip wl-clipboard copyq fontconfig)
    [[ "$profile:$manager" != workstation:native ]] || build+=(go)
    optional=(lazygit lazydocker zoxide atuin tree-sitter)
    # Arch must avoid partial upgrades when refreshing repository metadata.
    pacman -Syu --needed --noconfirm "${required[@]}" ${build[@]+"${build[@]}"}
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
}

if [[ "$hardware_only" == false ]]; then
  case "$(uname -s)" in
    Linux) install_packages ;;
    Darwin)
      # Homebrew bootstrap: directories only as root; git/network run as user.
      if [[ "$(uname -m)" == arm64 ]]; then prefix=/opt/homebrew; else prefix=/usr/local/Homebrew; fi
      if [[ ! -e "$prefix" && ! -L "$prefix" ]]; then
        mkdir -p "$prefix"
        chown "$SUDO_UID:$(id -g "$SUDO_USER")" "$prefix"
      fi
      ;;
    *) exit 2 ;;
  esac
fi

if [[ "$hardware" == true ]]; then
  [[ "$(uname -s)" == Linux ]] || exit 2
  root_copy "$repo/linux/optimize.sh" /usr/local/bin/apply-linux-hardware-settings.sh 0755
  root_copy "$repo/linux/apply-linux-hardware-settings.service" /etc/systemd/system/apply-linux-hardware-settings.service 0644
  root_copy "$repo/linux/99-battery-charge-threshold.rules" /etc/udev/rules.d/99-battery-charge-threshold.rules 0644
  /bin/bash /usr/local/bin/apply-linux-hardware-settings.sh --apply
  systemctl daemon-reload
  systemctl enable --now apply-linux-hardware-settings.service
  udevadm control --reload-rules
  udevadm trigger -s power_supply
fi

if [[ "$change_shell" == true ]]; then
  shell="$(command -v zsh)"
  grep -qxF "$shell" /etc/shells || printf '%s\n' "$shell" >> /etc/shells
  chsh -s "$shell" "$SUDO_USER"
fi
if [[ "$(uname -s)" == Linux && "$profile" == workstation && "$hardware_only" == false ]]; then
  root_copy "$repo/zsh/.dircolors" /root/.dircolors 0644
fi
if [[ ${#warnings[@]} -gt 0 ]]; then
  printf 'Optional packages unavailable: %s\n' "${warnings[*]}" >&2
fi
