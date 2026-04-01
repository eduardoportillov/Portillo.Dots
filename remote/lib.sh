#!/usr/bin/env bash
set -uo pipefail

REMOTE_BASE="$HOME/.portillo-remote"
REMOTE_BIN="$REMOTE_BASE/bin"
REMOTE_CONFIG="$REMOTE_BASE"
REMOTE_NVIM_SHARE="$HOME/.local/share/nvim-portillo-remote"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

info()  { echo -e "${BLUE}ℹ${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)  echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    armv7l|armhf)  echo "armv7l" ;;
    *) error "Unsupported architecture: $arch"; return 1 ;;
  esac
}

detect_os() {
  local os
  os="$(uname -s)"
  case "$os" in
    Linux)  echo "linux" ;;
    Darwin) echo "darwin" ;;
    *) error "Unsupported OS: $os"; return 1 ;;
  esac
}

ensure_dir() {
  mkdir -p "$1"
}

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

get_local_version() {
  local bin="$1"
  local bin_path="$REMOTE_BIN/$bin"

  [[ ! -x "$bin_path" ]] && return 1

  case "$bin" in
    nvim)    "$bin_path" --version | head -1 | grep -oE '[0-9]+\.[0-9]+[a-z0-9]*' ;;
    tmux)    "$bin_path" -V        | grep -oE '[0-9]+\.[0-9]+[a-z0-9]*' ;;
    rg)      "$bin_path" --version | head -1 | grep -oE '[0-9]+\.[0-9]+[a-z0-9]*' ;;
    fd)      "$bin_path" --version | head -1 | grep -oE '[0-9]+\.[0-9]+[a-z0-9]*' ;;
    fzf)     "$bin_path" --version | grep -oE '[0-9]+\.[0-9]+[a-z0-9]*' | head -1 ;;
    lazygit) "$bin_path" --version | grep -oE '[0-9]+\.[0-9]+[a-z0-9]*' | head -1 ;;
  esac
}

get_remote_version() {
  local repo="$1"
  local location
  location="$(curl -sI -o /dev/null -w '%{redirect_url}' \
    "https://github.com/$repo/releases/latest" 2>/dev/null)"
  local tag="${location##*/}"
  tag="${tag#v}"
  echo "$tag"
}

needs_update() {
  local bin="$1"
  local repo="$2"

  if [[ ! -x "$REMOTE_BIN/$bin" ]]; then
    return 0
  fi

  local local_ver remote_ver
  local_ver="$(get_local_version "$bin")"
  remote_ver="$(get_remote_version "$repo")"

  if [[ -z "$remote_ver" ]]; then
    ok "$bin ${local_ver:-unknown} (up to date, remote unreachable)"
    return 1
  fi

  if [[ "$local_ver" == "$remote_ver" ]]; then
    ok "$bin $local_ver (up to date)"
    return 1
  fi

  info "$bin $local_ver → $remote_ver"
  return 0
}
