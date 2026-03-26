#!/usr/bin/env bash
set -euo pipefail

# === VARIABLES GLOBALES ===
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"
ARCH="$(uname -m)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

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
  echo ""
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
  brew update
}

# === PASO 3: INSTALL BREW PACKAGES ===
install_brew_packages() {
  info "Installing Homebrew packages..."
  
  local packages=(
    "git" "curl" "unzip" "tmux" "neovim" "ripgrep" "fd" "fzf" "bat"
    "lazygit" "lazydocker" "zsh" "tree-sitter" "zoxide" "atuin"
    "zsh-autosuggestions" "zsh-syntax-highlighting" "powerlevel10k"
    "starship" "go"
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
  
  local fonts_dir="$HOME/.local/share/fonts"
  mkdir -p "$fonts_dir"
  
  if fc-list | grep -q "Hack Nerd Font"; then
    ok "Hack Nerd Font already installed"
    return 0
  fi
  
  if [[ "$PLATFORM" == "mac" ]]; then
    info "Installing via Homebrew Cask (macOS)..."
    brew install --cask font-hack-nerd-font
  else
    info "Installing via direct download (Linux)..."
    local tmp_dir="/tmp/hack-font-$$"
    mkdir -p "$tmp_dir"
    
    cd "$tmp_dir"
    curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip
    unzip -o Hack.zip > /dev/null 2>&1
    cp *.ttf "$fonts_dir/" 2>/dev/null || true
    cd - > /dev/null
    rm -rf "$tmp_dir"
    
    if command -v fc-cache &> /dev/null; then
      fc-cache -fv > /dev/null 2>&1
    fi
  fi
  
  ok "Hack Nerd Font installed"
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
      info "Updating $plugin_name..."
      git -C "$plugin_path" pull -q
    else
      info "Installing $plugin_name..."
      git clone -q "$plugin_url" "$plugin_path"
    fi
  done
  
  # Setup powerlevel10k theme
  local theme_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  if [[ -d "$theme_dir" ]]; then
    info "Updating powerlevel10k..."
    git -C "$theme_dir" pull -q
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
    info "Updating TPM..."
    git -C "$tpm_dir" pull -q
  else
    info "Installing TPM..."
    git clone -q https://github.com/tmux-plugins/tpm "$tpm_dir"
  fi
}

# === PASO 7: INSTALL DEV TOOLS (INTERACTIVE) ===
install_dev_tools() {
  info "Dev Tools (optional)"
  echo ""
  
  # NVM
  if ask_yn "Install Node Version Manager (NVM)?" "y"; then
    if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
      info "Installing NVM..."
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash > /dev/null 2>&1
      ok "NVM installed"
    else
      ok "NVM already installed"
    fi
  fi
  
  # SDKMAN
  if ask_yn "Install SDKMAN (Java, Kotlin, Gradle)?" "y"; then
    if [[ ! -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
      info "Installing SDKMAN..."
      curl -s "https://get.sdkman.io" | bash > /dev/null 2>&1
      ok "SDKMAN installed"
    else
      ok "SDKMAN already installed"
    fi
  fi
  
  # Go (already in brew, confirm)
  if ask_yn "Confirm Go installation?" "y"; then
    if ! command -v go &> /dev/null; then
      info "Installing Go via Homebrew..."
      brew install go
    else
      ok "Go already installed"
    fi
  fi
  
  # uv
  if ask_yn "Install uv (Python package manager)?" "y"; then
    if [[ ! -f "$HOME/.local/bin/uv" ]]; then
      info "Installing uv..."
      mkdir -p "$HOME/.local/bin"
      curl -LsSf https://astral.sh/uv/install.sh | sh > /dev/null 2>&1
      ok "uv installed"
    else
      ok "uv already installed"
    fi
  fi
}

# === PASO 8: CREATE SYMLINKS ===
create_symlinks() {
  info "Creating symlinks..."
  
  local symlinks=(
    "tmux/tmux.conf:$HOME/.tmux.conf"
    "nvim:$HOME/.config/nvim"
    "alacritty/alacritty.toml:$HOME/.config/alacritty/alacritty.toml"
    "zsh/.zshrc:$HOME/.zshrc"
    "zsh/p10k.zsh:$HOME/.p10k.zsh"
    "starship.toml:$HOME/.config/starship.toml"
  )
  
  for symlink_spec in "${symlinks[@]}"; do
    local src_path="${symlink_spec%:*}"
    local dst_path="${symlink_spec#*:}"
    local src_full="$REPO_DIR/$src_path"
    
    # Create parent directory if needed
    mkdir -p "$(dirname "$dst_path")"
    
    # Handle existing symlinks or files
    if [[ -L "$dst_path" ]]; then
      # Already a symlink, update it
      ln -sf "$src_full" "$dst_path"
      ok "Updated symlink: $dst_path"
    elif [[ -e "$dst_path" ]]; then
      # Real file/dir exists, backup it
      backup "$dst_path"
      ln -s "$src_full" "$dst_path"
      ok "Created symlink: $dst_path"
    else
      # Doesn't exist, just create symlink
      ln -s "$src_full" "$dst_path"
      ok "Created symlink: $dst_path"
    fi
  done
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
  if fc-list | grep -q "Hack Nerd Font" 2>/dev/null; then
    ok "✓ Hack Nerd Font"
    ok_count=$((ok_count + 1))
  else
    error "✗ Hack Nerd Font"
  fi
  
  # Symlinks
  local symlinks_to_check=(
    "$HOME/.tmux.conf:$REPO_DIR/tmux/tmux.conf"
    "$HOME/.config/nvim:$REPO_DIR/nvim"
    "$HOME/.config/alacritty/alacritty.toml:$REPO_DIR/alacritty/alacritty.toml"
    "$HOME/.zshrc:$REPO_DIR/zsh/.zshrc"
    "$HOME/.p10k.zsh:$REPO_DIR/zsh/p10k.zsh"
    "$HOME/.config/starship.toml:$REPO_DIR/starship.toml"
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
  
  echo ""
  echo "Summary: $ok_count/$total checks passed"
  
  if [[ $ok_count -eq $total ]]; then
    ok "All checks passed!"
  else
    warn "Some checks failed. Review above."
  fi
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
}

main "$@"
