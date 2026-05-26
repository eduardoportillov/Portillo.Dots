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
gsettings set org.gnome.desktop.wm.preferences workspace-names "['work', 'others', 'dev', 'dev-back', 'dev-front']"

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
gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-right "['<Alt><Shift>Tab']"
gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "[]"
gsettings set org.gnome.desktop.wm.keybindings toggle-maximized "['<Ctrl><Alt>f']"
gsettings set org.gnome.desktop.wm.keybindings begin-move "[]"
gsettings set org.gnome.desktop.wm.keybindings begin-resize "[]"

# Ctrl+Alt+T debe abrir Alacritty directamente, sin depender del terminal por defecto de GNOME.
gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "[]"
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'Alacritty'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'alacritty'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Control><Alt>t'

echo "GNOME configurado."
