#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ZSHRC="$REPO_DIR/zsh/.zshrc"

if [[ ! -f "$ZSHRC" ]]; then
  echo "ERROR: $ZSHRC not found" >&2
  exit 1
fi

generate_rc() {
  cat <<'HEADER'
# Portillo Remote bashrc - auto-generated
# Do not edit manually

export PATH="$HOME/.portillo-remote/bin:$HOME/.local/bin:$PATH"
export EDITOR="nvim"
export NVIM_APPNAME="portillo-remote/nvim"
export VISUAL="nvim"

PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

HEADER

  local in_function=0 func_buffer=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*function[[:space:]] ]]; then
      in_function=1
      func_buffer="$line"$'\n'
      continue
    fi

    if [[ $in_function -eq 1 ]]; then
      func_buffer+="$line"$'\n'
      if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*$ ]]; then
        echo "$func_buffer"
        in_function=0
        func_buffer=""
      fi
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*alias[[:space:]] ]]; then
      echo "$line"
    fi
  done < "$ZSHRC"

  cat <<'FOOTER'

# Remote helpers
alias vim='nvim'
alias vi='nvim'
alias tm='tmux new-session -A -s portillo'

export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

if [[ -f "$HOME/.portillo-remote/fzf/shell/completion.bash" ]]; then
  source "$HOME/.portillo-remote/fzf/shell/completion.bash"
fi
if [[ -f "$HOME/.portillo-remote/fzf/shell/key-bindings.bash" ]]; then
  source "$HOME/.portillo-remote/fzf/shell/key-bindings.bash"
fi
FOOTER
}

generate_rc
