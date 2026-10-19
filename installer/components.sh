#!/usr/bin/env bash
# Single source of truth for the tools each profile installs and verifies.
#
# Line format: "<kind> <command> <min_version> <description>"
#   kind        : required | optional
#   command     : executable name used by install, display and verification
#   min_version : lowest version the managed configuration actually needs, or "-"
#                 when no known minimum applies. Never invent one: a gate must
#                 correspond to a syntax or API the dotfiles rely on.
#   description : human explanation, may contain spaces
#
# Every consumer reads this file: show_actions lists it, install targets it,
# verify_profile checks it. Adding a tool here keeps all three in agreement.

profile_components() {
  local profile="$1" platform="$2"
  case "$profile" in workstation|server) ;; *) printf 'Invalid profile: %s\n' "$profile" >&2; return 2 ;; esac
  case "$platform" in linux|mac) ;; *) printf 'Invalid platform: %s\n' "$platform" >&2; return 2 ;; esac

  # Neovim minimum is per profile: only LazyVim (workstation) needs 0.11. The
  # managed server config needs 0.10 for vim.ui.clipboard.osc52 and degrades
  # gracefully on older builds (the require is guarded with pcall).
  local nvim_minimum=0.10 nvim_reason='OSC52 clipboard needs 0.10'
  if [[ "$profile" == workstation ]]; then
    nvim_minimum=0.11
    nvim_reason='LazyVim needs 0.11'
  fi

  cat <<'EOF'
required git - Version control
required curl - Downloads and API calls
required ssh - Remote access client
required rsync - Remote file sync
required tmux 3.3 Terminal multiplexer (allow-passthrough needs 3.3)
EOF
  printf 'required nvim %s Neovim editor (%s)\n' "$nvim_minimum" "$nvim_reason"
  cat <<'EOF'
required rg - ripgrep text search
required fd - fd file search
required fzf - Fuzzy finder
required bat - bat file viewer
required jq - JSON processor
required htop - Process monitor
required python3 - Python runtime
required opencode 2.0 OpenCode V2 agent client
EOF

  if [[ "$profile" == workstation ]]; then
    cat <<'EOF'
required zsh - Zsh shell
required node 20 Node.js runtime (MCP servers use npx)
required pnpm - pnpm package manager
required go - Go toolchain
required rustup - Rust toolchain
required uv - Python package manager
required claude - Claude Code client
required zed - Zed editor
required alacritty 0.13 Alacritty terminal (osc52 needs 0.13)
optional lazygit - Git TUI
optional lazydocker - Docker TUI
optional zoxide - Smart cd
optional atuin - Shell history
EOF
  fi
}

# Alternate executable names some distributions ship. Used to create non-destructive
# shims in ~/.local/bin and to accept an already-working installation.
tool_aliases() {
  case "$1" in
    fd)  printf '%s\n' fdfind ;;
    bat) printf '%s\n' batcat ;;
    *)   return 0 ;;
  esac
}

# Version flag differs between tools; keep it out of verification call sites.
tool_version_flag() {
  case "$1" in
    tmux) printf '%s\n' '-V' ;;
    *)    printf '%s\n' '--version' ;;
  esac
}

# Resolve the executable for a tool, including macOS application bundles that do
# not expose a CLI on PATH. Prints nothing and returns non-zero when absent.
tool_executable() {
  local command="$1" candidate
  if candidate="$(command -v "$command" 2>/dev/null)" && [[ -n "$candidate" && -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  local alias
  while read -r alias; do
    [[ -n "$alias" ]] || continue
    if candidate="$(command -v "$alias" 2>/dev/null)" && [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(tool_aliases "$command")
  # macOS casks install app bundles; some expose a CLI inside the bundle.
  local bundle_cli
  case "$command" in
    alacritty) bundle_cli='Alacritty.app/Contents/MacOS/alacritty' ;;
    zed)       bundle_cli='Zed.app/Contents/MacOS/cli' ;;
    *)         return 1 ;;
  esac
  for candidate in "$HOME/Applications/$bundle_cli" "/Applications/$bundle_cli"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  # App present but no runnable CLI: report the bundle so presence still counts.
  for candidate in "$HOME/Applications/${bundle_cli%%/*}" "/Applications/${bundle_cli%%/*}"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Documented Homebrew installation prefix. Used for PATH setup and to refuse a
# bootstrap into a location Homebrew does not support.
homebrew_prefix() {
  local platform="$1" arch="$2"
  case "$platform:$arch" in
    mac:aarch64)   printf '%s\n' /opt/homebrew ;;
    mac:x86_64)    printf '%s\n' /usr/local ;;
    linux:*)       printf '%s\n' /home/linuxbrew/.linuxbrew ;;
    *)             return 1 ;;
  esac
}
