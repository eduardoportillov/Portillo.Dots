# shellcheck shell=bash
# Remote Server environment; sourced by Bash or Zsh without changing login shell.
if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/load-secrets.sh" ]; then
  . "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/load-secrets.sh"
fi
for portillo_bin in "$HOME/.local/bin" "$HOME/.opencode/bin"; do
  case ":$PATH:" in *":$portillo_bin:"*) ;; *) PATH="$portillo_bin:$PATH" ;; esac
done
export PATH
unset portillo_bin
# Node toolchain under demand: npm tools like pi resolve the fnm-managed Node
# only when it was provisioned; hosts without it are untouched.
if [ -x "$HOME/.local/share/fnm/fnm" ]; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$("$HOME/.local/share/fnm/fnm" env --use-on-cd --shell zsh)"
  else
    eval "$("$HOME/.local/share/fnm/fnm" env --shell bash)"
  fi
fi
export EDITOR=nvim
export VISUAL=nvim
if command -v dircolors >/dev/null 2>&1 && [ -r "$HOME/.dircolors" ]; then
  eval "$(dircolors -b "$HOME/.dircolors")"
fi
if command ls --color=auto -d . >/dev/null 2>&1; then
  alias ls='ls --color=auto'
fi
alias ll='ls -lah'
