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
  symlink_if_exists "nvim" && return 0

  if [[ -f "$DL_DIR/nvim.appimage" ]]; then
    chmod +x "$DL_DIR/nvim.appimage"
    mv "$DL_DIR/nvim.appimage" "$REMOTE_BIN/nvim"
    if ! "$REMOTE_BIN/nvim" --version &>/dev/null; then
      info "AppImage needs extraction..."
      "$REMOTE_BIN/nvim" --appimage-extract &>/dev/null
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
    ok "tmux installed"
  elif [[ -f "$DL_DIR/tmux.tar.gz" ]]; then
    tar xzf "$DL_DIR/tmux.tar.gz" -C "$DL_DIR"
    local binary
    binary="$(find "$DL_DIR" -type f -name "tmux" ! -path "$DL_DIR/tmux.tar.gz" | head -1)"
    if [[ -n "$binary" ]]; then
      chmod +x "$binary"
      mv "$binary" "$REMOTE_BIN/tmux"
    fi
    ok "tmux installed"
  elif [[ -x "$REMOTE_BIN/tmux" ]]; then
    ok "tmux (already installed)"
  else
    warn "tmux: no binary provided"
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

setup_lazy_nvim() {
  info "Pre-installing lazy.nvim..."
  local lazy_dir="$REMOTE_NVIM_SHARE/lazy/lazy.nvim"
  if [[ -d "$lazy_dir" ]]; then
    git -C "$lazy_dir" pull --ff-only 2>/dev/null
    ok "lazy.nvim up to date"
    return 0
  fi
  mkdir -p "$(dirname "$lazy_dir")"
  git clone --filter=blob:none https://github.com/folke/lazy.nvim.git "$lazy_dir" 2>/dev/null
  ok "lazy.nvim cloned"
}

setup_nvim_config_symlink() {
  local nvim_app_dir="$HOME/.config/portillo-remote/nvim"
  if [[ -L "$nvim_app_dir" ]] || [[ -d "$nvim_app_dir" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$nvim_app_dir")"
  ln -sf "$REMOTE_BASE/nvim" "$nvim_app_dir"
  ok "nvim config symlink created"
}

setup_tpm() {
  info "Installing TPM..."
  local tpm_dir="$REMOTE_BASE/tmux/plugins/tpm"
  if [[ -d "$tpm_dir" ]]; then
    ok "TPM already present"
    return 0
  fi
  mkdir -p "$(dirname "$tpm_dir")"
  git clone --depth 1 https://github.com/tmux-plugins/tpm.git "$tpm_dir" 2>/dev/null
  ok "TPM installed"
}

generate_tmux_remote_conf() {
  info "Generating tmux-remote.conf..."
  local src="$REMOTE_BASE/tmux/tmux.conf"
  local dst="$REMOTE_BASE/tmux-remote.conf"

  if [[ ! -f "$src" ]]; then
    warn "No tmux.conf found, skipping"
    return 0
  fi

  sed \
    -e "s|run '~/.tmux/plugins/tpm/tpm'|run '$REMOTE_BASE/tmux/plugins/tpm/tpm'|" \
    "$src" > "$dst"

  ok "tmux-remote.conf generated"
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

  echo ""
  info "Post-install setup..."
  setup_lazy_nvim
  setup_nvim_config_symlink
  setup_tpm
  generate_tmux_remote_conf

  echo ""
  ok "All binaries installed"
  info "Binaries in: $REMOTE_BIN"
  ls -la "$REMOTE_BIN"
}

main "$@"
