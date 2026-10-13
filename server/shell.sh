# Remote Server environment; sourced by Bash or Zsh without changing login shell.
for portillo_bin in "$HOME/.local/bin" "$HOME/.opencode/bin"; do
  case ":$PATH:" in *":$portillo_bin:"*) ;; *) PATH="$portillo_bin:$PATH" ;; esac
done
export PATH
unset portillo_bin
export EDITOR=nvim
export VISUAL=nvim
if command -v dircolors >/dev/null 2>&1 && [ -r "$HOME/.dircolors" ]; then
  eval "$(dircolors -b "$HOME/.dircolors")"
fi
if command ls --color=auto -d . >/dev/null 2>&1; then
  alias ls='ls --color=auto'
fi
alias ll='ls -lah'
