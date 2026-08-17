#!/usr/bin/env bash
set -uo pipefail

if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/lib.sh"
fi

ARCH="$(detect_arch)" || exit 1
OS="$(detect_os)"     || exit 1

DL_DIR="$REMOTE_BASE/downloads"

symlink_if_exists() {
  local bin_name="$1"
  local system_path
  system_path="$(command -v "$bin_name" 2>/dev/null)" || true

  if [[ -n "$system_path" && "$system_path" != "$REMOTE_BIN/"* ]]; then
    ln -sf "$system_path" "$REMOTE_BIN/$bin_name"
    ok "$bin_name → symlink to $system_path"
    return 0
  fi
  return 1
}

install_neovim() {
  info "neovim..."

  if [[ -f "$DL_DIR/nvim.appimage" ]]; then
    chmod +x "$DL_DIR/nvim.appimage"
    mv "$DL_DIR/nvim.appimage" "$REMOTE_BIN/nvim"
    if ! "$REMOTE_BIN/nvim" --version &>/dev/null; then
      info "AppImage needs extraction..."
      (cd "$REMOTE_BIN" && "$REMOTE_BIN/nvim" --appimage-extract &>/dev/null)
      if [[ -d "$REMOTE_BIN/squashfs-root" ]]; then
        mv "$REMOTE_BIN/squashfs-root/usr/bin/nvim" "$REMOTE_BIN/nvim" 2>/dev/null
        rm -rf "$REMOTE_BIN/squashfs-root"
      fi
    fi
    ok "neovim installed"
  elif [[ -f "$DL_DIR/nvim.tar.gz" ]]; then
    tar xzf "$DL_DIR/nvim.tar.gz" -C "$DL_DIR"
    local nvim_bin
    nvim_bin="$(find "$DL_DIR" -type f -name "nvim" ! -path "$DL_DIR/nvim.tar.gz" | head -1)"
    if [[ -n "$nvim_bin" ]]; then
      chmod +x "$nvim_bin"
      mv "$nvim_bin" "$REMOTE_BIN/nvim"
    fi
    ok "neovim installed"
  elif symlink_if_exists "nvim"; then
    return 0
  elif [[ -x "$REMOTE_BIN/nvim" ]]; then
    ok "neovim (already installed)"
  else
    warn "neovim: no binary provided"
  fi
}

install_tmux() {
  info "tmux..."
  symlink_if_exists "tmux" && return 0

  if [[ -f "$DL_DIR/tmux" ]]; then
    chmod +x "$DL_DIR/tmux"
    mv "$DL_DIR/tmux" "$REMOTE_BIN/tmux"
    if "$REMOTE_BIN/tmux" -V &>/dev/null; then
      ok "tmux installed"
    else
      rm -f "$REMOTE_BIN/tmux"
      warn "tmux download is invalid; Bash fallback will be used"
    fi
  elif [[ -x "$REMOTE_BIN/tmux" ]]; then
    if "$REMOTE_BIN/tmux" -V &>/dev/null; then
      ok "tmux (already installed)"
    else
      rm -f "$REMOTE_BIN/tmux"
      warn "invalid tmux removed; Bash fallback will be used"
    fi
  else
    warn "tmux not installed on host; remote.sh will use Bash without tmux"
  fi
}

install_ripgrep() {
  info "ripgrep..."
  symlink_if_exists "rg" && return 0

  if [[ -f "$DL_DIR/rg.tar.gz" ]]; then
    tar xzf "$DL_DIR/rg.tar.gz" -C "$DL_DIR"
    local binary
    binary="$(find "$DL_DIR" -type f -name "rg" | head -1)"
    if [[ -n "$binary" ]]; then
      chmod +x "$binary"
      mv "$binary" "$REMOTE_BIN/rg"
    fi
    ok "ripgrep installed"
  elif [[ -x "$REMOTE_BIN/rg" ]]; then
    ok "ripgrep (already installed)"
  else
    warn "ripgrep: no binary provided"
  fi
}

install_fd() {
  info "fd..."
  symlink_if_exists "fd" && return 0

  if [[ -f "$DL_DIR/fd.tar.gz" ]]; then
    tar xzf "$DL_DIR/fd.tar.gz" -C "$DL_DIR"
    local binary
    binary="$(find "$DL_DIR" -type f -name "fd" | head -1)"
    if [[ -n "$binary" ]]; then
      chmod +x "$binary"
      mv "$binary" "$REMOTE_BIN/fd"
    fi
    ok "fd installed"
  elif [[ -x "$REMOTE_BIN/fd" ]]; then
    ok "fd (already installed)"
  else
    warn "fd: no binary provided"
  fi
}

