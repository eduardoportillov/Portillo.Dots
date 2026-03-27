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
  you-should-use
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

# NVM (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# SDKMAN (Java, Kotlin, Gradle) - manages JAVA_HOME automatically
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# Go
if command -v go &> /dev/null; then
  export GOPATH="$HOME/go"
fi

# uv (Python package manager)
if [ -f "$HOME/.local/bin/uv" ]; then
  export PATH="$HOME/.local/bin:$PATH"
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

# General local bin
export PATH="$HOME/.local/bin:$PATH"

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

# Useful aliases
alias ll='ls -lah'
alias la='ls -lah'
alias l='ls -lh'
alias mkdir='mkdir -p'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
