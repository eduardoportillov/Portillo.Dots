#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
# Portillo Remote bashrc - auto-generated
# Do not edit manually

export PATH="$HOME/.portillo-remote/bin:$HOME/.local/bin:$PATH"
export EDITOR="nvim"
export NVIM_APPNAME="portillo-remote/nvim"
export VISUAL="nvim"

# Generated from Portillo.Dots/zsh/.dircolors during deploy. Keeping the
# resolved shell fragment outside ~/.portillo-remote makes colors survive the
# normal cleanup and avoids requiring dircolors on the remote host.
if [[ -r "$HOME/.portillo-dots-remote-state/ls-colors.sh" ]]; then
  source "$HOME/.portillo-dots-remote-state/ls-colors.sh"
elif [[ -r "$HOME/.dircolors" ]]; then
  if command -v dircolors &>/dev/null; then
    eval "$(dircolors -b "$HOME/.dircolors")"
  elif command -v gdircolors &>/dev/null; then
    eval "$(gdircolors -b "$HOME/.dircolors")"
  fi
fi

if command ls --color=auto -d . &>/dev/null; then
  alias ls='ls --color=auto'
elif command -v gls &>/dev/null; then
  alias ls='gls --color=auto'
fi

PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

alias ll='ls -lah'
alias la='ls -lah'
alias l='ls -lh'
alias mkdir='mkdir -p'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias vim='nvim'
alias vi='nvim'
alias tm='tmux new-session -A -s portillo'

# Top processes by resident memory. Usage: memtop [count], defaults to 10.
memtop() {
  local limit="${1:-10}"

  if ! [[ "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -lt 1 ]]; then
    printf 'usage: memtop [count]\n' >&2
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

export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

if [[ -f "$HOME/.portillo-remote/fzf/shell/completion.bash" ]]; then
  source "$HOME/.portillo-remote/fzf/shell/completion.bash"
fi
if [[ -f "$HOME/.portillo-remote/fzf/shell/key-bindings.bash" ]]; then
  source "$HOME/.portillo-remote/fzf/shell/key-bindings.bash"
fi
EOF
