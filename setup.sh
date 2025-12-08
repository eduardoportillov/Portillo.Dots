#!/usr/bin/env bash

set -euo pipefail

# Define colors if tput is available
if command -v tput >/dev/null 2>&1; then
  GREEN="$(tput setaf 114)"
  YELLOW="$(tput setaf 221)"
  BLUE="$(tput setaf 39)"
  RED="$(tput setaf 196)"
  CYAN="$(tput setaf 45)"
  RESET="$(tput sgr0)"
else
  GREEN=""
  YELLOW=""
  BLUE=""
  RED=""
  CYAN=""
  RESET=""
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP_SUDO_ALIVE=true

info() { printf "%b\n" "${CYAN}%s${RESET}" "${1}"; }
warn() { printf "%b\n" "${YELLOW}%s${RESET}" "${1}"; }
error() { printf "%b\n" "${RED}%s${RESET}" "${1}" >&2; exit 1; }

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "No se encontró el comando requerido: $1"
  fi
}

keep_sudo_credentials() {
  sudo -v
  if [ "$KEEP_SUDO_ALIVE" = true ]; then
    while true; do
      sudo -n true
      sleep 60
      kill -0 "$$" || exit
    done 2>/dev/null &
    SUDO_HELPER_PID=$!
  fi
}

cleanup() {
  if [ -n "${SUDO_HELPER_PID:-}" ]; then
    kill "$SUDO_HELPER_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

backup_path() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local backup="${target}.bak-${timestamp}"
    mv "$target" "$backup"
    warn "Se creó un respaldo en ${backup}"
  fi
}

copy_config() {
  local source_dir="$1"
  local dest_dir="$2"

  if [ ! -d "$source_dir" ]; then
    error "No se encontró el directorio de configuración ${source_dir}"
  fi

  backup_path "$dest_dir"
  mkdir -p "$(dirname "$dest_dir")"
  cp -R "$source_dir" "$dest_dir"
  info "Copiado ${source_dir##*/} en ${dest_dir}"
}

ensure_fd_alias() {
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    sudo mkdir -p /usr/local/bin
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    info "Se creó alias fdfind -> fd"
  fi
}

detect_platform() {
  local uname_s
  uname_s="$(uname -s)"
  case "$uname_s" in
    Darwin)
      PLATFORM="mac"
      ;;
    Linux)
      PLATFORM="linux"
      ;;
    *)
      error "Sistema operativo no soportado: ${uname_s}"
      ;;
  esac
}

choose_linux_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    LINUX_MANAGER="apt"
  elif command -v pacman >/dev/null 2>&1; then
    LINUX_MANAGER="pacman"
  else
    error "Distribución Linux no soportada. Se requiere apt o pacman."
  fi
}

install_packages_mac() {
  if ! command -v brew >/dev/null 2>&1; then
    info "Instalando Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi

  brew update
  brew install \
    neovim \
    node \
    ripgrep \
    fd \
    fzf \
    python \
    git \
    curl

  brew install --cask alacritty
}

install_packages_apt() {
  sudo apt-get update
  sudo apt-get install -y \
    build-essential \
    curl \
    git \
    unzip \
    fontconfig \
    ripgrep \
    fzf \
    fd-find \
    neovim \
    alacritty \
    nodejs \
    npm \
    python3 \
    python3-pip

  ensure_fd_alias
}

install_packages_pacman() {
  sudo pacman -Syu --noconfirm
  sudo pacman -S --needed --noconfirm \
    base-devel \
    curl \
    git \
    unzip \
    fontconfig \
    ripgrep \
    fd \
    fzf \
    neovim \
    alacritty \
    nodejs \
    npm \
    python-pip
}

install_dependencies() {
  detect_platform
  if [ "$PLATFORM" = "mac" ]; then
    install_packages_mac
  else
    choose_linux_manager
    if [ "$LINUX_MANAGER" = "apt" ]; then
      install_packages_apt
    else
      install_packages_pacman
    fi
  fi
}

install_tmux_plugins() {
  info "Instalando TPM y plugins de tmux"
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  if [ ! -d "$tpm_dir" ]; then
    git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
  fi
  # Plugins definidos en tmux/.tmux.conf serán gestionados por TPM al iniciar tmux
}

install_zsh_plugins() {
  info "Instalando complementos de zsh (zsh-autosuggestions, zsh-syntax-highlighting)"
  local zsh_local="$HOME/.local/share/zsh"
  mkdir -p "$zsh_local"
  if [ ! -d "$zsh_local/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$zsh_local/zsh-autosuggestions"
  fi
  if [ ! -d "$zsh_local/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$zsh_local/zsh-syntax-highlighting"
  fi
}

install_powerlevel10k() {
  info "Instalando Powerlevel10k"
  if [ ! -f "$HOME/.p10k.zsh" ]; then
    if [ ! -d "$HOME/.powerlevel10k" ]; then
      git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.powerlevel10k"
    fi
    # Copy provided p10k config if exists in repo
    if [ -f "$SCRIPT_DIR/p10k.zsh" ]; then
      backup_path "$HOME/.p10k.zsh"
      cp "$SCRIPT_DIR/p10k.zsh" "$HOME/.p10k.zsh"
    else
      # create minimal p10k bootstrap
      cat > "$HOME/.p10k.zsh" <<'P10K'
# Minimal Powerlevel10k config
typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir vcs)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time)
P10K
    fi
  fi
}

install_starship() {
  info "Instalando Starship prompt"
  if command -v brew >/dev/null 2>&1 && [ "$PLATFORM" = "mac" ]; then
    brew install starship || true
  else
    if [ "$PLATFORM" = "linux" ]; then
      if command -v apt-get >/dev/null 2>&1; then
        curl -sS https://starship.rs/install.sh | sh -s -- -y
      else
        curl -sS https://starship.rs/install.sh | sh -s -- -y
      fi
    fi
  fi
  # Copy starship.toml if provided
  if [ -f "$SCRIPT_DIR/starship.toml" ]; then
    backup_path "$HOME/.config/starship.toml"
    mkdir -p "$HOME/.config"
    cp "$SCRIPT_DIR/starship.toml" "$HOME/.config/starship.toml"
  fi
}

install_clipboard_tools() {
  info "Instalando herramientas de portapapeles (xclip/xsel)"
  if [ "$PLATFORM" = "linux" ]; then
    if [ "$LINUX_MANAGER" = "apt" ]; then
      sudo apt-get install -y xclip xsel || true
    elif [ "$LINUX_MANAGER" = "pacman" ]; then
      sudo pacman -S --needed --noconfirm xclip xsel || true
    fi
  fi
  # Note: win32yank is Windows-only; user should install on Windows host if needed
}

setup_alacritty() {
  info "Configurando Alacritty"
  local dest="$HOME/.config/alacritty"
  mkdir -p "$HOME/.config"
  copy_config "$SCRIPT_DIR/alacritty" "$dest"
}

setup_neovim() {
  info "Configurando Neovim"
  local dest="$HOME/.config/nvim"
  mkdir -p "$HOME/.config"
  copy_config "$SCRIPT_DIR/nvim" "$dest"
}

main() {
  info "Preparando entorno para Alacritty, Neovim, tmux y zsh"
  keep_sudo_credentials
  install_dependencies
  install_tmux_plugins
  install_zsh_plugins
  install_powerlevel10k
  install_starship
  install_clipboard_tools
  setup_alacritty
  setup_neovim
  info "Proceso completado. Abre Alacritty, Neovim y tmux para finalizar la instalación de plugins."
  info "Para tmux: abre tmux y presiona prefix + I para que TPM instale plugins"
}

main "$@"
