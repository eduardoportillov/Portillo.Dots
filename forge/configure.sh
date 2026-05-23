#!/bin/bash

# =====================================================================
# SCRIPT MAESTRO: CLONACIÓN AEROSPACE -> FORGE (LINUX)
# =====================================================================
# Este script iguala el comportamiento de GNOME Forge al de AeroSpace.
# Fuente de verdad: Configuración .toml de macOS.

echo "Iniciando configuración maestra de Forge..."

# ---------------------------------------------------------------------
# 1. GAPS Y APARIENCIA (AeroSpace: 3px)
# ---------------------------------------------------------------------
gsettings set org.gnome.shell.extensions.forge window-gap-size 3

# ---------------------------------------------------------------------
# 2. NAVEGACIÓN (FOCO) - Identico a AeroSpace (Alt+Ctrl+HJKL)
# Propósito: Evitar conflictos con tmux y apps internas.
# ---------------------------------------------------------------------
gsettings set org.gnome.shell.extensions.forge.keybindings window-focus-left "['<Alt><Control>h']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-focus-down "['<Alt><Control>j']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-focus-up "['<Alt><Control>k']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-focus-right "['<Alt><Control>l']"

# ---------------------------------------------------------------------
# 3. MOVIMIENTO DE VENTANAS (Alt+Shift+HJKL)
# ---------------------------------------------------------------------
gsettings set org.gnome.shell.extensions.forge.keybindings window-move-left "['<Alt><Shift>h']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-move-down "['<Alt><Shift>j']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-move-up "['<Alt><Shift>k']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-move-right "['<Alt><Shift>l']"

# ---------------------------------------------------------------------
# 4. GESTIÓN DE WORKSPACES (Nombres y Atajos 1-4)
# ---------------------------------------------------------------------
gsettings set org.gnome.desktop.wm.preferences workspace-names "['work', 'dev-front', 'dev-back', 'others']"

# Cambiar a Workspace (Alt + 1-4)
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-1 "['<Alt>1']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-2 "['<Alt>2']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-3 "['<Alt>3']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-4 "['<Alt>4']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-5 "['<Alt>5']"

# Enviar ventana a Workspace (Alt + Shift + 1-4)
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-1 "['<Alt><Shift>1']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-2 "['<Alt><Shift>2']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-3 "['<Alt><Shift>3']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-4 "['<Alt><Shift>4']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-5 "['<Alt><Shift>5']"

# ---------------------------------------------------------------------
# 5. LAYOUTS, MONITORES Y VENTANA FLOTANTE (Identico a AeroSpace)
# ---------------------------------------------------------------------
# Cambiar entre mosaico horizontal/vertical (Alt + /)
gsettings set org.gnome.shell.extensions.forge.keybindings con-split-layout-toggle "['<Alt>slash']"

# Cambiar a modo Tabulado/Acordeón (Alt + ,)
gsettings set org.gnome.shell.extensions.forge.keybindings con-tabbed-layout-toggle "['<Alt>comma']"

# Mover espacio al siguiente monitor (Alt + Shift + Tab) (no sirve)
gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-right "['<Alt><Shift>Tab']"

# Ventana Flotante (Alt + Shift + ;)
# Nota: Usamos el inicio del Modo Servicio de tu Mac para ejecutar la acción directa.
gsettings set org.gnome.shell.extensions.forge.keybindings window-toggle-float "['<Alt><Shift>semicolon']"

# Pantalla completa (Alt + Shift + F)
gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['<Alt><Shift>f']"

# ---------------------------------------------------------------------
# NO FUNCIONA TODAVIA - REDIMENSIONAR (Resize smart - Alt + Minus/Equal)
# ---------------------------------------------------------------------
# Desactiva los atajos de Gaps que están robando el comando
gsettings set org.gnome.shell.extensions.forge.keybindings window-gap-size-decrease "['']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-gap-size-increase "['']"

# AeroSpace: Alt + Minus (Achicar ventana)
# Forzamos el decremento del tamaño del contenedor
gsettings set org.gnome.shell.extensions.forge.keybindings window-resize-right-decrease "['<Alt>minus']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-resize-bottom-decrease "['<Alt>minus']"

# Forzamos el incremento del tamaño del contenedor derecho/inferior simultáneamente
gsettings set org.gnome.shell.extensions.forge.keybindings window-resize-right-increase "['<Alt>equal']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-resize-bottom-increase "['<Alt>equal']"

# ---------------------------------------------------------------------
# 7. EXTRAS Y LIMPIEZA DE CONFLICTOS
# ---------------------------------------------------------------------
# Reset Layout / Botón de pánico (Equivalente a R en modo servicio)
gsettings set org.gnome.shell.extensions.forge.keybindings toggle-tiling "['<Alt><Shift>r']"

# Asegurar Terminal en Ctrl+Alt+T
gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "['<Control><Alt>t']"

# Desactivar atajos de GNOME que causan lag o conflictos
gsettings set org.gnome.desktop.wm.keybindings begin-move "['']"
gsettings set org.gnome.desktop.wm.keybindings begin-resize "['']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-snap-center "['']"

echo "¡Hecho! Tu Linux ahora se comporta exactamente como tu Mac con AeroSpace."
