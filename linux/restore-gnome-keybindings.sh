#!/usr/bin/env bash
set -uo pipefail

# Reaplica configuración de GNOME y Tiling Shell al iniciar sesión.
# Resuelve: Ctrl+Alt+T, Win+Shift+S y la extensión de tiling desactivada tras reboot.

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

TS_UUID="tilingshell@ferrarodomenico.com"
TS_DIR="$HOME/.local/share/gnome-shell/extensions/$TS_UUID"

if [[ -d "$TS_DIR" ]]; then
  gsettings set org.gnome.shell disable-extension-version-validation true 2>>"$LOG_FILE" || true

  if command -v gnome-extensions >/dev/null 2>&1; then
    if ! gnome-extensions list --enabled 2>/dev/null | grep -qx "$TS_UUID"; then
      log "Habilitando Tiling Shell"
      gnome-extensions enable "$TS_UUID" 2>>"$LOG_FILE" || log "WARN: gnome-extensions enable falló"
    else
      log "Tiling Shell ya habilitada"
    fi
  fi

  # Espera a que el schema esté disponible antes de configurarlo
  for _ in {1..10}; do
    if [[ -d "$TS_DIR/schemas" ]]; then
      break
    fi
    sleep 1
  done
fi

if [[ -x "$REPO_DIR/gnome/configure.sh" ]]; then
  log "Aplicando gnome/configure.sh"
  bash "$REPO_DIR/gnome/configure.sh" >>"$LOG_FILE" 2>&1 || log "WARN: gnome/configure.sh falló"
fi

if [[ -d "$TS_DIR" && -x "$REPO_DIR/tilingshell/configure.sh" ]]; then
  log "Aplicando tilingshell/configure.sh"
  bash "$REPO_DIR/tilingshell/configure.sh" >>"$LOG_FILE" 2>&1 || log "WARN: tilingshell/configure.sh falló"
fi

log "=== Fin ==="