install_fzf() {
  info "fzf..."
  symlink_if_exists "fzf" && return 0

  if [[ -f "$DL_DIR/fzf.tar.gz" ]]; then
    local fzf_dir="$REMOTE_BASE/fzf"
    rm -rf "$fzf_dir"
    mkdir -p "$fzf_dir/bin"
    tar xzf "$DL_DIR/fzf.tar.gz" -C "$fzf_dir/bin/"
    if [[ -x "$fzf_dir/bin/fzf" ]]; then
      ln -sf "$fzf_dir/bin/fzf" "$REMOTE_BIN/fzf"
      ok "fzf installed"
    else
      warn "fzf: binary not found in archive"
    fi
  elif [[ -f "$DL_DIR/fzf" ]]; then
    chmod +x "$DL_DIR/fzf"
    mv "$DL_DIR/fzf" "$REMOTE_BIN/fzf"
    ok "fzf installed"
  elif [[ -x "$REMOTE_BIN/fzf" ]]; then
    ok "fzf (already installed)"
  else
    warn "fzf: no binary provided"
  fi
}

install_lazygit() {
  info "lazygit..."
  symlink_if_exists "lazygit" && return 0

  if [[ -f "$DL_DIR/lazygit.tar.gz" ]]; then
    tar xzf "$DL_DIR/lazygit.tar.gz" -C "$DL_DIR"
    local binary
    binary="$(find "$DL_DIR" -type f -name "lazygit" | head -1)"
    if [[ -n "$binary" ]]; then
      chmod +x "$binary"
      mv "$binary" "$REMOTE_BIN/lazygit"
    fi
    ok "lazygit installed"
  elif [[ -x "$REMOTE_BIN/lazygit" ]]; then
    ok "lazygit (already installed)"
  else
    warn "lazygit: no binary provided"
  fi
}

install_node() {
  info "node & npm..."
  if [[ -f "$DL_DIR/node.tar.xz" ]]; then
    local node_dir="$REMOTE_BASE/node"
    rm -rf "$node_dir"
    mkdir -p "$node_dir"
    tar -xf "$DL_DIR/node.tar.xz" -C "$node_dir" --strip-components=1
    if [[ -x "$node_dir/bin/node" ]]; then
      ln -sf "$node_dir/bin/node" "$REMOTE_BIN/node"
      ln -sf "$node_dir/bin/npm" "$REMOTE_BIN/npm"
      ln -sf "$node_dir/bin/npx" "$REMOTE_BIN/npx"
      ok "node & npm installed"
      return 0
    fi
  fi
  symlink_if_exists "node" && symlink_if_exists "npm" && return 0
  if [[ -x "$REMOTE_BIN/node" ]]; then
    ok "node & npm (already installed)"
  else
    warn "node: not installed"
  fi
}

install_zig_cc() {
  info "C compiler (zig cc)..."
  if [[ -f "$DL_DIR/zig.tar.xz" ]]; then
    local zig_dir="$REMOTE_BASE/zig"
    rm -rf "$zig_dir"
    mkdir -p "$zig_dir"
    tar -xf "$DL_DIR/zig.tar.xz" -C "$zig_dir" --strip-components=1
    local zig_bin="$zig_dir/zig"
    if [[ -x "$zig_bin" ]]; then
      ln -sf "$zig_bin" "$REMOTE_BIN/zig"
      cat > "$REMOTE_BIN/cc" <<'CC_EOF'
#!/usr/bin/env bash
args=()
for arg in "$@"; do
  case "$arg" in
    *unknown-linux*)
      arg="${arg//unknown-linux/linux}"
      ;;
  esac
  args+=("$arg")
done
exec "$HOME/.portillo-remote/zig/zig" cc "${args[@]}"
CC_EOF
      chmod +x "$REMOTE_BIN/cc"
      ln -sf "$REMOTE_BIN/cc" "$REMOTE_BIN/gcc"
      ok "C compiler (zig cc) installed"
      return 0
    fi
  fi
  symlink_if_exists "gcc" && symlink_if_exists "cc" && return 0
  if [[ -x "$REMOTE_BIN/cc" ]]; then
    ok "C compiler (already installed)"
  else
    warn "C compiler: not installed"
  fi
}

