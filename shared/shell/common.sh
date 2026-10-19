# shellcheck shell=bash
# Portillo.Dots shared shell environment: the baseline every host shares so an
# installed workstation, an installed server and a remote runtime feel like the
# same machine. Sourced by Bash and Zsh; the few shell-specific bits detect the
# shell. Contexts (zsh/.zshrc, server/shell.sh, remote/generate-rc.sh) add
# their own extras around this file and never duplicate its contents.

# User tool prefix plus the OpenCode runtime when present. The loop is
# idempotent: a PATH that already carries the entry is left alone.
for portillo_bin in "$HOME/.local/bin" "$HOME/.opencode/bin"; do
  case ":$PATH:" in *":$portillo_bin:"*) ;; *) PATH="$portillo_bin:$PATH" ;; esac
done
export PATH
unset portillo_bin

export EDITOR=nvim
export VISUAL=nvim

# Node toolchain under demand: npm tools (pi, pnpm) resolve the fnm-managed
# Node only when it was provisioned; hosts without a Node toolchain are
# untouched.
if [ -x "$HOME/.local/share/fnm/fnm" ]; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$("$HOME/.local/share/fnm/fnm" env --use-on-cd --shell zsh)"
  else
    eval "$("$HOME/.local/share/fnm/fnm" env --shell bash)"
  fi
fi

# Kanagawa Dragon rules for ls, from the tracked dircolors source of truth.
if command -v dircolors >/dev/null 2>&1 && [ -r "$HOME/.dircolors" ]; then
  eval "$(dircolors -b "$HOME/.dircolors")"
fi
if command ls --color=auto -d . >/dev/null 2>&1; then
  alias ls='ls --color=auto'
elif command -v gls >/dev/null 2>&1; then
  alias ls='gls --color=auto'
fi

# The shared prompt: Kanagawa Dragon palette, matching the tmux status colors
# (crystalBlue #8ba4b0 and fujiWhite #c5c9c5) on every host. Workstation keeps
# Powerlevel10k, which replaces this when it loads after the shared baseline.
if [ -n "${ZSH_VERSION:-}" ]; then
  # shellcheck disable=SC2034  # PROMPT is consumed by Zsh, not by this script.
  PROMPT='%F{#8ba4b0}%n@%m%f:%F{#c5c9c5}%~%f%# '
else
  PS1='\[\e[38;2;139;164;176m\]\u@\h\[\e[0m\]:\[\e[38;2;197;201;197m\]\w\[\e[0m\]\$ '
fi

alias ll='ls -lah'
alias la='ls -lah'
alias l='ls -lh'
alias mkdir='mkdir -p'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias vim='nvim'
alias vi='nvim'

# Top processes by resident memory. Usage: memtop [count], defaults to 10.
memtop() {
  local limit="${1:-10}"

  if ! [[ "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -lt 1 ]]; then
    printf 'usage: memtop [count]\n' >&2
    return 2
  fi

  ps -axo pid=,rss=,comm= | LC_ALL=C sort -k2,2nr | awk -v limit="$limit" '
    BEGIN {
      printf "%-8s %8s %s\n", "PID", "MB", "comm"
    }
    NR <= limit {
      printf "%-8s %8.1f %s\n", $1, $2 / 1024, $3
    }
  '
}
