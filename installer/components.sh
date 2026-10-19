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
required pi - Pi agent harness
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

# Provisioning descriptors: the single source for HOW each tool is obtained and
# upgraded. Adding a tool is one manifest line plus the entries below; tests
# enforce that every manifest command declares a provisioning path and an
# upgrade method, so a half-added tool fails the suite before it can break an
# installation. Consumers: privileged-core.sh (native packages),
# workstation.sh/opencode.sh installers (tool_source) and remote.sh (portable
# and npm provisioning inside the runtime).
#
# Methods accepted by tool_source:
#   installer:<url>   official installer fetched by run_installer
#   npm:<package>     npm --global --ignore-scripts --prefix ~/.local
#   fnm:<version>     Node.js through fnm (workstation.sh installs Node 24)
#   uv-tool:<package> uv tool install (Python CLI tools)
#   portable:<name>   verified release binary (remote runtime only)

# Native package names per package manager. Prints nothing when the tool is
# provisioned through tool_source instead. Manager: apt|dnf|pacman|brew.
tool_packages() {
  case "$2" in apt|dnf|pacman|brew) ;; *) return 2 ;; esac
  case "$1" in
    git|curl|rsync|tmux|fzf|jq|htop|zsh|bat|lazygit|lazydocker|zoxide|atuin)
      printf '%s\n' "$1" ;;
    ssh)
      case "$2" in
        apt)   printf '%s\n' openssh-client ;;
        dnf)   printf '%s\n' openssh-clients ;;
        pacman|brew) printf '%s\n' openssh ;;
      esac ;;
    nvim|rg)
      # Upstream names: neovim, ripgrep. Homebrew uses them too.
      [[ "$1" == nvim ]] && printf '%s\n' neovim || printf '%s\n' ripgrep ;;
    python3)
      case "$2" in
        pacman|brew) printf '%s\n' python ;;
        *)           printf '%s\n' python3 ;;
      esac ;;
    fd)
      case "$2" in
        pacman|brew) printf '%s\n' fd ;;
        *)           printf '%s\n' fd-find ;;
      esac ;;
    go)
      case "$2" in
        apt)   printf '%s\n' golang-go ;;
        dnf)   printf '%s\n' golang ;;
        pacman|brew) printf '%s\n' go ;;
      esac ;;
    alacritty)
      # macOS ships it as an application bundle, never as a brew formula here.
      [[ "$2" == brew ]] || printf '%s\n' alacritty ;;
    node|pnpm|rustup|uv|claude|zed|opencode|pi)
      : ;;
    *) return 0 ;;
  esac
}

# Non-native provisioning channel, as "method:spec". Empty when the tool is
# provisioned only as a native package.
tool_source() {
  case "$1" in
    node)     printf '%s\n' 'fnm:24' ;;
    pnpm)     printf '%s\n' 'npm:pnpm' ;;
    rustup)   printf '%s\n' 'installer:https://sh.rustup.rs' ;;
    uv)       printf '%s\n' 'installer:https://astral.sh/uv/install.sh' ;;
    claude)   printf '%s\n' 'installer:https://claude.ai/install.sh' ;;
    zed)      printf '%s\n' 'installer:https://zed.dev/install.sh' ;;
    opencode) printf '%s\n' 'installer:https://opencode.ai/v2/install' ;;
    pi)       printf '%s\n' 'npm:@earendil-works/pi-coding-agent' ;;
    *) return 0 ;;
  esac
}

# Dependencies on other manifest commands, as "name>=version" or bare "name".
# Empty when the tool has no managed dependency. version_at_least enforces the
# declared floor before provisioning.
tool_requires() {
  case "$1" in
    pnpm) printf '%s\n' 'node' ;;
    pi)   printf '%s\n' 'node>=22.19' ;;
    *) return 0 ;;
  esac
}

# Upgrade channel consumed by --upgrade:
#   manager            native package manager / Homebrew
#   self:<command>     the tool's own updater
#   installer:<url>    re-run the official installer
#   none               no supported upgrade path
tool_upgrade() {
  case "$1" in
    node)     printf '%s\n' 'none' ;;
    pnpm)     printf '%s\n' 'self:pnpm self-update' ;;
    rustup)   printf '%s\n' 'self:rustup update' ;;
    uv)       printf '%s\n' 'self:uv self update' ;;
    claude)   printf '%s\n' 'self:claude update' ;;
    zed)      printf '%s\n' 'installer:https://zed.dev/install.sh' ;;
    opencode) printf '%s\n' 'installer:https://opencode.ai/v2/install' ;;
    pi)       printf '%s\n' 'self:pi update' ;;
    git|curl|ssh|rsync|tmux|nvim|rg|fd|fzf|bat|jq|htop|python3|zsh|go|alacritty|lazygit|lazydocker|zoxide|atuin)
      printf '%s\n' 'manager' ;;
    *) return 0 ;;
  esac
}

# Remote runtime toolset (remote.sh): portable binaries the transient runtime
# provides, as "kind name". This is the single source for the install
# verification and remote.sh status lists; per-tool downloads (URLs, checksums,
# extraction) stay bespoke in remote.sh. Passed to the remote scripts through
# PORTILLO_RUNTIME_BINS because they run on the host without the repo.
remote_runtime_components() {
  cat <<'EOF'
required nvim
required rg
required fd
required fzf
required lazygit
required node
required npm
required stylua
optional tmux
EOF
}
