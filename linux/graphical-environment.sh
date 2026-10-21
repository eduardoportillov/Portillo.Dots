#!/usr/bin/env bash
# Recover only public connection metadata, never X11 cookies or clipboard data.
# Output is shell-escaped for Bash/Zsh: eval "$(bash graphical-environment.sh)".
set -euo pipefail

# Never replace SSH forwarding or a deliberately selected alternative display.
[[ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] || exit 0
command -v systemctl >/dev/null 2>&1 || exit 0

display='' wayland='' authority='' runtime='' session_type=''
environment="$(systemctl --user show-environment 2>/dev/null)" || exit 0
while IFS='=' read -r key value; do
  case "$key" in
    DISPLAY) display="$value" ;;
    WAYLAND_DISPLAY) wayland="$value" ;;
    XAUTHORITY) authority="$value" ;;
    XDG_RUNTIME_DIR) runtime="$value" ;;
    XDG_SESSION_TYPE) session_type="$value" ;;
  esac
done <<< "$environment"

[[ "$session_type" == wayland || "$session_type" == x11 ]] || exit 0

export_value() {
  printf 'export %s=%q\n' "$1" "$2"
}

wayland_socket_ok() {
  local value="$1" dir="$2" socket
  [[ "$dir" == /* && -d "$dir" && -O "$dir" && -n "$value" ]] || return 1
  if [[ "$value" == /* ]]; then socket="$value"; else socket="$dir/$value"; fi
  [[ -S "$socket" && -O "$socket" ]]
}

wayland_works() {
  local value="$1" dir="$2"
  wayland_socket_ok "$value" "$dir" || return 1
  command -v wl-paste >/dev/null 2>&1 || return 1
  WAYLAND_DISPLAY="$value" XDG_RUNTIME_DIR="$dir" \
    wl-paste --list-types >/dev/null 2>&1
}

x11_works() {
  local value="$1" auth="$2"
  [[ -n "$value" && "$auth" == /* && -f "$auth" && -r "$auth" && -O "$auth" ]] || return 1
  command -v xdpyinfo >/dev/null 2>&1 || return 1
  DISPLAY="$value" XAUTHORITY="$auth" xdpyinfo >/dev/null 2>&1
}

# Keep an explicitly selected display when it really works. Stale environment
# variables are common after desktop relogin and tmux resurrection; repair them
# from the user session manager, then drop only backends proven unusable.
if [[ -n "${WAYLAND_DISPLAY:-}" ]] && wayland_works "$WAYLAND_DISPLAY" "${XDG_RUNTIME_DIR:-}"; then
  :
elif wayland_works "$wayland" "$runtime"; then
  export_value WAYLAND_DISPLAY "$wayland"
  export_value XDG_RUNTIME_DIR "$runtime"
  export_value XDG_SESSION_TYPE wayland
else
  [[ -z "${WAYLAND_DISPLAY:-}" ]] || printf 'unset WAYLAND_DISPLAY\n'
fi

if [[ -n "${DISPLAY:-}" ]] && x11_works "$DISPLAY" "${XAUTHORITY:-}"; then
  :
elif x11_works "$display" "$authority"; then
  export_value DISPLAY "$display"
  export_value XAUTHORITY "$authority"
else
  if [[ -n "${DISPLAY:-}" ]]; then printf 'unset DISPLAY\n'; fi
  if [[ -n "${XAUTHORITY:-}" ]]; then printf 'unset XAUTHORITY\n'; fi
fi

if [[ "$session_type" == wayland ]] && wayland_works "$wayland" "$runtime"; then
  export_value XDG_SESSION_TYPE wayland
elif [[ "$session_type" == x11 ]] && x11_works "$display" "$authority"; then
  export_value XDG_SESSION_TYPE x11
fi
