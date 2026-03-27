#!/usr/bin/env bash
set -uo pipefail

# === VARIABLES GLOBALES ===
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"
ARCH="$(uname -m)"
BACKUP_DIR="$REPO_DIR/.backup/$(date +%Y%m%d-%H%M%S)"
LOG="$HOME/.dotfiles-setup.log"

# === LOGGING ===
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

# Determinar PLATFORM
if [[ "$OS" == "Darwin" ]]; then
  PLATFORM="mac"
else
  PLATFORM="linux"
fi

# === COLORES Y HELPERS ===
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

banner() {
  echo -e "${BLUE}"
  echo "╔════════════════════════════════════════╗"
  echo "║     Portillo.Dots Setup Script         ║"
  echo "║              v1.0.0                    ║"
  echo "╚════════════════════════════════════════╝"
  echo -e "${NC}"
  echo "Platform: $PLATFORM"
  echo "Architecture: $ARCH"
  echo "Log file: $LOG"
  echo ""
  log "=== SETUP STARTED ==="
}

info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

error() {
  echo -e "${RED}✗${NC} $1"
}

ok() {
  echo -e "${GREEN}✓${NC} $1"
}

backup() {
  local src="$1"
  if [[ -e "$src" ]] && [[ ! -L "$src" ]]; then
    mkdir -p "$BACKUP_DIR"
    mv "$src" "$BACKUP_DIR/"
    ok "Backed up $(basename "$src") to $BACKUP_DIR"
  fi
}

ask_yn() {
  local prompt="$1"
  local default="${2:-y}"
  local response
  
  if [[ "$default" == "y" ]]; then
    read -p "$(echo -e ${YELLOW}?)${NC} $prompt [Y/n]: " -r response
    response="${response:-y}"
  else
    read -p "$(echo -e ${YELLOW}?)${NC} $prompt [y/N]: " -r response
    response="${response:-n}"
  fi
  
  [[ "$response" =~ ^[Yy]$ ]]
}

# === SAFE GIT UPDATE ===
safe_git_update() {
  local dir="$1"
  local name="$2"
  
  if [[ ! -d "$dir/.git" ]]; then
    warn "$name: not a git repository, skipping"
    return 0
  fi
  
  if ! git -C "$dir" diff-index --quiet HEAD -- 2>/dev/null; then
    warn "$name: local changes detected, skipping update"
    return 0
  fi
  
  if git -C "$dir" pull --ff-only --quiet 2>/dev/null; then
    ok "$name: updated"
  else
    warn "$name: update skipped (offline or conflict)"
  fi
}

# === PASO 1: OS DETECTION ===
detect_os() {
  info "Detecting OS..."
  echo "Platform: $PLATFORM, Architecture: $ARCH"
}

