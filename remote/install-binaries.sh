#!/usr/bin/env bash
set -euo pipefail

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
  if [[ -f "$DL_DIR/nvim.tar.gz" ]]; then
    local runtime="$REMOTE_BASE/nvim-runtime"
    [[ ! -L "$runtime" ]] || { error 'Unsafe Neovim runtime path'; return 1; }
    local digest
    digest="$(file_digest "$DL_DIR/nvim.tar.gz")"
    if [[ -f "$runtime/.archive-sha256" && "$(cat "$runtime/.archive-sha256")" == "$digest" && -x "$runtime/bin/nvim" ]]; then
      ln -sfn "$runtime/bin/nvim" "$REMOTE_BIN/nvim"
      ok 'neovim runtime unchanged; extraction skipped'
      return 0
    fi
    local extracted
    extracted="$(mktemp -d "$REMOTE_BASE/.nvim.XXXXXXXX")"
    tar xzf "$DL_DIR/nvim.tar.gz" -C "$extracted" --strip-components=1
    if [[ ! -x "$extracted/bin/nvim" || ! -d "$extracted/share/nvim/runtime" ]]; then
      rm -rf "$extracted"
      error 'Incomplete Neovim distribution'
      return 1
    fi
    "$extracted/bin/nvim" --version >/dev/null || { rm -rf "$extracted"; return 1; }
    printf '%s\n' "$digest" > "$extracted/.archive-sha256"
    rm -rf "$runtime"
    mv "$extracted" "$runtime"
    # Keep bin/, lib/ and share/ together; Neovim resolves runtime relatively.
    ln -sfn "$runtime/bin/nvim" "$REMOTE_BIN/nvim"
    ok 'neovim installed with its complete runtime'
  elif symlink_if_exists "nvim"; then
    return 0
  elif [[ -x "$REMOTE_BIN/nvim" ]]; then
    ok "neovim (already installed)"
  else
    error "neovim: no binary provided"
    return 1
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
    [[ ! -L "$node_dir" ]] || { error 'Unsafe Node runtime path'; return 1; }
    local digest
    digest="$(file_digest "$DL_DIR/node.tar.xz")"
    if [[ -f "$node_dir/.archive-sha256" && "$(cat "$node_dir/.archive-sha256")" == "$digest" && -x "$node_dir/bin/node" ]]; then
      ok 'node runtime unchanged; extraction skipped'
      return 0
    fi
    rm -rf "$node_dir"
    mkdir -p "$node_dir"
    tar -xf "$DL_DIR/node.tar.xz" -C "$node_dir" --strip-components=1
    if [[ -x "$node_dir/bin/node" ]]; then
      ln -sf "$node_dir/bin/node" "$REMOTE_BIN/node"
      ln -sf "$node_dir/bin/npm" "$REMOTE_BIN/npm"
      ln -sf "$node_dir/bin/npx" "$REMOTE_BIN/npx"
      printf '%s\n' "$digest" > "$node_dir/.archive-sha256"
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
    [[ ! -L "$zig_dir" ]] || { error 'Unsafe Zig runtime path'; return 1; }
    local digest
    digest="$(file_digest "$DL_DIR/zig.tar.xz")"
    if [[ -f "$zig_dir/.archive-sha256" && "$(cat "$zig_dir/.archive-sha256")" == "$digest" && -x "$REMOTE_BIN/cc" ]]; then
      ok 'C compiler runtime unchanged; extraction skipped'
      return 0
    fi
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
      printf '%s\n' "$digest" > "$zig_dir/.archive-sha256"
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
    ok "lazy.nvim already installed (versions managed by lazy-lock.json)"
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
  if [[ -e "$nvim_app_dir" || -L "$nvim_app_dir" ]]; then
    local saved
    saved="$(mktemp -d "$(dirname "$nvim_app_dir")/.nvim-backup.XXXXXXXX")"
    mv "$nvim_app_dir" "$saved/nvim"
  fi
  ln -s "$REMOTE_BASE/nvim" "$nvim_app_dir"
  ok "nvim config symlink created"
}

setup_server_nvim_config() {
  # Compatibility entrypoint: server is no longer a different editor.
  setup_nvim_config_symlink
}

setup_tpm() {
  # Bare runtimes keep tmux isolated; setup-managed hosts supply the shared overlay.
  return 0
}

main() {
  echo ""
  echo "=== Portillo Remote Binary Installer ==="
  echo "Arch: $ARCH | OS: $OS"
  echo ""

  ensure_dir "$REMOTE_BIN"

  # The toolset comes from the provisioning catalog through remote.sh; each
  # tool maps to its bespoke installer (URLs, checksums and extraction are
  # tool-specific).
  local binary runtime_bins=()
  read -r -a runtime_bins <<< "${PORTILLO_RUNTIME_BINS:-}"
  [[ ${#runtime_bins[@]} -gt 0 ]] || { error 'Runtime toolset not provided by remote.sh'; return 1; }
  for binary in "${runtime_bins[@]}"; do
    case "$binary" in
      nvim)    install_neovim ;;
      tmux)    install_tmux ;;
      rg)      install_ripgrep ;;
      fd)      install_fd ;;
      fzf)     install_fzf ;;
      lazygit) install_lazygit ;;
      node)    install_node ;;
      npm)     : ;;  # installed together with node
      stylua)  install_stylua ;;
      *) error "No installer for runtime tool: $binary"; return 1 ;;
    esac
  done

  # Both profiles use the same Tree-sitter plugins.
  install_zig_cc

  for binary in "${runtime_bins[@]}"; do
    [[ -x "$REMOTE_BIN/$binary" ]] || { error "Required remote binary missing: $binary"; return 1; }
    "$REMOTE_BIN/$binary" --version >/dev/null || { error "Remote binary cannot run: $binary"; return 1; }
  done

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

if [[ "${PORTILLO_INSTALLER_LIBRARY:-0}" != 1 ]]; then
  main "$@"
fi
