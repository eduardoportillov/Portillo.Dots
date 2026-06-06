#!/usr/bin/env bash
set -euo pipefail

echo "Configurando GNOME..."

if ! command -v gsettings >/dev/null 2>&1; then
  echo "Error: gsettings no está disponible." >&2
  exit 1
fi

# Teclado e interfaz del sistema.
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us+altgr-intl')]"
gsettings set org.gnome.shell.keybindings show-screenshot-ui "['<Super><Shift>s']"

# Workspaces fijos y compartidos por todos los monitores.
gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.desktop.wm.preferences num-workspaces 5
gsettings set org.gnome.mutter workspaces-only-on-primary false
# Nombres y orden de workspaces sinónimos de AeroSpace (aerospace/aerospace.toml):
# Alt+1=work, Alt+2=dev-front, Alt+3=dev-back, Alt+4=others, Alt+5=comodin.
gsettings set org.gnome.desktop.wm.preferences workspace-names "['work', 'dev-front', 'dev-back', 'others', 'comodin']"

# Cambiar a workspace (Alt + 1-5).
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-1 "['<Alt>1']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-2 "['<Alt>2']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-3 "['<Alt>3']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-4 "['<Alt>4']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-5 "['<Alt>5']"

# Enviar ventana a workspace (Alt + Shift + 1-5).
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-1 "['<Alt><Shift>1']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-2 "['<Alt><Shift>2']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-3 "['<Alt><Shift>3']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-4 "['<Alt><Shift>4']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-5 "['<Alt><Shift>5']"

# Monitores y ventanas.
# move-to-monitor-right intencionalmente NO bindeado: el binding Alt+Shift+Tab
# trae más problemas que beneficios (colisión con switch-windows-backward).
# Si necesitas mover ventana entre monitores, usa drag con mouse o Alt+Shift+H/L
# de Forge para mover dentro del árbol de tiling.
gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-right "[]"
gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "[]"
gsettings set org.gnome.desktop.wm.keybindings toggle-maximized "['<Shift><Alt>f']"
gsettings set org.gnome.desktop.wm.keybindings begin-move "[]"
gsettings set org.gnome.desktop.wm.keybindings begin-resize "[]"

# Custom keybindings:
#   custom0 = Ctrl+Alt+T → Alacritty (sin depender del terminal por defecto de GNOME)
#   custom1 = Super+Shift+R → dots-fix-tiling (reinicia o-tiling cuando se corrompe el stack)
gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "[]"
CK_PATH=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding
CK0=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/
CK1=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$CK0', '$CK1']"
gsettings set "$CK_PATH:$CK0" name 'Alacritty'
gsettings set "$CK_PATH:$CK0" command 'alacritty'
gsettings set "$CK_PATH:$CK0" binding '<Control><Alt>t'
gsettings set "$CK_PATH:$CK1" name 'Reset o-tiling'
gsettings set "$CK_PATH:$CK1" command "$HOME/.local/bin/dots-fix-tiling"
gsettings set "$CK_PATH:$CK1" binding '<Super><Shift>r'

echo "GNOME configurado."
