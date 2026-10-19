#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
# Portillo Remote bashrc - auto-generated
# Do not edit manually

# Shared baseline (aliases, memtop, editor, colors, prompt): the same
# environment an installed host provides, from the deployed shared tree.
if [ -r "$HOME/.portillo-remote/shared/shell/common.sh" ]; then
  . "$HOME/.portillo-remote/shared/shell/common.sh"
fi

# The remote runtime binaries take precedence over anything the baseline adds.
export PATH="$HOME/.portillo-remote/bin:$PATH"
export EDITOR="nvim"
export NVIM_APPNAME="portillo-remote/nvim"
export VISUAL="nvim"

# Hosts without dircolors still get the colors: this fragment was resolved from
# the tracked zsh/.dircolors during deploy. Keeping it outside
# ~/.portillo-remote makes colors survive the normal cleanup.
if ! command -v dircolors >/dev/null 2>&1 && [ -r "$HOME/.portillo-dots-remote-state/ls-colors.sh" ]; then
  source "$HOME/.portillo-dots-remote-state/ls-colors.sh"
fi

alias tm='tmux -L portillo-dots new-session -A -s portillo'

export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

if [ -f "$HOME/.portillo-remote/fzf/shell/completion.bash" ]; then
  source "$HOME/.portillo-remote/fzf/shell/completion.bash"
fi
if [ -f "$HOME/.portillo-remote/fzf/shell/key-bindings.bash" ]; then
  source "$HOME/.portillo-remote/fzf/shell/key-bindings.bash"
fi
EOF
