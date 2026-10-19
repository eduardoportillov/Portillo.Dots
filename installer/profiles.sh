#!/usr/bin/env bash

# Print the exact tool manifest of the active profile as two aligned lists.
show_components() {
  local kind name minimum description
  local required=() optional=() gated=()
  while read -r kind name minimum description; do
    [[ -n "$kind" ]] || continue
    if [[ "$kind" == required ]]; then required+=("$name"); else optional+=("$name"); fi
    [[ "$minimum" == - ]] || gated+=("$name>=$minimum")
  done < <(profile_components "$PROFILE" "$PLATFORM")
  info "Required tools (${#required[@]}): ${required[*]}"
  if [[ ${#optional[@]} -gt 0 ]]; then
    info "Optional tools (${#optional[@]}, absence is not fatal): ${optional[*]}"
  fi
  if [[ ${#gated[@]} -gt 0 ]]; then
    info "Declared minimum versions (${#gated[@]}): ${gated[*]}"
  fi
}

show_actions() {
  info "Profile: $PROFILE | Platform: $PLATFORM/$ARCH | Packages: $PACKAGE_MANAGER"
  show_components
  if [[ "${CHECK_SUDO:-false}" == true ]]; then
    info 'Read-only privileged identity check: one sudo invocation, no packages/config/service changes'
    return 0
  fi
  if [[ "${HARDEN_EXISTING_SERVICE:-false}" == true ]]; then
    info 'Harden only the matching existing Linux service script: root-owned copy + backup'
    info 'No packages, sudoers changes, service restart or hardware tuning'
    return 0
  fi
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
  local catalog="$REPO_DIR/installer/components.sh"
  local core="$REPO_DIR/installer/privileged-core.sh" entry="$REPO_DIR/installer/privileged.sh"
  [[ -f "$catalog" && -r "$catalog" && ! -L "$catalog" ]] \
    || die 'Missing or unsafe provisioning catalog; sudo was not invoked'
  [[ -f "$core" && -r "$core" && ! -L "$core" && -f "$entry" && -r "$entry" && ! -L "$entry" ]] \
    || die 'Missing or unsafe privileged payload; sudo was not invoked'
  /bin/bash -p -n "$catalog" && /bin/bash -p -n "$core" && /bin/bash -p -n "$entry" \
    || die 'Invalid privileged payload; sudo was not invoked'
  # -p ignores imported shell functions and BASH_ENV before any root code runs.
  # Functions are parsed before the final entrypoint call; its children get EOF.
  # The catalog ships inside the payload so package names resolve with no
  # additional root-time sourcing.
  cat "$catalog" "$core" "$entry" | \
    sudo /bin/bash -p -s -- "$PROFILE" "$PACKAGE_MANAGER" "$HARDWARE" "$HARDWARE_ONLY" \
    "$CHANGE_SHELL" "$UPGRADE" "$REPO_DIR" "${1:-install}" \
    2>&1 | tee -a "$LOG"
}

install_brew_tools() {
  local prefix
  prefix="$(homebrew_prefix "$PLATFORM" "$ARCH")" || die "No documented Homebrew prefix for $PLATFORM/$ARCH"
  if [[ "$PLATFORM" == mac ]] && ! command -v brew >/dev/null 2>&1; then
    # Homebrew must be pre-installed with its official installer. Bootstrapping
    # by cloning would land in a prefix we cannot verify on an untested platform,
    # and macOS Intel requires /usr/local, which is never empty enough to clone.
    die "Homebrew is required on macOS. Install it first, then re-run setup:
         /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  fi
  if [[ "$PLATFORM" == mac ]] && [[ "$(brew --prefix 2>/dev/null)" != "$prefix" ]]; then
    warn "Homebrew reports prefix '$(brew --prefix 2>/dev/null)' but the documented prefix is '$prefix'"
  fi
  export PATH="$prefix/bin:$prefix/sbin:$PATH"
  # The manifest drives the formula list through the catalog; support packages
  # (archives, treesitter tooling, ffmpeg) are plumbing, not manifest tools.
  local packages=(unzip zip) kind name package
  if [[ "$PROFILE" == workstation ]]; then
    packages+=(tree-sitter ffmpeg)
  fi
  while read -r kind name _; do
    [[ -n "$kind" ]] || continue
    package="$(tool_packages "$name" brew)"
    if [[ -n "$package" ]]; then
      append_unique packages "$package"
    fi
  done < <(profile_components "$PROFILE" "$PLATFORM")
  local installed
  [[ "$UPGRADE" == false ]] || brew update >>"$LOG" 2>&1
  # One brew query for the whole set; one invocation per package is the dominant
  # cost of a large install and returns data we already have in bulk.
  installed="$(brew list --versions 2>/dev/null || true)"
  for package in "${packages[@]}"; do
    if ! grep -q "^$package " <<<"$installed"; then
      brew install "$package" >>"$LOG" 2>&1
    elif [[ "$UPGRADE" == true ]]; then
      brew upgrade "$package" >>"$LOG" 2>&1
    fi
  done
}

install_profile() {
  [[ "$PACKAGE_MANAGER" != brew ]] || install_brew_tools
  mkdir -p "$HOME/.local/bin"
  # Some distributions ship different executable names. Create non-destructive
  # shims in ~/.local/bin; an entry the user already owns is never replaced.
  local command_name alias resolved target
  while read -r kind command_name minimum description; do
    [[ -n "$command_name" ]] || continue
    while read -r alias; do
      [[ -n "$alias" ]] || continue
      target="$HOME/.local/bin/$command_name"
      if [[ -e "$target" || -L "$target" ]]; then
        # Owned by the user or created by a previous run: leave it exactly as is.
        [[ -x "$target" ]] \
          || warn "Not replacing non-executable $target; make it executable or remove it"
        continue
      fi
      if ! command -v "$command_name" >/dev/null 2>&1; then
        resolved="$(command -v "$alias" 2>/dev/null || true)"
        if [[ -n "$resolved" ]]; then
          ln -s "$resolved" "$target"
        fi
      fi
    done < <(tool_aliases "$command_name")
  done < <(profile_components "$PROFILE" "$PLATFORM")
  export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
  if [[ "$PROFILE" == workstation ]]; then
    install_workstation
  fi
  install_source_tools "$PROFILE"
  install_opencode
}

configure_profile() {
  symlink_file "$REPO_DIR/zsh/.dircolors" "$HOME/.dircolors"
  symlink_file "$REPO_DIR/shared/shell/common.sh" "$CONFIG_HOME/portillo-dots/shell-common.sh"
  symlink_file "$REPO_DIR/shared/tmux/base.conf" "$CONFIG_HOME/portillo-dots/tmux-base.conf"
  symlink_file "$REPO_DIR/shared/nvim/base.lua" "$CONFIG_HOME/portillo-dots/nvim-base.lua"
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
  # Tighten credential files last: generation must have happened first.
  secure_known_secrets || warn 'Some credential paths could not be restricted'
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
  local _opencode_config=""
  verify_secret_permissions || failed=1
  local checks=("$HOME/.dircolors:$REPO_DIR/zsh/.dircolors"
                "$CONFIG_HOME/portillo-dots/shell-common.sh:$REPO_DIR/shared/shell/common.sh"
                "$CONFIG_HOME/portillo-dots/tmux-base.conf:$REPO_DIR/shared/tmux/base.conf"
                "$CONFIG_HOME/portillo-dots/nvim-base.lua:$REPO_DIR/shared/nvim/base.lua")
  if [[ "$PROFILE" == server ]]; then
    checks+=("$HOME/.tmux.conf:$REPO_DIR/server/tmux.conf" "$CONFIG_HOME/nvim/init.lua:$REPO_DIR/server/nvim/init.lua")
  else
    checks+=("$HOME/.tmux.conf:$REPO_DIR/tmux/tmux.conf" "$HOME/.zshrc:$REPO_DIR/zsh/.zshrc" "$CONFIG_HOME/nvim/init.lua:$REPO_DIR/nvim/init.lua")
  fi
  for pair in "${checks[@]}"; do
    destination="${pair%%:*}" source="${pair#*:}"
    if [[ ! -L "$destination" || "$(readlink "$destination")" != "$source" ]]; then
      warn "Config missing or different: $destination"
      record_event failed "config link missing or different: $destination"
      failed=1
    else
      record_event unchanged "link $destination"
    fi
  done
  [[ -f "$CONFIG_HOME/opencode/opencode.jsonc" || -f "$CONFIG_HOME/opencode/opencode.json" ]] \
    || { warn 'OpenCode global config missing'
         record_event failed 'OpenCode global config missing'
         failed=1; }
  if [[ -f "$CONFIG_HOME/opencode/opencode.jsonc" ]]; then
    _opencode_config="$CONFIG_HOME/opencode/opencode.jsonc"
  elif [[ -f "$CONFIG_HOME/opencode/opencode.json" ]]; then
    _opencode_config="$CONFIG_HOME/opencode/opencode.json"
  fi
  if [[ -n "${_opencode_config:-}" ]]; then
    # One Python invocation covers shape, Server baseline, secrets and MCP deps.
    if ! python3 -B "$REPO_DIR/opencode/check-config.py" "$_opencode_config" "$PROFILE" --deps; then
      record_event failed "OpenCode config check failed ($PROFILE baseline or MCP dependency)"
      failed=1
    fi
  fi
  return "$failed"
}

verify_profile() {
  local failed=0 kind name minimum description installed
  # The manifest drives verification, so a tool added to show_actions can never
  # silently escape the checks (and vice versa).
  while read -r kind name minimum description; do
    [[ -n "$kind" ]] || continue
    if ! tool_executable "$name" >/dev/null; then
      if [[ "$kind" == required ]]; then
        warn "Missing required tool: $name ($description)"
        record_event failed "required tool missing: $name ($description)"
        failed=1
      else
        info "Optional tool not present: $name ($description)"
        record_event skipped "optional tool absent: $name"
      fi
      continue
    fi
    [[ "$minimum" == - ]] && continue
    if ! installed="$(tool_version "$name")"; then
      # An app bundle or an unusual build may expose no parseable version.
      info "Version not detectable for $name; declared minimum is $minimum"
      continue
    fi
    if ! version_at_least "$installed" "$minimum"; then
      warn "$name $installed is older than the declared minimum $minimum ($description)"
      record_event failed "$name $installed < required $minimum"
      failed=1
    fi
  done < <(profile_components "$PROFILE" "$PLATFORM")
  verify_configs || failed=1
  if [[ "$failed" -ne 0 ]]; then
    warn "Verification FAILED: $PROFILE"
  else
    info "Verification passed: $PROFILE"
  fi
  return "$failed"
}
