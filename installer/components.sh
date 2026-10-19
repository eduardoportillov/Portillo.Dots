#!/usr/bin/env bash
# Single source of truth for the tools each profile installs and verifies.
# One line per tool: "<kind> <command> <description>"
#   kind=required : profile is incomplete without it (verification fails)
#   kind=optional : nice to have; absence is reported but never fatal
#
# Every consumer must read this file: show_actions lists it, install targets it,
# verify_profile checks it. Adding a tool in one place keeps them in agreement.

profile_components() {
  local profile="$1" platform="$2"
  case "$profile" in workstation|server) ;; *) printf 'Invalid profile: %s\n' "$profile" >&2; return 2 ;; esac
  case "$platform" in linux|mac) ;; *) printf 'Invalid platform: %s\n' "$platform" >&2; return 2 ;; esac

  cat <<'EOF'
required git Version control
required curl Downloads and API calls
required ssh Remote access client
required rsync Remote file sync
required tmux Terminal multiplexer
required nvim Neovim editor
required rg ripgrep text search
required fd fd file search
required fzf Fuzzy finder
required bat bat file viewer
required jq JSON processor
required htop Process monitor
required python3 Python runtime
required opencode OpenCode V2 agent client
EOF

  if [[ "$profile" == workstation ]]; then
    cat <<'EOF'
required zsh Zsh shell
required node Node.js runtime
required pnpm pnpm package manager
required go Go toolchain
required rustup Rust toolchain
required uv Python package manager
required claude Claude Code client
required zed Zed editor
optional lazygit Git TUI
optional lazydocker Docker TUI
optional zoxide Smart cd
optional atuin Shell history
EOF
  fi
}
