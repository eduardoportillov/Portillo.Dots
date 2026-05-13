#!/usr/bin/env bash
set -uo pipefail

# === VARIABLES GLOBALES ===
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"
ARCH="$(uname -m)"
BACKUP_DIR="$REPO_DIR/.backup/$(date +%Y%m%d-%H%M%S)"
LOG="$REPO_DIR/logs/setup.log"
AUTO_YES=true
APT_UPDATED=false
mkdir -p "$REPO_DIR/logs"

# === ARG PARSING ===
for arg in "$@"; do
  case "$arg" in
    -y|--yes) AUTO_YES=true ;;
    -i|--interactive) AUTO_YES=false ;;
  esac
done

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

  if [[ "$AUTO_YES" == true ]]; then
    echo -e "$(echo -e "${YELLOW}?${NC}") $prompt [Y/n]: y (auto)"
    return 0
  fi
  
  if [[ "$default" == "y" ]]; then
    read -rp "$(echo -e "${YELLOW}?${NC}") $prompt [Y/n]: " response
    response="${response:-y}"
  else
    read -rp "$(echo -e "${YELLOW}?${NC}") $prompt [y/N]: " response
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

# === DETECT SYSTEM PACKAGE MANAGER ===
detect_pkg_manager() {
  if [[ "$PLATFORM" == "mac" ]]; then
    echo "brew"
  elif command -v apt-get &> /dev/null; then
    echo "apt"
  elif command -v pacman &> /dev/null; then
    echo "pacman"
  elif command -v yum &> /dev/null; then
    echo "yum"
  elif command -v dnf &> /dev/null; then
    echo "dnf"
  elif command -v zypper &> /dev/null; then
    echo "zypper"
  elif command -v apk &> /dev/null; then
    echo "apk"
  else
    echo ""
  fi
}

# === INSTALL SYSTEM PACKAGES ===
install_system_packages() {
  local pkg_manager="$1"
  shift
  local packages=("$@")
  
  case "$pkg_manager" in
    apt)
      if [[ "$APT_UPDATED" != true ]]; then
        sudo apt-get update -qq >>"$LOG" 2>&1
        APT_UPDATED=true
      fi
      for pkg in "${packages[@]}"; do
        info "Installing $pkg..."
        sudo apt-get install -y "$pkg" >>"$LOG" 2>&1 && ok "$pkg installed" || warn "Failed to install $pkg"
      done
      ;;
    pacman)
      for pkg in "${packages[@]}"; do
        info "Installing $pkg..."
        sudo pacman -S --noconfirm "$pkg" >>"$LOG" 2>&1 && ok "$pkg installed" || warn "Failed to install $pkg"
      done
      ;;
    yum|dnf)
      for pkg in "${packages[@]}"; do
        info "Installing $pkg..."
        sudo "$pkg_manager" install -y "$pkg" >>"$LOG" 2>&1 && ok "$pkg installed" || warn "Failed to install $pkg"
      done
      ;;
    zypper)
      for pkg in "${packages[@]}"; do
        info "Installing $pkg..."
        sudo zypper -n install "$pkg" >>"$LOG" 2>&1 && ok "$pkg installed" || warn "Failed to install $pkg"
      done
      ;;
    apk)
      for pkg in "${packages[@]}"; do
        info "Installing $pkg..."
        sudo apk add "$pkg" >>"$LOG" 2>&1 && ok "$pkg installed" || warn "Failed to install $pkg"
      done
      ;;
    *)
      warn "Unknown package manager, skipping installation"
      return 1
      ;;
  esac
}

