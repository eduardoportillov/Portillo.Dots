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
[[ -z "${DISPLAY:-}" || -z "$display" || "$DISPLAY" == "$display" ]] || exit 0
[[ -z "${WAYLAND_DISPLAY:-}" || -z "$wayland" || "$WAYLAND_DISPLAY" == "$wayland" ]] || exit 0

export_value() {
  printf 'export %s=%q\n' "$1" "$2"
}

if [[ -n "$display" && "$authority" == /* && -f "$authority" && -r "$authority" && -O "$authority" ]]; then
  export_value DISPLAY "$display"
  export_value XAUTHORITY "$authority"
fi
if [[ "$session_type" == wayland && "$runtime" == /* && -d "$runtime" && -O "$runtime" && -n "$wayland" ]]; then
  if [[ "$wayland" == /* ]]; then socket="$wayland"; else socket="$runtime/$wayland"; fi
  if [[ -S "$socket" && -O "$socket" ]]; then
    export_value WAYLAND_DISPLAY "$wayland"
    export_value XDG_RUNTIME_DIR "$runtime"
    export_value XDG_SESSION_TYPE "$session_type"
  fi
fi
