#!/usr/bin/env bash

install_workstation() {
  # Retire only the identifiable npm shim from the previous installer.
  if [[ -f "$HOME/.local/bin/npm" && ! -L "$HOME/.local/bin/npm" ]] \
    && grep -qF '# npm shim — transparently delegates to pnpm' "$HOME/.local/bin/npm"; then
    backup "$HOME/.local/bin/npm"
  fi
  if ! command -v fnm >/dev/null 2>&1 && [[ ! -x "$HOME/.local/share/fnm/fnm" ]]; then
    run_installer fnm https://raw.githubusercontent.com/Schniz/fnm/master/.ci/install.sh --skip-shell
  fi
  local fnm_bin
  fnm_bin="$(command -v fnm || true)"
  [[ -n "$fnm_bin" ]] || fnm_bin="$HOME/.local/share/fnm/fnm"
  [[ -x "$fnm_bin" ]] || die 'fnm installation did not provide a binary'
  eval "$("$fnm_bin" env --shell bash)"
  if ! command -v node >/dev/null 2>&1; then
    "$fnm_bin" install 24 >>"$LOG" 2>&1
    "$fnm_bin" default 24 >>"$LOG" 2>&1
    "$fnm_bin" use 24 >>"$LOG" 2>&1
    command -v node >/dev/null 2>&1 || die 'Node.js installation did not expose node'
  fi
  if ! command -v pnpm >/dev/null 2>&1; then
    # A user prefix avoids sudo and leaves Node's own npm semantics untouched.
    # Resolve npm explicitly: a Node install may not expose it on PATH.
    local npm_bin
    npm_bin="$(command -v npm || true)"
    [[ -n "$npm_bin" ]] || npm_bin="$(dirname "$(command -v node)")/npm"
    [[ -x "$npm_bin" ]] || die 'npm is required to install pnpm; check the Node.js installation'
    "$npm_bin" install --global --prefix "$HOME/.local" pnpm >>"$LOG" 2>&1
    export PATH="$HOME/.local/bin:$PATH"
    command -v pnpm >/dev/null 2>&1 || die 'pnpm installation did not expose pnpm'
  elif [[ "$UPGRADE" == true ]]; then
    pnpm self-update >>"$LOG" 2>&1
  fi
  if [[ ! -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
    run_installer sdkman https://get.sdkman.io
  fi
  if ! command -v rustup >/dev/null 2>&1 && [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
    run_installer rustup https://sh.rustup.rs -y --no-modify-path
  elif [[ "$UPGRADE" == true ]]; then
    "$(command -v rustup || printf '%s' "$HOME/.cargo/bin/rustup")" update >>"$LOG" 2>&1
  fi
  export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
  command -v rustup >/dev/null 2>&1 || die 'rustup installation did not expose rustup'
  # Zed extension development needs these targets, but only fetch them when
  # missing: re-running setup must not make a network round-trip every time.
  if ! rustup target list --installed 2>/dev/null | grep -qx wasm32-wasip1 \
    || ! rustup target list --installed 2>/dev/null | grep -qx wasm32-wasip2; then
    rustup target add wasm32-wasip1 wasm32-wasip2 >>"$LOG" 2>&1
  fi
  if ! command -v uv >/dev/null 2>&1; then
    run_installer uv https://astral.sh/uv/install.sh
  elif [[ "$UPGRADE" == true ]]; then
    uv self update >>"$LOG" 2>&1
  fi
  if ! uv tool list | grep -q '^markitdown'; then
    uv tool install 'markitdown[all]' >>"$LOG" 2>&1
  elif [[ "$UPGRADE" == true ]]; then
    uv tool upgrade markitdown >>"$LOG" 2>&1
  fi
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes run_installer oh-my-zsh \
      https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh --unattended
  elif [[ "$UPGRADE" == true ]]; then
    sync_git_dependency https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  fi
  local plugin
  for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    sync_git_dependency "https://github.com/zsh-users/$plugin.git" "$HOME/.oh-my-zsh/custom/plugins/$plugin"
  done
  sync_git_dependency https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  sync_git_dependency https://github.com/tmux-plugins/tpm.git "$HOME/.tmux/plugins/tpm"
  install_fonts
  if ! command -v claude >/dev/null 2>&1; then
    run_installer claude https://claude.ai/install.sh
  elif [[ "$UPGRADE" == true ]]; then
    claude update >>"$LOG" 2>&1
  fi
  if [[ "$PLATFORM" == mac ]]; then
    local app
    # These casks are user applications, not system packages. Do not require a
    # second authentication just to copy them into a root-owned /Applications.
    mkdir -p "$HOME/Applications"
    for app in alacritty zed aerospace copyq; do
      if ! brew list --cask "$app" >/dev/null 2>&1; then
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
  symlink_file "$REPO_DIR/zsh/.zshrc" "$HOME/.zshrc"
  symlink_file "$REPO_DIR/zsh/p10k.zsh" "$HOME/.p10k.zsh"
  symlink_file "$REPO_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"
  symlink_file "$REPO_DIR/.markdownlint.jsonc" "$HOME/.markdownlint.jsonc"
  prepare_config_directory "$CONFIG_HOME/nvim"
  local file
  for file in init.lua lua lazy-lock.json lazyvim.json stylua.toml .gitignore .neoconf.json db_ui; do
    symlink_file "$REPO_DIR/nvim/$file" "$CONFIG_HOME/nvim/$file"
  done
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
