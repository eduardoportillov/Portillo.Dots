#!/usr/bin/env bash
set -uo pipefail

# =====================================================================
# Forge Uninstall — erradica TODO rastro de Forge del sistema.
# =====================================================================
# Limpia:
#   - Extensión user-local (~/.local/share/gnome-shell/extensions/forge@...)
#   - Backups (forge@*.bak-*)
#   - Extensión system-wide (/usr/share/... y /usr/local/share/...)
#   - Paquete apt gnome-shell-extension-forge si está instalado
#   - Extension updates pendientes
#   - Stylesheets/configs en ~/.config/forge
#   - gnome-extensions-cli (gext) si fue instalado por pipx — opcional vía --purge-gext
#   - Lo quita de enabled-extensions de gnome-shell
#
# NO toca:
#   - dconf settings (/org/gnome/shell/extensions/forge/) → los gestiona
#     forge/configure.sh y son fuente de verdad de la repo.
#
# Uso:
#   bash forge/uninstall.sh [--purge-gext]
#
# Idempotente: si nada existe, sale OK.

FORGE_UUID="${FORGE_UUID:-forge@jmmaranan.com}"
PURGE_GEXT=false
[[ "${1:-}" == "--purge-gext" ]] && PURGE_GEXT=true

USER_EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
SYS_EXT_DIRS=(/usr/share/gnome-shell/extensions /usr/local/share/gnome-shell/extensions)

echo "Erradicando Forge del sistema..."

# 1. Deshabilitar la extensión si está habilitada
if command -v gnome-extensions >/dev/null 2>&1; then
  gnome-extensions disable "$FORGE_UUID" 2>/dev/null || true
fi

# 2. Quitar de enabled-extensions de gnome-shell
if command -v gsettings >/dev/null 2>&1; then
  current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo '[]')"
  # Python para edición robusta de la lista
  new="$(python3 -c "
import sys, ast
arr = ast.literal_eval(sys.argv[1])
arr = [e for e in arr if e != sys.argv[2]]
print(arr)
" "$current" "$FORGE_UUID" 2>/dev/null || echo "$current")"
  if [[ "$new" != "$current" ]]; then
    gsettings set org.gnome.shell enabled-extensions "$new" 2>/dev/null || true
    echo "  ✓ Quitado de enabled-extensions"
  fi
fi

# 3. Borrar extensión user-local + cualquier backup
removed=0
for dir in "$USER_EXT_DIR/$FORGE_UUID" "$USER_EXT_DIR/$FORGE_UUID".bak-*; do
  if [[ -e "$dir" ]]; then
    rm -rf "$dir"
    echo "  ✓ Borrado: $dir"
    removed=$((removed + 1))
  fi
done
[[ $removed -eq 0 ]] && echo "  (sin extensión user-local)"

# 4. Borrar extension-updates pendientes
if [[ -d "$HOME/.local/share/gnome-shell/extension-updates/$FORGE_UUID" ]]; then
  rm -rf "$HOME/.local/share/gnome-shell/extension-updates/$FORGE_UUID"
  echo "  ✓ Borrado: extension-updates/$FORGE_UUID"
fi

# 5. Borrar instalaciones system-wide (si fueron por paquete o manual)
for sys_dir in "${SYS_EXT_DIRS[@]}"; do
  if [[ -d "$sys_dir/$FORGE_UUID" ]]; then
    if [[ -w "$sys_dir" ]] || sudo -n true 2>/dev/null; then
      sudo rm -rf "$sys_dir/$FORGE_UUID"
      echo "  ✓ Borrado system-wide: $sys_dir/$FORGE_UUID"
    else
      echo "  ⚠ Requiere sudo manualmente: sudo rm -rf '$sys_dir/$FORGE_UUID'"
    fi
  fi
done

# 6. Paquete apt si estaba instalado
if command -v dpkg >/dev/null 2>&1 && dpkg -l 2>/dev/null | grep -q gnome-shell-extension-forge; then
  echo "  Removiendo paquete apt gnome-shell-extension-forge..."
  sudo apt-get remove -y gnome-shell-extension-forge >/dev/null 2>&1 \
    && echo "  ✓ Paquete apt eliminado" \
    || echo "  ⚠ Falló la eliminación del paquete apt"
fi

# 7. Stylesheets/configs viejos
if [[ -d "$HOME/.config/forge" ]]; then
  rm -rf "$HOME/.config/forge"
  echo "  ✓ Borrado: ~/.config/forge (stylesheets antiguos)"
fi

# 8. gext (gnome-extensions-cli) opcional
if [[ "$PURGE_GEXT" == true ]] && command -v gext >/dev/null 2>&1; then
  if command -v pipx >/dev/null 2>&1; then
    pipx uninstall gnome-extensions-cli >/dev/null 2>&1 \
      && echo "  ✓ pipx uninstall gnome-extensions-cli"
  fi
  # gext binary roto sin venv
  if [[ -L "$HOME/.local/bin/gext" || -f "$HOME/.local/bin/gext" ]]; then
    rm -f "$HOME/.local/bin/gext"
    echo "  ✓ Borrado: ~/.local/bin/gext"
  fi
fi

echo "Erradicación de Forge completa."
echo "Nota: dconf settings (/org/gnome/shell/extensions/forge/) NO se tocan."
echo "      Son la fuente de verdad y los maneja forge/configure.sh."
