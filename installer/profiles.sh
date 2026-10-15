#!/usr/bin/env bash

show_actions() {
  info "Profile: $PROFILE | Platform: $PLATFORM/$ARCH | Packages: $PACKAGE_MANAGER"
  if [[ "$CONFIG_ONLY" == true ]]; then
    info 'User configs only: no sudo, downloads, packages or system services'
  else
    info 'One system phase: native CLI packages (Git, SSH client, rsync, tmux, Neovim, rg, fd, fzf, bat, jq, htop, Python)'
    if [[ "$PROFILE" == workstation ]]; then
      info 'Development: Node/pnpm, Go, Rust, SDKMAN, uv, MarkItDown, shell plugins, OpenCode and Claude Code'
      info 'Desktop: Alacritty/fonts, Zed, GNOME or AeroSpace (when applicable)'
    else
      info 'Server: OpenCode; no desktop, toolchains, daemon setup or login-shell change'
    fi
    [[ "$UPGRADE" == false ]] || info 'Explicit upgrades enabled (Arch repository sync always requires a full system upgrade)'
  fi
  [[ "$HARDWARE" == false ]] || info 'OPT-IN: CPU/memory settings, BAT1 charge limit (60%), root-owned system service'
  [[ "$CHANGE_SHELL" == false ]] || info 'OPT-IN: change login shell to Zsh'
  [[ "$OPENCODE_TEMPLATE" == false ]] || warn 'Custom OpenCode template selected: review V2 compatibility of its plugins'
}

privileged_phase() {
  info 'System phase: sudo may request your password once; no sudoers rule is created'
  # A single sudo process keeps root authority only for this helper's lifetime.
  # Use stdin so the helper is loaded once, not kept as a user-writable daemon.
  sudo /bin/bash -s -- "$PROFILE" "$PACKAGE_MANAGER" "$HARDWARE" "$HARDWARE_ONLY" \
    "$CHANGE_SHELL" "$UPGRADE" "$REPO_DIR" < "$REPO_DIR/installer/privileged.sh" \
    2>&1 | tee -a "$LOG"
}

install_brew_tools() {
  if [[ "$PLATFORM" == mac ]] && ! command -v brew >/dev/null 2>&1; then
    local prefix
    if [[ "$ARCH" == aarch64 ]]; then prefix=/opt/homebrew; else prefix=/usr/local/Homebrew; fi
    [[ -d "$prefix" && -w "$prefix" && ! -L "$prefix" && -z "$(ls -A "$prefix")" ]] \
      || die "Homebrew prefix is not an empty writable directory: $prefix"
    git clone https://github.com/Homebrew/brew.git "$prefix" >>"$LOG" 2>&1
    export PATH="$prefix/bin:$PATH"
    eval "$("$prefix/bin/brew" shellenv)"
  fi
  local packages=(git curl unzip zip rsync tmux neovim ripgrep fd fzf bat jq htop python)
  [[ "$PROFILE" != workstation ]] || packages+=(lazygit lazydocker zsh tree-sitter zoxide atuin go ffmpeg)
  local package
  [[ "$UPGRADE" == false ]] || brew update >>"$LOG" 2>&1
  for package in "${packages[@]}"; do
    if ! brew list --versions "$package" >/dev/null 2>&1; then
      brew install "$package" >>"$LOG" 2>&1
    elif [[ "$UPGRADE" == true ]]; then
      brew upgrade "$package" >>"$LOG" 2>&1
    fi
  done
}

install_profile() {
  [[ "$PACKAGE_MANAGER" != brew ]] || install_brew_tools
  mkdir -p "$HOME/.local/bin"
  # Debian names the executables differently; don't overwrite user binaries.
  local pair original alias
  for pair in 'fdfind:fd' 'batcat:bat'; do
    original="${pair%:*}" alias="${pair#*:}"
    if ! command -v "$alias" >/dev/null 2>&1 && command -v "$original" >/dev/null 2>&1; then
      [[ ! -e "$HOME/.local/bin/$alias" && ! -L "$HOME/.local/bin/$alias" ]] || die "Conflicting executable: $alias"
      ln -s "$(command -v "$original")" "$HOME/.local/bin/$alias"
    fi
  done
  export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
  if [[ "$PROFILE" == workstation ]]; then
    check_workstation_neovim || die 'Upgrade Neovim before configuring LazyVim (native package too old; consider Homebrew)'
    install_workstation
  fi
  install_opencode
}

