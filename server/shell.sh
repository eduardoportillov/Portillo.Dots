# shellcheck shell=bash
# Remote Server environment; sourced by Bash or Zsh without changing login shell.
# The shared baseline (aliases, colors, prompt, editor, user tool prefix) comes
# from the shared tree so every host feels like the same machine; only server
# specifics live in this file.
if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/portillo-dots/shell-common.sh" ]; then
  . "${XDG_CONFIG_HOME:-$HOME/.config}/portillo-dots/shell-common.sh"
fi
# OpenCode references provider credentials as {env:NAME}; load them from the
# per-host file when it exists. Strictly opt-out by deleting secrets.env.
if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/load-secrets.sh" ]; then
  . "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/load-secrets.sh"
fi
