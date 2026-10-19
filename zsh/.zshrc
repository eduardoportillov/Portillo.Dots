# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# A restored tmux pane may predate GNOME's graphical login. Recover the current
# connection metadata before clipboard clients start; leave SSH forwarding alone.
if [[ -n "${TMUX:-}" && -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]; then
  _portillo_graphical_helper="${${(%):-%N}:A:h:h}/linux/graphical-environment.sh"
  if [[ -f "$_portillo_graphical_helper" ]]; then
    eval "$(bash "$_portillo_graphical_helper")"
  fi
  unset _portillo_graphical_helper
fi

# OpenCode references provider credentials as {env:NAME}; load them from the
# per-host file when it exists. Strictly opt-out by deleting secrets.env.
if [[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/load-secrets.sh" ]]; then
  source "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/load-secrets.sh"
fi

# Shared baseline (aliases, memtop, editor, user tool prefix, prompt defaults
# and the Kanagawa Dragon dircolors). Sourced before Oh My Zsh so the LS_COLORS
# rules are in place when it reads them; Powerlevel10k replaces the shared
# prompt further below.
if [[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/portillo-dots/shell-common.sh" ]]; then
  source "${XDG_CONFIG_HOME:-$HOME/.config}/portillo-dots/shell-common.sh"
fi

# OS detection
_PORTILLO_OS="$(uname -s)"
if [[ "$_PORTILLO_OS" == "Darwin" ]]; then
  _PORTILLO_OS="macos"
else
  _PORTILLO_OS="linux"
fi

# Homebrew shellenv comes from the shared baseline (shell-common.sh), so brew
# tools and the user prefix keep one single definition across every host.

# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins (macos only if on macOS)
plugins=(
  git
  z
  brew
  sudo
  extract
  web-search
  zsh-autosuggestions
  zsh-syntax-highlighting
  # you-should-use — disabled: reminds you to use aliases instead of full
  # commands (e.g. "use gl instead of git pull"), which defeats the purpose
  # of actually learning the real commands.
  # you-should-use
  copyfile
  copypath
  fzf
)

if [[ "$_PORTILLO_OS" == "macos" ]]; then
  plugins+=(macos)
fi

[[ ! -r "$ZSH/oh-my-zsh.sh" ]] || source "$ZSH/oh-my-zsh.sh"

# Powerlevel10k
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# fnm (Fast Node Manager): handled by the shared baseline (shell-common.sh),
# which provisions the fnm-managed Node only when it exists.

# pnpm — use explicitly; leave npm semantics unchanged for external tools.
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH" ;;
esac

# rustup (Rust toolchain manager)
[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"

# SDKMAN (Java, Kotlin, Gradle) - manages JAVA_HOME automatically
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# Go
if command -v go &> /dev/null; then
  export GOPATH="$HOME/go"
fi

# uv (Python package manager)
if [ -f "$HOME/.local/bin/uv" ]; then
  : # binary lives in ~/.local/bin — added to PATH at the end of this file
fi

# bun
if [ -d "$HOME/.bun" ]; then
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
fi

# opencode runtime lives in ~/.opencode/bin — added to PATH by the shared
# baseline (shell-common.sh).

# tmux wrapper function for cross-platform session management
function tm() {
  [[ -n "$TMUX" ]] && change="switch-client" || change="new-session"
  if [[ -n "${1:-}" ]]; then
    tmux $change -t "$1" 2>/dev/null || tmux new-session -d -s "$1" && tmux $change -t "$1"
  else
    local session
    session="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | head -n1)"
    if [[ -n "$session" ]]; then
      tmux $change -t "$session"
    else
      tmux new-session
    fi
  fi
}

# Shell options
setopt ignoreeof

# Per-host overrides; always loaded last so they win over the managed config.
[[ ! -r "${XDG_CONFIG_HOME:-$HOME/.config}/portillo-dots/local.zsh" ]] || source "${XDG_CONFIG_HOME:-$HOME/.config}/portillo-dots/local.zsh"