check_workstation_neovim() {
  local version major minor
  version="$(nvim --version | sed -n '1s/.*v\([0-9]*\.[0-9]*\).*/\1/p')"
  major="${version%%.*}" minor="${version#*.}"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
  [[ "$major" -gt 0 || "$minor" -ge 11 ]]
}

configure_profile() {
  symlink_file "$REPO_DIR/zsh/.dircolors" "$HOME/.dircolors"
  if [[ "$PROFILE" == server ]]; then
    symlink_file "$REPO_DIR/server/tmux.conf" "$HOME/.tmux.conf"
    prepare_config_directory "$CONFIG_HOME/nvim"
    symlink_file "$REPO_DIR/server/nvim/init.lua" "$CONFIG_HOME/nvim/init.lua"
    symlink_file "$REPO_DIR/server/shell.sh" "$CONFIG_HOME/portillo-dots/server.sh"
    configure_server_shell
  else
    configure_workstation
  fi
  configure_opencode
}

configure_server_shell() {
  local rc
  case "${SHELL##*/}" in
    bash) rc="$HOME/.bashrc" ;;
    zsh) rc="${ZDOTDIR:-$HOME}/.zshrc" ;;
    *) warn 'Unsupported shell integration: add ~/.local/bin and ~/.opencode/bin to PATH manually'; return 0 ;;
  esac
  if [[ -L "$rc" ]]; then
    warn "Preserving symlinked shell config: $rc; source portillo-dots/server.sh manually"
    return 0
  fi
  python3 "$REPO_DIR/installer/shell-block.py" "$rc" "$BACKUP_DIR"
}

verify_configs() {
  local failed=0 pair destination source
  local checks=("$HOME/.dircolors:$REPO_DIR/zsh/.dircolors")
  if [[ "$PROFILE" == server ]]; then
    checks+=("$HOME/.tmux.conf:$REPO_DIR/server/tmux.conf" "$CONFIG_HOME/nvim/init.lua:$REPO_DIR/server/nvim/init.lua")
  else
    checks+=("$HOME/.tmux.conf:$REPO_DIR/tmux/tmux.conf" "$HOME/.zshrc:$REPO_DIR/zsh/.zshrc" "$CONFIG_HOME/nvim/init.lua:$REPO_DIR/nvim/init.lua")
  fi
  for pair in "${checks[@]}"; do
    destination="${pair%%:*}" source="${pair#*:}"
    if [[ ! -L "$destination" || "$(readlink "$destination")" != "$source" ]]; then
      warn "Config missing or different: $destination"; failed=1
    fi
  done
  [[ -f "$CONFIG_HOME/opencode/opencode.jsonc" || -f "$CONFIG_HOME/opencode/opencode.json" ]] \
    || { warn 'OpenCode global config missing'; failed=1; }
  if [[ -f "$CONFIG_HOME/opencode/opencode.jsonc" ]]; then
    python3 -B "$REPO_DIR/opencode/check-config.py" "$CONFIG_HOME/opencode/opencode.jsonc" "$PROFILE" || failed=1
  elif [[ -f "$CONFIG_HOME/opencode/opencode.json" ]]; then
    python3 -B "$REPO_DIR/opencode/check-config.py" "$CONFIG_HOME/opencode/opencode.json" "$PROFILE" || failed=1
  fi
  return "$failed"
}

verify_profile() {
  local failed=0 binary
  local binaries=(git curl ssh rsync tmux nvim rg fd fzf bat jq htop python3 opencode)
  [[ "$PROFILE" != workstation ]] || binaries+=(zsh node pnpm go rustup uv claude zed)
  for binary in "${binaries[@]}"; do
    if ! command -v "$binary" >/dev/null 2>&1; then
      warn "Missing: $binary"; failed=1
    fi
  done
  if command -v opencode >/dev/null 2>&1; then
    opencode --version | grep -Eq '(^|v)2\.' || { warn 'OpenCode V2 is required'; failed=1; }
  fi
  if [[ "$PROFILE" == workstation ]] && command -v nvim >/dev/null 2>&1; then
    if ! check_workstation_neovim; then
      warn 'LazyVim requires Neovim >= 0.11; use a newer distro package or Homebrew'; failed=1
    fi
  fi
  verify_configs || failed=1
  [[ "$failed" -ne 0 ]] || info "Verification passed: $PROFILE"
  return "$failed"
}
