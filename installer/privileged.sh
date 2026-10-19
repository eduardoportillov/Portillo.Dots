#!/usr/bin/env bash
# Entrypoint appended to privileged-core.sh and loaded via one sudo process.
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
IFS=$' \t\n'
unset BASH_ENV ENV CDPATH
umask 022

privileged_main() {
  [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]] || {
    printf 'Run this helper through setup.sh as a normal user.\n' >&2; return 1;
  }
  [[ $# -eq 8 ]] || return 2
  local profile="$1" manager="$2" hardware="$3" hardware_only="$4" change_shell="$5" upgrade="$6" repo="$7" operation="$8"
  case "$profile:$manager" in workstation:native|workstation:brew|server:native|server:brew) ;; *) return 2 ;; esac
  case "$operation" in install|check|harden) ;; *) return 2 ;; esac
  local flag
  for flag in "$hardware" "$hardware_only" "$change_shell" "$upgrade"; do
    case "$flag" in true|false) ;; *) return 2 ;; esac
  done
  [[ "$profile" != server || ( "$hardware" == false && "$hardware_only" == false && "$change_shell" == false ) ]] || return 2
  [[ "$hardware_only" == false || ( "$hardware" == true && "$upgrade" == false && "$change_shell" == false ) ]] || return 2
  [[ "$repo" == /* && -d "$repo" && "$(id -u "$SUDO_USER")" == "${SUDO_UID:-}" ]] || return 2
  declare -F root_copy retire_legacy_rule install_packages harden_existing_service >/dev/null || {
    printf 'Incomplete privileged payload; use setup.sh.\n' >&2; return 1;
  }
  local platform
  platform="$(uname -s)"
  case "$platform:$manager" in Linux:native|Linux:brew|Darwin:brew) ;; *) return 2 ;; esac
  [[ "$hardware" == false || "$platform" == Linux ]] || return 2
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ "$operation" == check ]]; then
    [[ "$hardware" == false && "$change_shell" == false && "$upgrade" == false ]] || return 2
    printf 'Privileged identity verified: uid=%s invoking_uid=%s. No system changes performed.\n' "$EUID" "$SUDO_UID"
    return 0
  fi
  if [[ "$operation" == harden ]]; then
    [[ "$platform:$profile" == Linux:workstation && "$hardware" == false && "$change_shell" == false && "$upgrade" == false ]] || return 2
    harden_existing_service /usr/local/bin/apply-linux-hardware-settings.sh \
      /etc/systemd/system/apply-linux-hardware-settings.service \
      "$repo/linux/optimize.sh" "$repo/linux/apply-linux-hardware-settings.service"
    return
  fi

  retire_legacy_rule /etc/sudoers.d/portillo-dots-setup "$SUDO_USER"
  if [[ "$hardware_only" == false ]]; then
    case "$platform" in
      Linux) install_packages "$profile" "$manager" "$upgrade" ;;
      Darwin)
        # Homebrew is pre-installed by its official installer and manages
        # packages as the invoking user. Nothing here needs root; macOS system
        # package writes are intentionally not performed.
        printf 'macOS: user-level Homebrew manages all packages; no root package action.\n'
        ;;
      *) return 2 ;;
    esac
  fi
  if [[ "$hardware" == true ]]; then
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
    local shell
    shell="$(command -v zsh)"
    grep -qxF "$shell" /etc/shells || printf '%s\n' "$shell" >> /etc/shells
    chsh -s "$shell" "$SUDO_USER"
  fi
  if [[ "$platform" == Linux && "$profile" == workstation && "$hardware_only" == false ]]; then
    root_copy "$repo/zsh/.dircolors" /root/.dircolors 0644
  fi
}

# No child command can consume the remaining script stream or prompt on stdin.
privileged_main "$@" </dev/null
