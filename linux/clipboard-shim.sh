#!/usr/bin/env bash
# Clipboard shim: installed as xclip, xsel, wl-copy and wl-paste in ~/.local/bin.
#
# Long-lived clients (Claude Code, Pi, OpenCode) keep the graphical environment
# they were born with. When tmux or the user session starts before Xwayland or
# the Wayland socket is ready, or Xwayland restarts (new .mutter-Xwaylandauth.*
# file), that environment goes stale and every copy fails with "Clipboard
# unavailable: install xclip or xsel, or check X11 access".
#
# Each copy/paste spawns a fresh process, so repairing the environment HERE
# fixes already-running clients without restarting them. Only public connection
# metadata is discovered (socket paths, the Xwayland -auth path); cookies and
# clipboard contents are never read or printed.
set -u

name="${0##*/}"
self="$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")"

# Locate the real binary: first PATH entry that is not this script.
real=''
IFS=: read -r -a path_entries <<< "${PATH:-}"
for dir in "${path_entries[@]}"; do
  candidate="$dir/$name"
  [[ -x "$candidate" && -f "$candidate" ]] || continue
  [[ "$(readlink -f -- "$candidate" 2>/dev/null)" == "$self" ]] && continue
  real="$candidate"
  break
done
if [[ -z "$real" ]]; then
  printf '%s: real binary not found in PATH\n' "$name" >&2
  exit 127
fi

repair_environment() {
  # Never touch SSH forwarding.
  [[ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] || return 0

  local uid runtime sock proc display auth
  uid="$(id -u)"
  runtime="${XDG_RUNTIME_DIR:-}"
  if [[ -z "$runtime" || ! -d "$runtime" || ! -O "$runtime" ]]; then
    runtime="/run/user/$uid"
  fi
  [[ -d "$runtime" && -O "$runtime" ]] || return 0
  export XDG_RUNTIME_DIR="$runtime"

  # Wayland: keep the current socket if it exists, otherwise pick a live one.
  local current="${WAYLAND_DISPLAY:-}"
  if [[ "$current" != /* ]]; then current="$runtime/$current"; fi
  if [[ -z "${WAYLAND_DISPLAY:-}" || ! -S "$current" ]]; then
    unset WAYLAND_DISPLAY
    for sock in "$runtime"/wayland-*; do
      [[ -S "$sock" && -O "$sock" ]] || continue
      export WAYLAND_DISPLAY="${sock##*/}"
      break
    done
  fi

  # X11: the running Xwayland of this user is the source of truth for both the
  # display number and the authority file, which changes whenever it restarts.
  display='' auth=''
  while IFS= read -r proc; do
    [[ "$proc" == *Xwayland* ]] || continue
    local -a argv
    read -r -a argv <<< "$proc"
    local i
    for ((i = 0; i < ${#argv[@]}; i++)); do
      case "${argv[i]}" in
        :[0-9]*) [[ -n "$display" ]] || display="${argv[i]}" ;;
        -auth) auth="${argv[i + 1]:-}" ;;
      esac
    done
    break
  done < <(pgrep -u "$uid" -a Xwayland 2>/dev/null | cut -d' ' -f2-)

  if [[ -n "$display" ]]; then
    if [[ -z "${DISPLAY:-}" || "$DISPLAY" == "$display" ]]; then
      export DISPLAY="$display"
      if [[ "$auth" == /* && -r "$auth" && -O "$auth" ]]; then
        export XAUTHORITY="$auth"
      fi
    fi
  fi
}

repair_environment
exec "$real" "$@"
