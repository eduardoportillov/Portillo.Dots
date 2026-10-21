#!/usr/bin/env bash

install_workstation() {
  # Retire only the identifiable npm shim from the previous installer.
  if [[ -f "$HOME/.local/bin/npm" && ! -L "$HOME/.local/bin/npm" ]] \
    && grep -qF '# npm shim — transparently delegates to pnpm' "$HOME/.local/bin/npm"; then
    backup "$HOME/.local/bin/npm"
  fi
  export PATH="$HOME/.local/bin:$PATH"
  # Node and pnpm come from the provisioning catalog (install_source_tools).
  # ensure_node_runtime provides the fnm-managed Node their npm channel needs.
  ensure_node_runtime 24
  if [[ ! -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
    run_installer sdkman https://get.sdkman.io
  fi
  export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
  if ! command -v rustup >/dev/null 2>&1 && [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
    run_installer rustup https://sh.rustup.rs -y --no-modify-path
  elif [[ "$UPGRADE" == true ]]; then
    apply_tool_upgrade rustup
  fi
  command -v rustup >/dev/null 2>&1 || die 'rustup installation did not expose rustup'
  # Zed extension development needs these targets, but only fetch them when
  # missing: re-running setup must not make a network round-trip every time.
  # One query covers both targets; asking twice would spawn rustup twice.
  local installed_targets
  installed_targets="$(rustup target list --installed 2>/dev/null || true)"
  if ! grep -qx 'wasm32-wasip1' <<<"$installed_targets" \
    || ! grep -qx 'wasm32-wasip2' <<<"$installed_targets"; then
    rustup target add wasm32-wasip1 wasm32-wasip2 >>"$LOG" 2>&1
  fi
  if ! command -v uv >/dev/null 2>&1; then
    run_installer uv https://astral.sh/uv/install.sh
  elif [[ "$UPGRADE" == true ]]; then
    apply_tool_upgrade uv
  fi
  if ! uv tool list | grep -q '^markitdown'; then
    uv tool install 'markitdown[all]' >>"$LOG" 2>&1
  elif [[ "$UPGRADE" == true ]]; then
    uv tool upgrade markitdown >>"$LOG" 2>&1
  fi
  sync_git_dependency https://github.com/tmux-plugins/tpm.git "$HOME/.tmux/plugins/tpm"
  install_fonts
  if ! command -v claude >/dev/null 2>&1; then
    run_installer claude https://claude.ai/install.sh
  elif [[ "$UPGRADE" == true ]]; then
    apply_tool_upgrade claude
  fi
  if [[ "$PLATFORM" == mac ]]; then
    local app
    # These casks are user applications, not system packages. Do not require a
    # second authentication just to copy them into a root-owned /Applications.
    mkdir -p "$HOME/Applications"
    # One brew query for the whole cask set instead of one invocation per app.
    local installed_casks
    installed_casks="$(brew list --cask --versions 2>/dev/null || true)"
    for app in alacritty zed aerospace copyq; do
      if ! grep -q "^$app " <<<"$installed_casks"; then
        brew install --cask --appdir="$HOME/Applications" "$app" >>"$LOG" 2>&1
      elif [[ "$UPGRADE" == true ]]; then
        brew upgrade --cask --appdir="$HOME/Applications" "$app" >>"$LOG" 2>&1
      fi
    done
  elif ! command -v zed >/dev/null 2>&1 || [[ "$UPGRADE" == true ]]; then
    run_installer zed https://zed.dev/install.sh
  fi
}

install_fonts() {
  if [[ "$PLATFORM" == mac ]]; then
    brew list --cask font-hack-nerd-font >/dev/null 2>&1 \
      || brew install --cask font-hack-nerd-font >>"$LOG" 2>&1
  elif ! command -v fc-match >/dev/null 2>&1 || ! fc-match 'Hack Nerd Font' | grep -q 'Hack'; then
    local destination="$HOME/.local/share/fonts"
    mkdir -p "$destination" "$WORK_DIR/fonts"
    curl --proto '=https' --tlsv1.2 -fsSL --connect-timeout 15 --max-time 300 \
      https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip -o "$WORK_DIR/Hack.zip"
    unzip -q "$WORK_DIR/Hack.zip" -d "$WORK_DIR/fonts"
    find "$WORK_DIR/fonts" -type f -name '*.ttf' -exec cp '{}' "$destination/" \;
    if command -v fc-cache >/dev/null 2>&1; then fc-cache -f "$destination"; fi
  fi
  return 0
}

prepare_config_directory() {
  local directory="$1"
  # Do not write children through an old directory symlink into another repo.
  if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
    backup "$directory"
  fi
  mkdir -p "$directory"
}

configure_workstation() {
  symlink_file "$REPO_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"
  symlink_file "$REPO_DIR/.markdownlint.jsonc" "$HOME/.markdownlint.jsonc"
  local file
  prepare_config_directory "$CONFIG_HOME/alacritty"
  symlink_file "$REPO_DIR/alacritty/themes/kanagawa_dragon.toml" "$CONFIG_HOME/alacritty/themes/kanagawa_dragon.toml"
  if [[ "$PLATFORM" == mac ]]; then
    symlink_file "$REPO_DIR/alacritty/alacritty.macos.toml" "$CONFIG_HOME/alacritty/alacritty.toml"
    symlink_file "$REPO_DIR/aerospace/aerospace.toml" "$HOME/.aerospace.toml"
  else
    symlink_file "$REPO_DIR/alacritty/alacritty.toml" "$CONFIG_HOME/alacritty/alacritty.toml"
  fi
  prepare_config_directory "$HOME/.claude"
  symlink_file "$REPO_DIR/claude/settings.json" "$HOME/.claude/settings.json"
  symlink_file "$REPO_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  # Zed contains personal SSH destinations: preserve an independent config.
  prepare_config_directory "$CONFIG_HOME/zed"
  for file in settings.json keymap.json; do
    if [[ ! -e "$CONFIG_HOME/zed/$file" && ! -L "$CONFIG_HOME/zed/$file" ]]; then
      symlink_file "$REPO_DIR/zed/$file" "$CONFIG_HOME/zed/$file"
    fi
  done
  mkdir -p "$HOME/.local/bin"
  symlink_file "$REPO_DIR/remote.sh" "$HOME/.local/bin/dots-remote"
  if [[ "$PLATFORM" == linux ]]; then
    symlink_file "$REPO_DIR/linux/dots-fix-tiling.sh" "$HOME/.local/bin/dots-fix-tiling"
    symlink_file "$REPO_DIR/linux/dots-diag.sh" "$HOME/.local/bin/dots-diag"
    # Tema de sonido portillo: silencia solo el evento screen-capture (clic de
    # cámara de las capturas); hereda Yaru,freedesktop para el resto de sonidos.
    symlink_file "$REPO_DIR/linux/sound-theme/portillo/index.theme" \
      "$HOME/.local/share/sounds/portillo/index.theme"
    symlink_file "$REPO_DIR/linux/sound-theme/portillo/stereo/screen-capture.oga" \
      "$HOME/.local/share/sounds/portillo/stereo/screen-capture.oga"
  fi
  if [[ "$PLATFORM" == linux && -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v gsettings >/dev/null 2>&1; then
    bash "$REPO_DIR/gnome/configure.sh" >>"$LOG" 2>&1
    # Known-broken o-tiling stays opt-in, never deleted/enabled by setup.
    warn 'o-tiling is not installed automatically; see TODO.md for the known GNOME issue'
  fi
  if [[ "$CONFIG_ONLY" == false && -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]]; then
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" >>"$LOG" 2>&1
  fi
}
