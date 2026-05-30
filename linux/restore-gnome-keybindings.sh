#!/usr/bin/env bash
set -uo pipefail

# Reaplica configuración de GNOME y Forge al iniciar sesión.
# Resuelve: Ctrl+Alt+T, Win+Shift+S y Forge desactivado tras reboot.

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG_FILE="$LOG_DIR/restore-gnome-keybindings.log"
mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG_FILE"; }

log "=== Inicio: REPO_DIR=$REPO_DIR ==="

if ! command -v gsettings >/dev/null 2>&1; then
  log "gsettings no disponible, abortando"
  exit 0
fi

# Espera a que dbus de sesión esté listo (oneshot puede arrancar muy pronto)
for _ in {1..10}; do
  if gsettings get org.gnome.shell enabled-extensions >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

FORGE_UUID="forge@jmmaranan.com"
FORGE_DIR="$HOME/.local/share/gnome-shell/extensions/$FORGE_UUID"

if [[ -d "$FORGE_DIR" ]]; then
  gsettings set org.gnome.shell disable-extension-version-validation true 2>>"$LOG_FILE" || true

  if command -v gnome-extensions >/dev/null 2>&1; then
    if ! gnome-extensions list --enabled 2>/dev/null | grep -qx "$FORGE_UUID"; then
      log "Habilitando Forge"
      gnome-extensions enable "$FORGE_UUID" 2>>"$LOG_FILE" || log "WARN: gnome-extensions enable falló"
    else
      log "Forge ya habilitada"
    fi
  fi

  # Espera a que el schema esté disponible antes de configurarlo
  for _ in {1..10}; do
    if [[ -d "$FORGE_DIR/schemas" ]]; then
      break
    fi
    sleep 1
  done
fi

if [[ -x "$REPO_DIR/gnome/configure.sh" ]]; then
  log "Aplicando gnome/configure.sh"
  bash "$REPO_DIR/gnome/configure.sh" >>"$LOG_FILE" 2>&1 || log "WARN: gnome/configure.sh falló"
fi

# NO re-renderizar el árbol de Forge con un toggle de tiling-mode-enabled: corrompe
# el window-stack de Mutter y deja las ventanas nuevas invisibles. Ver TODO.md.
if [[ -d "$FORGE_DIR" && -x "$REPO_DIR/forge/configure.sh" ]]; then
  log "Aplicando forge/configure.sh"
  bash "$REPO_DIR/forge/configure.sh" >>"$LOG_FILE" 2>&1 || log "WARN: forge/configure.sh falló"
fi

log "=== Fin ==="
