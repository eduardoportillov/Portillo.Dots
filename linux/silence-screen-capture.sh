#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# silence-screen-capture — silencia el sonido de las capturas de GNOME
# =====================================================================
# GNOME Shell 50 reproduce el evento 'screen-capture' resolviéndolo por
# tema de sonidos. El tema del repo (theme-name 'portillo') ya lo agrega
# silencioso en ~/.local/share/sounds/... pero el gnome-shell vivo puede
# conservar la resolución del tema anterior hasta el siguiente reinicio
# de sesión. Este bypass sustituye la copia del sistema con una versión
# silenciosa vía dpkg-divert: cualquier proceso reproduce silencio
# siempre, y las actualizaciones de sound-theme-freedesktop conservan su
# original en el archivo *.distrib sin sobrescribir el nuestro.
#
# Uso (el bypass requiere sudo; status es de solo lectura):
#   sudo bash silence-screen-capture.sh install   # aplicarlo
#   sudo bash silence-screen-capture.sh restore   # revertirlo
#   bash silence-screen-capture.sh status         # estado actual

TARGET=/usr/share/sounds/freedesktop/stereo/screen-capture.oga
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SILENT="$SCRIPT_DIR/sound-theme/portillo/stereo/screen-capture.oga"

usage() {
  printf 'Uso: silence-screen-capture.sh install|restore|status\n'
  printf '  install  (sudo) instala silencio en %s vía dpkg-divert\n' "$TARGET"
  printf '  restore  (sudo) devuelve el archivo original del paquete\n'
  printf '  status   muestra si el bypass está aplicado\n'
}

is_diverted() {
  command -v dpkg-divert >/dev/null 2>&1 \
    && dpkg-divert --list "$TARGET" 2>/dev/null | grep -q .
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    printf 'Requiere root: sudo bash silence-screen-capture.sh install\n' >&2
    return 1
  fi
}

do_install() {
  require_root
  command -v dpkg-divert >/dev/null 2>&1 || {
    printf 'dpkg-divert no disponible; solo Debian/Ubuntu.\n' >&2
    return 1
  }
  [[ -f "$TARGET" ]] || {
    printf 'No existe el archivo del sistema: %s\n' "$TARGET" >&2
    return 1
  }
  [[ -f "$SILENT" && ! -L "$SILENT" ]] || {
    printf 'Falta el audio silencioso del repo: %s\n' "$SILENT" >&2
    return 1
  }
  if is_diverted; then
    printf 'Desvío ya registrado; refrescando el contenido silencioso.\n'
  else
    # El desvío persiste tras upgrades: el paquete escribe en *.distrib.
    dpkg-divert --local --rename --add "$TARGET"
  fi
  install -o root -g root -m 0644 "$SILENT" "$TARGET"
  printf 'Capturas con silencio: %s (original en %s.distrib).\n' "$TARGET" "$TARGET"
}

do_restore() {
  require_root
  if is_diverted; then
    dpkg-divert --remove --rename "$TARGET"
    printf 'Archivo original de sound-theme-freedesktop restaurado.\n'
  else
    printf 'No hay desvío que revertir para %s.\n' "$TARGET"
  fi
}

do_status() {
  if ! command -v dpkg-divert >/dev/null 2>&1; then
    printf 'dpkg-divert no disponible (distro sin dpkg).\n'
    return 1
  fi
  if is_diverted; then
    if [[ -f "$TARGET" && ! -L "$TARGET" ]] && cmp -s "$SILENT" "$TARGET" 2>/dev/null; then
      printf 'aplicado (silencio instalado)\n'
    else
      printf 'divertido, con contenido distinto al silencio esperado\n'
    fi
    printf 'original: %s.distrib\n' "$TARGET"
  else
    printf 'no aplicado (solo el tema portillo del repo)\n'
  fi
}

case "${1:-}" in
  install) do_install ;;
  restore) do_restore ;;
  status) do_status ;;
  *) usage; exit 1 ;;
esac
