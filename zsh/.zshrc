# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# OS detection
_PORTILLO_OS="$(uname -s)"
if [[ "$_PORTILLO_OS" == "Darwin" ]]; then
  _PORTILLO_OS="macos"
else
  _PORTILLO_OS="linux"
fi

# Homebrew shellenv
if [[ "$_PORTILLO_OS" == "macos" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ "$_PORTILLO_OS" == "linux" ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

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

source $ZSH/oh-my-zsh.sh

# Powerlevel10k
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# fnm (Fast Node Manager)
if [[ -d "$HOME/.local/share/fnm" ]]; then
  export PATH="$HOME/.local/share/fnm:$PATH"
fi

if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

# pnpm — default JS package manager; npm is shimmed to pnpm via ~/.local/bin/npm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH" ;;
esac
alias npm="pnpm"

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

# opencode
if [ -d "$HOME/.opencode/bin" ]; then
  export PATH="$HOME/.opencode/bin:$PATH"
fi

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

# Fix unreadable colors for world-writable dirs (ow/tw/st): default LS_COLORS
# paints them with a green background that clashes with dark terminal themes
# (e.g. Kanagawa Dragon). Keep the security warning but as bold bright-red
# text (Kanagawa Dragon's bright red, #e46876) with no background, so it
# stays legible while still standing out from normal directories.
export LS_COLORS="${LS_COLORS}:ow=01;38;2;228;104;118:tw=01;38;2;228;104;118:st=01;38;2;228;104;118"

# Useful aliases
alias ll='ls -lah'
alias la='ls -lah'
alias l='ls -lh'
alias mkdir='mkdir -p'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# Top processes by resident memory. Usage: memtop [count], defaults to 10.
function memtop() {
  local limit="${1:-10}"

  if ! [[ "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -lt 1 ]]; then
    print -u2 "usage: memtop [count]"
    return 2
  fi

  ps -eo pid,rss,comm --sort=-rss | awk -v limit="$limit" '
    NR == 1 {
      printf "%-8s %8s %s\n", "PID", "MB", "CMD"
      next
    }
    NR <= limit + 1 {
      printf "%-8s %8.1f %s\n", $1, $2 / 1024, $3
    }
  '
}

# ~/.local/bin — must come last so its shims (e.g. npm → pnpm) take priority
# over anything node version managers (nvm/fnm) prepend to PATH above.
export PATH="$HOME/.local/bin:$PATH"
