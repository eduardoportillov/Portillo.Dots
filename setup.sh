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
  info "Preparando entorno para Alacritty y Neovim"
  keep_sudo_credentials
  install_dependencies
  setup_alacritty
  setup_neovim
  info "Proceso completado. Abre Alacritty y Neovim para comenzar."
}

main "$@"