# === PASO 2: SETUP BREW ===
setup_brew() {
  info "Setting up Homebrew..."
  
  if command -v brew &> /dev/null; then
    ok "Homebrew already installed"
    if [[ "$PLATFORM" == "mac" ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true
    fi
    return 0
  fi
  
  # For Linux, try to install system basics first
  if [[ "$PLATFORM" == "linux" ]]; then
    local pkg_manager="$(detect_pkg_manager)"
    if [[ -n "$pkg_manager" ]]; then
      info "Installing essential system packages first ($pkg_manager)..."
      install_system_packages "$pkg_manager" "git" "curl" "unzip" "sudo" "build-essential"
    fi
  fi
  
  # Try Homebrew installation
  info "Homebrew not found. Installing..."
  if [[ "$PLATFORM" == "mac" ]]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>>"$LOG" || true
  fi
  
  # Try to source brew
  if [[ "$PLATFORM" == "mac" ]] && [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    ok "Homebrew initialized (macOS)"
  elif [[ -f $HOME/.linuxbrew/bin/brew ]]; then
    eval "$($HOME/.linuxbrew/bin/brew shellenv)"
    ok "Homebrew initialized (Linux - user install)"
  elif [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    ok "Homebrew initialized (Linux - system install)"
  else
    warn "Homebrew installation failed or not available"
  fi

  # Agregar brew shellenv al .bashrc para que también funcione en sesiones bash
  if [[ "$PLATFORM" == "linux" ]] && command -v brew &>/dev/null; then
    local brew_line='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"'
    if ! grep -qF 'linuxbrew' "$HOME/.bashrc" 2>/dev/null; then
      echo >> "$HOME/.bashrc"
      echo "# Homebrew" >> "$HOME/.bashrc"
      echo "$brew_line" >> "$HOME/.bashrc"
    fi
  fi

  if command -v brew &> /dev/null; then
    info "Running brew update..."
    brew update >>"$LOG" 2>&1 || warn "brew update failed, continuing..."
  fi
}

# === PASO 3: INSTALL BREW PACKAGES ===
install_brew_packages() {
  info "Installing packages..."
  
  local packages=(
    "git" "curl" "unzip" "zip" "tmux" "neovim" "ripgrep" "fd" "fzf" "bat"
    "lazygit" "lazydocker" "zsh" "tree-sitter" "zoxide" "atuin" "go"
  )

  # Linux-only packages
  if [[ "$PLATFORM" == "linux" ]]; then
    packages+=("xclip")
  fi

  # If brew is available, use it
  if command -v brew &> /dev/null; then
    for pkg in "${packages[@]}"; do
      if brew list "$pkg" &> /dev/null; then
        ok "$pkg already installed"
      else
        info "Installing $pkg with brew..."
        brew install "$pkg" >>"$LOG" 2>&1 || warn "Failed to install $pkg with brew"
      fi
    done
  else
    # Fallback to system package manager
    local pkg_manager="$(detect_pkg_manager)"
    if [[ -n "$pkg_manager" ]]; then
      info "Brew not available, using system package manager ($pkg_manager)..."
      
      # Map package names for different package managers
      local pkg_list=()
      for pkg in "${packages[@]}"; do
        # Some packages have different names in different package managers
        case "$pkg" in
          lazygit|lazydocker|atuin|fzf|bat|ripgrep|fd|zoxide|tree-sitter|zsh|tmux|git|curl|unzip|neovim|go)
            pkg_list+=("$pkg") ;;
          *)
            pkg_list+=("$pkg") ;;
        esac
      done
      
      install_system_packages "$pkg_manager" "${pkg_list[@]}"
    else
      error "No package manager found and brew is not available. Please install packages manually."
      return 1
    fi
  fi
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
    if command -v brew &> /dev/null; then
      if brew install --cask font-hack-nerd-font >>"$LOG" 2>&1; then
        ok "Hack Nerd Font installed"
      else
        warn "Font installation failed, continuing..."
      fi
    else
      warn "Homebrew not available, skipping font installation"
    fi
  else
    info "Installing via direct download (Linux)..."
    local fonts_dir="$HOME/.local/share/fonts"
    local tmp_dir="/tmp/hack-font-$$"
    mkdir -p "$fonts_dir" "$tmp_dir"
    
    cd "$tmp_dir"
    
    # Check if unzip is available, if not try to install it
    if ! command -v unzip &> /dev/null; then
      warn "unzip not found, attempting to install..."
      local pkg_manager="$(detect_pkg_manager)"
      if [[ -n "$pkg_manager" ]]; then
        install_system_packages "$pkg_manager" "unzip"
      fi
      
      # Check again
      if ! command -v unzip &> /dev/null; then
        warn "unzip still not available, trying alternative extraction..."
        # Try bsdtar or 7z or tar
        if command -v bsdtar &> /dev/null; then
          if curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip 2>>"$LOG"; then
            bsdtar -xf Hack.zip -C "$tmp_dir" >>"$LOG" 2>&1 || true
            cp "$tmp_dir"/*.ttf "$fonts_dir/" 2>/dev/null || true
          fi
        elif command -v 7z &> /dev/null; then
          if curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip 2>>"$LOG"; then
            7z x Hack.zip -o"$tmp_dir" >>"$LOG" 2>&1 || true
            cp "$tmp_dir"/*.ttf "$fonts_dir/" 2>/dev/null || true
          fi
        else
          warn "No extraction tool available (unzip, bsdtar, 7z), skipping font installation"
        fi
        cd - > /dev/null
        rm -rf "$tmp_dir" 2>/dev/null || true
        return 1
      fi
    fi
    
    # Now unzip should be available
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
    info "Oh My Zsh not found. Installing..."
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
    local plugin_name="${plugin_spec%%:*}"
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

# === PASO 7A: SETUP OPENCODE ===
setup_opencode() {
  info "Setting up OpenCode..."
  
  local opencode_config_dir="$HOME/.config/opencode"
  local opencode_config_file="$opencode_config_dir/config.jsonc"
  local template_file="$REPO_DIR/opencode/opencode.template.jsonc"
  local env_file="$REPO_DIR/opencode/.env"
  local generated_config="$REPO_DIR/opencode/opencode.jsonc"
  local regenerate_script="$REPO_DIR/opencode/regenerate-config.sh"
  
  # Check template exists
  if [[ ! -f "$template_file" ]]; then
    warn "OpenCode template not found at $template_file, skipping"
    return 1
  fi
  
  # Make regenerate script executable
  if [[ -f "$regenerate_script" ]]; then
    chmod +x "$regenerate_script"
  fi
  
  # If .env doesn't exist but .env.example does, copy it so the user has a starting point
  if [[ ! -f "$env_file" ]] && [[ -f "${env_file}.example" ]]; then
    cp "${env_file}.example" "$env_file"
    info "Copied .env.example → .env (fill in your API keys)"
  fi

  # Generate opencode.jsonc from template using .env as source of truth
  if [[ -f "$env_file" ]]; then
    info "Generating opencode.jsonc from template with .env variables..."
    
    # Read template
    local config_content="$(<"$template_file")"
    
    # Replace ALL variables from .env dynamically
    local var_count=0
    while IFS='=' read -r key value; do
      # Skip empty lines and comments
      [[ -z "$key" ]] && continue
      [[ "$key" =~ ^#.* ]] && continue
      
      # Trim whitespace
      key="$(echo "$key" | xargs)"
      value="$(echo "$value" | xargs)"
      
      # Replace {{VARIABLE}} with the value
      config_content="${config_content//\{\{$key\}\}/$value}"
      var_count=$((var_count + 1))
    done < "$env_file"
    
    # Write generated config to repo
    echo "$config_content" > "$generated_config"
    ok "Generated opencode.jsonc with $var_count variables"
  else
    warn "OpenCode .env not found, using template as-is"
    cp "$template_file" "$generated_config"
  fi
  
  # Create symlink from ~/.config/opencode/config.jsonc to generated opencode.jsonc
  mkdir -p "$opencode_config_dir"
  
  if [[ -L "$opencode_config_file" ]] && [[ "$(readlink "$opencode_config_file")" == "$generated_config" ]]; then
    ok "OpenCode config symlink already correct"
  elif [[ -e "$opencode_config_file" ]] && [[ ! -L "$opencode_config_file" ]]; then
    backup "$opencode_config_file"
    ln -sf "$generated_config" "$opencode_config_file"
    ok "Created symlink for OpenCode config"
  else
    ln -sf "$generated_config" "$opencode_config_file"
    ok "Created symlink for OpenCode config"
  fi
  
  # Install OpenCode via brew (preferred) — do NOT rely on command -v opencode
  # since it may find a Windows-mounted binary (e.g., /mnt/c/...) that won't work on Linux
  if command -v brew &> /dev/null; then
    if brew list opencode &>/dev/null 2>&1; then
      ok "OpenCode already installed (brew)"
    else
      info "Installing OpenCode via brew (sst/tap)..."
      brew install sst/tap/opencode >>"$LOG" 2>&1 && ok "OpenCode installed" || warn "Failed to install OpenCode via brew"
    fi
  elif ! command -v opencode &> /dev/null; then
    if command -v npm &> /dev/null; then
      info "Installing OpenCode via npm..."
      npm install -g opencode >>"$LOG" 2>&1 && ok "OpenCode installed" || warn "Failed to install OpenCode via npm"
    else
      warn "Neither brew nor npm found, skipping OpenCode installation"
    fi
  else
    ok "OpenCode already installed"
  fi
}

# === PASO 7: INSTALL DEV TOOLS (IDEMPOTENT) ===
install_dev_tools() {
  info "Dev Tools"
  echo ""
  
  # fnm (Fast Node Manager)
  if command -v fnm &> /dev/null || [[ -f "$HOME/.local/share/fnm/fnm" ]] || [[ -f "$HOME/.fnm/fnm" ]]; then
    ok "fnm already installed"
  else
    if ask_yn "Install fnm (Fast Node Manager for Node.js)?" "y"; then
      info "Installing fnm..."
      if curl -fsSL https://raw.githubusercontent.com/Schniz/fnm/master/.ci/install.sh 2>>"$LOG" | bash >>"$LOG" 2>&1; then
        ok "fnm installed"
        # Install Node.js 22 LTS as default
        local fnm_bin="$HOME/.local/share/fnm/fnm"
        [[ ! -f "$fnm_bin" ]] && fnm_bin="$HOME/.fnm/fnm"
        if [[ -f "$fnm_bin" ]]; then
          info "Installing Node.js 22 LTS (default)..."
          eval "$("$fnm_bin" env --shell bash)" 2>/dev/null
          "$fnm_bin" install 22 >>"$LOG" 2>&1 && "$fnm_bin" default 22 >>"$LOG" 2>&1 && ok "Node.js 22 set as default" || warn "Node.js 22 install failed, set manually with: fnm install 22 && fnm default 22"
        fi
      else
        warn "fnm installation failed, continuing..."
      fi
    fi
  fi
  
  # SDKMAN
  if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
    ok "SDKMAN already installed"
  else
    if ask_yn "Install SDKMAN (Java, Kotlin, Gradle)?" "y"; then
      info "Installing SDKMAN..."
      # SDKMAN needs unzip and zip, ensure both are available
      local pkg_manager_sdk="$(detect_pkg_manager)"
      if ! command -v unzip &> /dev/null || ! command -v zip &> /dev/null; then
        warn "unzip/zip required for SDKMAN, attempting to install..."
        if [[ -n "$pkg_manager_sdk" ]] && [[ "$pkg_manager_sdk" != "brew" ]]; then
          install_system_packages "$pkg_manager_sdk" "unzip" "zip"
        elif command -v brew &> /dev/null; then
          brew install unzip zip >>"$LOG" 2>&1 || true
        fi
      fi
      
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
      if command -v brew &> /dev/null; then
        info "Installing Go via Homebrew..."
        if brew install go >>"$LOG" 2>&1; then
          ok "Go installed"
        else
          warn "Go installation failed, continuing..."
        fi
      else
        # Try system package manager
        local pkg_manager="$(detect_pkg_manager)"
        if [[ -n "$pkg_manager" ]]; then
          info "Installing Go via $pkg_manager..."
          if install_system_packages "$pkg_manager" "golang-go" 2>/dev/null; then
            ok "Go installed"
          else
            warn "Go installation failed, continuing..."
          fi
        else
          warn "Homebrew and system package manager not available for Go installation"
        fi
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

  # copyq
  if command -v copyq &> /dev/null; then
    ok "copyq already installed"
  else
    if ask_yn "Install CopyQ (clipboard manager)?" "y"; then
      info "Installing copyq..."
      if [[ "$PLATFORM" == "mac" ]]; then
        if brew install --cask copyq >>"$LOG" 2>&1; then
          ok "copyq installed"
        else
          warn "copyq installation failed, continuing..."
        fi
      else
        # On Linux: copyq is a macOS-only brew cask; install via apt with the hluk PPA
        local pm_copyq="$(detect_pkg_manager)"
        if [[ "$pm_copyq" == "apt" ]]; then
          # Ensure add-apt-repository is available
          if ! command -v add-apt-repository &>/dev/null; then
            sudo apt-get install -y software-properties-common >>"$LOG" 2>&1 || true
          fi
          if sudo add-apt-repository -y ppa:hluk/copyq >>"$LOG" 2>&1; then
            sudo apt-get update -qq >>"$LOG" 2>&1
            sudo apt-get install -y copyq >>"$LOG" 2>&1 && ok "copyq installed" || warn "copyq installation failed, continuing..."
          else
            # PPA failed, try direct from apt (may exist in universe)
            sudo apt-get install -y copyq >>"$LOG" 2>&1 && ok "copyq installed" || warn "copyq not available in apt, skipping"
          fi
        elif [[ -n "$pm_copyq" ]]; then
          install_system_packages "$pm_copyq" "copyq"
        else
          warn "No supported package manager for copyq on Linux, skipping"
        fi
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
    "db_ui"
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

# === PASO 9: CONFIGURE DEFAULT SHELL (ZSH) ===
configure_default_shell() {
  info "Configuring default shell..."
  
  local current_shell="$SHELL"
  local zsh_path
  
  # Find zsh path
  if command -v zsh &> /dev/null; then
    zsh_path="$(command -v zsh)"
  else
    error "zsh not found, skipping shell configuration"
    return 1
  fi
  
  # Check if current shell is zsh already
  if [[ "$current_shell" == *"zsh"* ]]; then
    ok "Already using zsh: $current_shell"
    return 0
  fi
  
  info "Current shell is: $current_shell"
  info "Attempting to set default shell to zsh: $zsh_path"
  
  # Ensure zsh is listed in /etc/shells (required for chsh)
  if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    info "Adding $zsh_path to /etc/shells..."
    if echo "$zsh_path" | sudo tee -a /etc/shells >>"$LOG" 2>&1; then
      ok "Added $zsh_path to /etc/shells"
    else
      warn "Could not add zsh to /etc/shells (may need sudo)"
    fi
  fi
  
  # Try chsh with sudo first (avoids PAM issues in scripts)
  if sudo chsh -s "$zsh_path" "$USER" >>"$LOG" 2>&1; then
    ok "Default shell changed to zsh (run 'exec zsh' or open a new terminal)"
  elif chsh -s "$zsh_path" >>"$LOG" 2>&1; then
    ok "Default shell changed to zsh (run 'exec zsh' or open a new terminal)"
  else
    warn "Could not change shell automatically."
    warn "To set zsh manually, run: chsh -s $zsh_path"
    warn "Or add to your .bashrc: exec zsh"
  fi
}

# === PASO 10: INSTALL TMUX PLUGINS ===
install_tmux_plugins() {
  info "Installing Tmux plugins..."
  
  if [[ -f "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]]; then
    "$HOME/.tmux/plugins/tpm/bin/install_plugins"
    ok "Tmux plugins installed"
  else
    warn "TPM not found, skipping tmux plugin installation"
  fi
}

# === PASO 11: VERIFY INSTALLATION ===
verify() {
  info "Verification"
  echo ""
  
  local total=0
  local ok_count=0
  
  # Binarios
  local binaries=(
    "nvim" "tmux" "git" "brew" "fzf" "rg" "fd" "bat" "lazygit" "lazydocker" "opencode"
  )
  
  if [[ "$PLATFORM" == "linux" ]]; then
    binaries+=("xclip" "copyq")
  else
    binaries+=("copyq")
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

  # OpenCode
  total=$((total + 1))
  local opencode_generated="$REPO_DIR/opencode/opencode.jsonc"
  local opencode_config="$HOME/.config/opencode/config.jsonc"
  if [[ -f "$opencode_generated" ]] && [[ -L "$opencode_config" ]] && [[ "$(readlink "$opencode_config")" == "$opencode_generated" ]]; then
    ok "✓ OpenCode config (generated + symlinked)"
    ok_count=$((ok_count + 1))
  else
    error "✗ OpenCode config"
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
  
  local nvim_check_links=("init.lua" "lua" "lazy-lock.json" "stylua.toml" ".gitignore" "db_ui")
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

  # === SUDO: pedir contraseña UNA sola vez al inicio (Linux y macOS) ===
  # Se autentica con sudo -v (interactivo, una sola vez) y luego escribe una
  # regla temporal en sudoers que extiende el timeout a infinito (-1).
  # Esto es más fiable que un keepalive porque el keepalive basado en TTY
  # puede fallar si sudo vincula el timestamp al proceso principal en vez
  # del subshell de background.
  # Seguridad: timestamp_timeout=-1 solo extiende la sesión ya autenticada —
  # NO elimina la autenticación (diferente a NOPASSWD:ALL).
  # La regla se borra automáticamente al salir (éxito o error) via trap.
  info "Requesting sudo access (will be cached for the entire setup)..."
  if ! sudo -v; then
    error "sudo access required. Aborting."
    exit 1
  fi
  # Extender timeout a infinito durante el setup — sin expiración
  _sudoers_tmp="/etc/sudoers.d/portillo-dots-setup"
  echo "Defaults:$USER timestamp_timeout=-1" | sudo tee "$_sudoers_tmp" > /dev/null
  sudo chmod 0440 "$_sudoers_tmp"
  trap 'sudo rm -f "$_sudoers_tmp" 2>/dev/null' EXIT

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
  
  setup_opencode
  echo ""
  
  install_dev_tools
  echo ""
  
  create_symlinks
  echo ""
  
  configure_default_shell
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