install_stylua() {
  info "stylua..."
  symlink_if_exists "stylua" && return 0

  if [[ -f "$DL_DIR/stylua.zip" ]]; then
    if command -v unzip &>/dev/null; then
      unzip -qo "$DL_DIR/stylua.zip" -d "$REMOTE_BIN"
      chmod +x "$REMOTE_BIN/stylua" 2>/dev/null || true
    elif command -v python3 &>/dev/null; then
      python3 -c "import zipfile; zipfile.ZipFile('$DL_DIR/stylua.zip').extractall('$REMOTE_BIN')"
      chmod +x "$REMOTE_BIN/stylua" 2>/dev/null || true
    fi
    if [[ -x "$REMOTE_BIN/stylua" ]]; then
      ok "stylua installed"
      return 0
    fi
  elif [[ -f "$DL_DIR/stylua" ]]; then
    chmod +x "$DL_DIR/stylua"
    mv "$DL_DIR/stylua" "$REMOTE_BIN/stylua"
    ok "stylua installed"
    return 0
  fi

  if [[ -x "$REMOTE_BIN/stylua" ]]; then
    ok "stylua (already installed)"
  else
    warn "stylua: no binary provided"
  fi
}

setup_lazy_nvim() {
  if ! command -v git &>/dev/null; then
    warn "git not found on remote host; install git ('sudo apt install -y git') so LazyVim can clone plugins"
    return 1
  fi
  info "Pre-installing lazy.nvim..."
  local lazy_dir="$REMOTE_NVIM_SHARE/lazy/lazy.nvim"
  if [[ -d "$lazy_dir" ]]; then
    git -C "$lazy_dir" pull --ff-only 2>/dev/null
    ok "lazy.nvim up to date"
    return 0
  fi
  mkdir -p "$(dirname "$lazy_dir")"
  if git clone --filter=blob:none https://github.com/folke/lazy.nvim.git "$lazy_dir" 2>/dev/null; then
    ok "lazy.nvim cloned"
  else
    warn "Failed to clone lazy.nvim"
    return 1
  fi
}

setup_nvim_config_symlink() {
  local nvim_app_dir="$HOME/.config/portillo-remote/nvim"
  if [[ -L "$nvim_app_dir" ]] && [[ "$(readlink "$nvim_app_dir")" == "$REMOTE_BASE/nvim" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$nvim_app_dir")"
  ln -sf "$REMOTE_BASE/nvim" "$nvim_app_dir"
  ok "nvim config symlink created"
}

setup_tpm() {
  if ! command -v git &>/dev/null; then
    warn "git not found on remote host; TPM clone skipped"
    return 0
  fi
  info "Installing TPM and plugins..."
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  mkdir -p "$HOME/.tmux/plugins"
  if [[ ! -d "$tpm_dir" ]]; then
    git clone --depth 1 https://github.com/tmux-plugins/tpm.git "$tpm_dir" 2>/dev/null || true
  fi

  local user_tmux_conf="$HOME/.tmux.conf"
  if [[ ! -e "$user_tmux_conf" ]] || [[ -L "$user_tmux_conf" ]]; then
    ln -sf "$REMOTE_BASE/tmux/tmux.conf" "$user_tmux_conf"
  fi

  if [[ -x "$tpm_dir/bin/install_plugins" ]] && command -v tmux &>/dev/null; then
    tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$HOME/.tmux/plugins/" 2>/dev/null || true
    "$tpm_dir/bin/install_plugins" &>/dev/null || true
    ok "TPM and plugins installed"
  else
    ok "TPM installed"
  fi
}

main() {
  echo ""
  echo "=== Portillo Remote Binary Installer ==="
  echo "Arch: $ARCH | OS: $OS"
  echo ""

  ensure_dir "$REMOTE_BIN"

  install_neovim
  install_tmux
  install_ripgrep
  install_fd
  install_fzf
  install_lazygit
  install_node
  install_zig_cc
  install_stylua

  echo ""
  info "Post-install setup..."
  setup_lazy_nvim
  setup_nvim_config_symlink
  setup_tpm

  echo ""
  ok "All binaries installed"
  info "Binaries in: $REMOTE_BIN"
  ls -la "$REMOTE_BIN"
}

main "$@"