# === PASO 2: SETUP BREW ===
setup_brew() {
  info "Setting up Homebrew..."
  
  if ! command -v brew &> /dev/null; then
    warn "Homebrew not found. Installing..."
    if [[ "$PLATFORM" == "mac" ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
  else
    ok "Homebrew already installed"
  fi
  
  # Source brew shellenv
  if [[ "$PLATFORM" == "mac" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
  
  info "Running brew update..."
  brew update >>"$LOG" 2>&1 || warn "brew update failed, continuing..."
}

# === PASO 3: INSTALL BREW PACKAGES ===
install_brew_packages() {
  info "Installing Homebrew packages..."
  
  local packages=(
    "git" "curl" "unzip" "tmux" "neovim" "ripgrep" "fd" "fzf" "bat"
    "lazygit" "lazydocker" "zsh" "tree-sitter" "zoxide" "atuin"
    "go"
  )
  
  for pkg in "${packages[@]}"; do
    if brew list "$pkg" &> /dev/null; then
      ok "$pkg already installed"
    else
      info "Installing $pkg..."
      brew install "$pkg"
    fi
  done
}

# === PASO 4: INSTALL FONTS ===
install_fonts() {
  info "Installing Hack Nerd Font..."
  
  # Check if already installed (platform-specific)
  if [[ "$PLATFORM" == "mac" ]]; then
    # macOS: check if brew cask is installed
    if brew list --cask 2>/dev/null | grep -q "font-hack-nerd-font"; then
      ok "Hack Nerd Font already installed"
      return 0
    fi
  else
    # Linux: check with fc-list
    if fc-list 2>/dev/null | grep -q "Hack Nerd Font"; then
      ok "Hack Nerd Font already installed"
      return 0
    fi
  fi
  
  # Install
  if [[ "$PLATFORM" == "mac" ]]; then
    info "Installing via Homebrew Cask (macOS)..."
    if brew install --cask font-hack-nerd-font >>"$LOG" 2>&1; then
      ok "Hack Nerd Font installed"
    else
      warn "Font installation failed, continuing..."
    fi
  else
    info "Installing via direct download (Linux)..."
    local fonts_dir="$HOME/.local/share/fonts"
    local tmp_dir="/tmp/hack-font-$$"
    mkdir -p "$fonts_dir" "$tmp_dir"
    
    cd "$tmp_dir"
    if curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip 2>>"$LOG"; then
      unzip -o Hack.zip -d "$tmp_dir" >>"$LOG" 2>&1 || true
      cp "$tmp_dir"/*.ttf "$fonts_dir/" 2>/dev/null || true
      
      if command -v fc-cache &> /dev/null; then
        fc-cache -fv >>"$LOG" 2>&1 || true
      fi
      ok "Hack Nerd Font installed"
    else
      warn "Font download failed, continuing..."
    fi
    cd - > /dev/null
    rm -rf "$tmp_dir" 2>/dev/null || true
  fi
}

# === PASO 5: SETUP OH MY ZSH ===
setup_oh_my_zsh() {
  info "Setting up Oh My Zsh..."
  
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    warn "Oh My Zsh not found. Installing..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  else
    ok "Oh My Zsh already installed"
  fi
  
  # Setup custom plugins
  local custom_plugins_dir="$HOME/.oh-my-zsh/custom/plugins"
  mkdir -p "$custom_plugins_dir"
  
  local plugins=(
    "zsh-autosuggestions:https://github.com/zsh-users/zsh-autosuggestions.git"
    "zsh-syntax-highlighting:https://github.com/zsh-users/zsh-syntax-highlighting.git"
    "you-should-use:https://github.com/MichaelAquilina/zsh-you-should-use.git"
  )
  
  for plugin_spec in "${plugins[@]}"; do
    local plugin_name="${plugin_spec%:*}"
    local plugin_url="${plugin_spec#*:}"
    local plugin_path="$custom_plugins_dir/$plugin_name"
    
    if [[ -d "$plugin_path" ]]; then
      safe_git_update "$plugin_path" "$plugin_name"
    else
      info "Installing $plugin_name..."
      git clone -q "$plugin_url" "$plugin_path"
    fi
  done
  
  # Setup powerlevel10k theme
  local theme_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  if [[ -d "$theme_dir" ]]; then
    safe_git_update "$theme_dir" "powerlevel10k"
  else
    info "Installing powerlevel10k..."
    git clone -q https://github.com/romkatv/powerlevel10k.git "$theme_dir"
  fi
}

# === PASO 6: SETUP TPM ===
setup_tpm() {
  info "Setting up Tmux Plugin Manager (TPM)..."
  
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  
  if [[ -d "$tpm_dir" ]]; then
    safe_git_update "$tpm_dir" "TPM"
  else
    info "Installing TPM..."
    git clone -q https://github.com/tmux-plugins/tpm "$tpm_dir"
  fi
}

# === PASO 7: INSTALL DEV TOOLS (IDEMPOTENT) ===
install_dev_tools() {
  info "Dev Tools (optional)"
  echo ""
  
  # NVM
  if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    ok "NVM already installed"
  else
    if ask_yn "Install Node Version Manager (NVM)?" "y"; then
      info "Installing NVM..."
      if curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh 2>>"$LOG" | bash >>"$LOG" 2>&1; then
        ok "NVM installed"
      else
        warn "NVM installation failed, continuing..."
      fi
    fi
  fi
  
  # SDKMAN
  if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
    ok "SDKMAN already installed"
  else
    if ask_yn "Install SDKMAN (Java, Kotlin, Gradle)?" "y"; then
      info "Installing SDKMAN..."
      if curl -s "https://get.sdkman.io" 2>>"$LOG" | bash >>"$LOG" 2>&1; then
        ok "SDKMAN installed"
      else
        warn "SDKMAN installation failed, continuing..."
      fi
    fi
  fi
  
  # Go
  if command -v go &> /dev/null; then
    ok "Go already installed"
  else
    if ask_yn "Install Go?" "y"; then
      info "Installing Go via Homebrew..."
      if brew install go >>"$LOG" 2>&1; then
        ok "Go installed"
      else
        warn "Go installation failed, continuing..."
      fi
    fi
  fi
  
  # uv
  if [[ -f "$HOME/.local/bin/uv" ]]; then
    ok "uv already installed"
  else
    if ask_yn "Install uv (Python package manager)?" "y"; then
      info "Installing uv..."
      mkdir -p "$HOME/.local/bin"
      if curl -LsSf https://astral.sh/uv/install.sh 2>>"$LOG" | sh >>"$LOG" 2>&1; then
        ok "uv installed"
      else
        warn "uv installation failed, continuing..."
      fi
    fi
  fi
}

create_nvim_symlinks() {
  info "Setting up nvim config (directory + internal symlinks)..."
  
  local nvim_config="$HOME/.config/nvim"
  local nvim_repo="$REPO_DIR/nvim"
  
  if [[ -L "$nvim_config" ]]; then
    rm "$nvim_config"
    ok "Removed old nvim directory symlink"
  fi
  
  mkdir -p "$nvim_config"
  
  local nvim_links=(
    "init.lua"
    "lua"
    "lazy-lock.json"
    "lazyvim.json"
    "stylua.toml"
    ".gitignore"
    ".neoconf.json"
  )
  
  for item in "${nvim_links[@]}"; do
    local src="$nvim_repo/$item"
    local dst="$nvim_config/$item"
    
    if [[ ! -e "$src" ]]; then
      continue
    fi
    
    if [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]]; then
      ok "nvim/$item already linked"
      continue
    fi
    
    if [[ -e "$dst" ]] && [[ ! -L "$dst" ]]; then
      backup "$dst"
    fi
    
    ln -sf "$src" "$dst"
    ok "Linked nvim/$item"
  done
}

# === PASO 8: CREATE SYMLINKS ===
create_symlinks() {
  info "Creating symlinks..."
  
  local symlinks=(
    "tmux/tmux.conf:$HOME/.tmux.conf"
    "alacritty/alacritty.toml:$HOME/.config/alacritty/alacritty.toml"
    "zsh/.zshrc:$HOME/.zshrc"
    "zsh/p10k.zsh:$HOME/.p10k.zsh"
  )
  
  for symlink_spec in "${symlinks[@]}"; do
    local src_path="${symlink_spec%:*}"
    local dst_path="${symlink_spec#*:}"
    local src_full="$REPO_DIR/$src_path"
    
    mkdir -p "$(dirname "$dst_path")"
    
    if [[ -L "$dst_path" ]]; then
      ln -sf "$src_full" "$dst_path"
      ok "Updated symlink: $dst_path"
    elif [[ -e "$dst_path" ]]; then
      backup "$dst_path"
      ln -s "$src_full" "$dst_path"
      ok "Created symlink: $dst_path"
    else
      ln -s "$src_full" "$dst_path"
      ok "Created symlink: $dst_path"
    fi
  done
  
  create_nvim_symlinks
}

# === PASO 9: INSTALL TMUX PLUGINS ===
install_tmux_plugins() {
  info "Installing Tmux plugins..."
  
  if [[ -f "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]]; then
    "$HOME/.tmux/plugins/tpm/bin/install_plugins"
    ok "Tmux plugins installed"
  else
    warn "TPM not found, skipping tmux plugin installation"
  fi
}

# === PASO 10: VERIFY INSTALLATION ===
verify() {
  info "Verification"
  echo ""
  
  local total=0
  local ok_count=0
  
  # Binarios
  local binaries=(
    "nvim" "tmux" "git" "brew" "fzf" "rg" "fd" "bat" "lazygit" "lazydocker"
  )
  
  if [[ "$PLATFORM" == "linux" ]]; then
    binaries+=("xclip")
  fi
  
  for bin in "${binaries[@]}"; do
    total=$((total + 1))
    if command -v "$bin" &> /dev/null; then
      ok "✓ $bin"
      ok_count=$((ok_count + 1))
    else
      error "✗ $bin"
    fi
  done
  
  # Oh My Zsh
  total=$((total + 1))
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    ok "✓ Oh My Zsh"
    ok_count=$((ok_count + 1))
  else
    error "✗ Oh My Zsh"
  fi
  
  # OMZ Plugins
  for plugin in "zsh-autosuggestions" "zsh-syntax-highlighting" "you-should-use"; do
    total=$((total + 1))
    if [[ -d "$HOME/.oh-my-zsh/custom/plugins/$plugin" ]]; then
      ok "✓ $plugin"
      ok_count=$((ok_count + 1))
    else
      error "✗ $plugin"
    fi
  done
  
  # powerlevel10k
  total=$((total + 1))
  if [[ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
    ok "✓ powerlevel10k"
    ok_count=$((ok_count + 1))
  else
    error "✗ powerlevel10k"
  fi
  
  # TPM
  total=$((total + 1))
  if [[ -d "$HOME/.tmux/plugins/tpm" ]]; then
    ok "✓ TPM"
    ok_count=$((ok_count + 1))
  else
    error "✗ TPM"
  fi
  
  # Fonts
  total=$((total + 1))
  # Temporarily disable pipefail for fc-list (SIGPIPE with grep -q)
  set +o pipefail
  if fc-list 2>&1 | grep -q "Hack Nerd Font"; then
    set -o pipefail
    ok "✓ Hack Nerd Font"
    ok_count=$((ok_count + 1))
  else
    set -o pipefail
    error "✗ Hack Nerd Font"
  fi
  
  # Symlinks (standard)
  local symlinks_to_check=(
    "$HOME/.tmux.conf:$REPO_DIR/tmux/tmux.conf"
    "$HOME/.config/alacritty/alacritty.toml:$REPO_DIR/alacritty/alacritty.toml"
    "$HOME/.zshrc:$REPO_DIR/zsh/.zshrc"
    "$HOME/.p10k.zsh:$REPO_DIR/zsh/p10k.zsh"
  )
  
  for symlink_check in "${symlinks_to_check[@]}"; do
    local target="${symlink_check%:*}"
    local expected="${symlink_check#*:}"
    total=$((total + 1))
    
    if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$expected" ]]; then
      ok "✓ $(basename "$target") symlink"
      ok_count=$((ok_count + 1))
    else
      error "✗ $(basename "$target") symlink"
    fi
  done
  
  # Nvim: verify real directory + internal symlinks
  total=$((total + 1))
  if [[ -d "$HOME/.config/nvim" ]] && [[ ! -L "$HOME/.config/nvim" ]]; then
    ok "✓ nvim config directory (real)"
    ok_count=$((ok_count + 1))
  else
    error "✗ nvim config directory (expected real dir, got symlink or missing)"
  fi
  
  local nvim_check_links=("init.lua" "lua" "lazy-lock.json" "stylua.toml" ".gitignore")
  for item in "${nvim_check_links[@]}"; do
    local nvim_target="$HOME/.config/nvim/$item"
    local nvim_expected="$REPO_DIR/nvim/$item"
    total=$((total + 1))
    
    if [[ -L "$nvim_target" ]] && [[ "$(readlink "$nvim_target")" == "$nvim_expected" ]]; then
      ok "✓ nvim/$item symlink"
      ok_count=$((ok_count + 1))
    else
      error "✗ nvim/$item symlink"
    fi
  done
  
  echo ""
  echo "Summary: $ok_count/$total checks passed"
  
  if [[ $ok_count -eq $total ]]; then
    ok "All checks passed!"
  else
    warn "Some checks failed. Review above."
  fi
  
  # Never return error from verify
  log "VERIFY: $ok_count/$total checks passed"
  return 0
}

# === MAIN ===
main() {
  banner
  
  detect_os
  echo ""
  
  setup_brew
  echo ""
  
  install_brew_packages
  echo ""
  
  install_fonts
  echo ""
  
  setup_oh_my_zsh
  echo ""
  
  setup_tpm
  echo ""
  
  install_dev_tools
  echo ""
  
  create_symlinks
  echo ""
  
  install_tmux_plugins
  echo ""
  
  verify
  echo ""
  
  echo "Done! Open a new terminal or run: exec zsh"
  echo "Log file: $LOG"
  log "=== SETUP COMPLETED ==="
}

main "$@"
