#!/usr/bin/env bash
set -euo pipefail

REMOTE_BASE="$HOME/.portillo-remote"
STATE_DIR="$HOME/.portillo-dots-remote-state"
TMUX_SOCKET="portillo-dots"

export PATH="$REMOTE_BASE/bin:$HOME/.local/bin:$PATH"
export NVIM_APPNAME="portillo-remote/nvim"

if [[ -r "$STATE_DIR/ls-colors.sh" ]]; then
  source "$STATE_DIR/ls-colors.sh"
fi
if [[ -r "$STATE_DIR/shell-version.sh" ]]; then
  source "$STATE_DIR/shell-version.sh"
fi

selected_path="${1:-}"
if [[ -n "$selected_path" ]] && [[ -d "$selected_path" ]]; then
  cd "$selected_path" || exit 1
elif [[ -n "$selected_path" ]]; then
  printf 'Warning: remote path does not exist: %s\n' "$selected_path" >&2
fi

if [[ "${PORTILLO_NO_TMUX:-0}" == "1" ]] || ! command -v tmux &>/dev/null; then
  exec bash --rcfile "$STATE_DIR/bashrc" -i
fi

tmux_bin="$(command -v tmux)"
ptmux() {
  "$tmux_bin" -L "$TMUX_SOCKET" "$@"
}

tmux_conf="$STATE_DIR/tmux-remote.conf"
shell_version="${PORTILLO_SHELL_ENV_VERSION:-}"
if [[ -z "$shell_version" ]]; then
  printf 'Error: the persistent shell environment is not loaded. Redeploy Portillo.Dots.\n' >&2
  exit 1
fi

session_created=0
bash_bin="$(command -v bash)"
printf -v managed_command 'exec %q --rcfile %q -i' "$bash_bin" "$STATE_DIR/bashrc"
tmux_conf_version="$(cksum "$tmux_conf" | awk '{ print $1 "-" $2 }')"
config_loaded=1

if ptmux list-sessions &>/dev/null; then
  active_conf_version="$(ptmux show-environment -g PORTILLO_TMUX_CONFIG_VERSION 2>/dev/null || true)"
  active_conf_version="${active_conf_version#PORTILLO_TMUX_CONFIG_VERSION=}"
  if [[ "$active_conf_version" != "$tmux_conf_version" ]]; then
    if ! ptmux source-file "$tmux_conf"; then
      printf 'Warning: could not fully reload %s; applying shell settings directly.\n' \
        "$tmux_conf" >&2
      config_loaded=0
    else
      ptmux set-environment -g PORTILLO_TMUX_CONFIG_VERSION "$tmux_conf_version"
    fi
  fi
  ptmux set-option -g default-shell "$bash_bin"
  ptmux set-option -g default-command "$managed_command"
  session_id="$(ptmux list-sessions -f '#{==:#{session_name},portillo}' -F '#{session_id}' \
    | command head -n 1)"
  if [[ -z "$session_id" ]]; then
    ptmux new-session -d -s portillo -c "$PWD" "$managed_command"
    session_id="$(ptmux display-message -p -t portillo: '#{session_id}')"
    session_created=1
  fi
elif [[ -f "$tmux_conf" ]]; then
  "$tmux_bin" -L "$TMUX_SOCKET" -f "$tmux_conf" \
    new-session -d -s portillo -c "$PWD" "$managed_command"
  session_id="$(ptmux display-message -p -t portillo: '#{session_id}')"
  session_created=1
else
  ptmux new-session -d -s portillo -c "$PWD" "$managed_command"
  session_id="$(ptmux display-message -p -t portillo: '#{session_id}')"
  session_created=1
fi

ptmux set-option -t "$session_id" default-shell "$bash_bin"
ptmux set-option -t "$session_id" default-command "$managed_command"
ptmux set-environment -g LS_COLORS "$LS_COLORS"
if [[ -n "${COLORTERM:-}" ]]; then
  ptmux set-environment -g COLORTERM "$COLORTERM"
fi
ptmux set-environment -g PORTILLO_DIRCOLORS_VERSION "$PORTILLO_DIRCOLORS_VERSION"
ptmux set-environment -g PORTILLO_SHELL_ENV_VERSION "$shell_version"
if [[ "$config_loaded" -eq 1 ]]; then
  ptmux set-environment -g PORTILLO_TMUX_CONFIG_VERSION "$tmux_conf_version"
fi

managed_window=""
if [[ "$session_created" -eq 1 ]]; then
  managed_window="$(ptmux display-message -p -t "$session_id": '#{window_id}')"
else
  while IFS='|' read -r window_id window_version window_path; do
    if [[ "$window_version" == "$shell_version" ]] \
      && { [[ -z "$selected_path" ]] || [[ "$window_path" == "$PWD" ]]; }; then
      managed_window="$window_id"
      break
    fi
  done < <(ptmux list-windows -t "$session_id" \
    -F '#{window_id}|#{@portillo_dircolors_version}|#{pane_current_path}')
fi

if [[ -z "$managed_window" ]]; then
  managed_window="$(ptmux new-window -d -P -F '#{window_id}' -t "$session_id": -c "$PWD")"
fi

ptmux set-option -w -t "$managed_window" @portillo_dircolors_version "$shell_version"
ptmux select-window -t "$managed_window"
exec "$tmux_bin" -L "$TMUX_SOCKET" attach-session -t "$session_id"
