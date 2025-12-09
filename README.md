# Stack

- Terminal
  - Alacritty — emulador GPU rápido y minimalista; gestiona apariencia y atajos.

- Shell
  - Zsh — intérprete de comandos principal.
    - Powerlevel10k (`~/.p10k.zsh`) — prompt rápido y configurable.
    - zsh-autosuggestions — sugiere comandos basados en historial.
    - zsh-syntax-highlighting — colorea comandos para detectar errores.
    - Starship — prompt minimalista y multiplataforma (opcional junto a p10k).

- Multiplexor de terminal
  - tmux — manejo de sesiones, ventanas y paneles.
    - TPM (`tmux-plugins/tpm`) — gestor de plugins para tmux.
    - tmux-sensible — sane defaults para tmux.
    - tmux-yank — integración de portapapeles.
    - vim-tmux-navigator — navegación entre vim y tmux panes.
    - tmux-resurrect — persistencia y restauración de sesiones.
    - tmux-which-key — ayuda visual de atajos en tmux.
    - tmux-kanagawa — tema visual para la barra de estado.

- Editor
  - Neovim — editor configurado con `lazy.nvim`.
    - opencode.nvim — utilidades y workflows (según repo exacto).
    - avante.nvim — tema/UI plugin.
    - copilot.lua + copilot-cmp — integración con GitHub Copilot (sugerencias/completado).
    - CopilotChat (placeholder) — interfaz de chat para Copilot (repo a concretar).
    - smear-cursor.nvim — efecto visual del cursor.
    - bufferline.nvim — barra de buffers con iconos.
    - treesitter, telescope, lualine, gitsigns — soporte de sintaxis, búsqueda y status.

- Portapapeles y utilidades
  - Linux: `xclip`, `xsel` — manejo del portapapeles desde comandos y Neovim/tmux.
  - Windows: `win32yank` — recomendado para integración en Windows/WSL.

# Dotstack

Este repositorio contiene el scaffold de dotstack en el subdirectorio `dotstack/`.

Para inicializar en un host:

1. Clona este repositorio (si no lo has hecho).
2. Ejecuta `dotstack/setup.sh --yes --preflight` desde `dotstack/` o manualmente:
   - `ln -s $(pwd)/dotstack ~/.dotstack`
   - `~/.dotstack/bin/dotstack preflight`
   - `~/.dotstack/bin/dotstack activate --append --yes`

El directorio `~/.dotstack` está enlazado al subdirectorio `dotstack/` de este repositorio para que el repositorio sea la fuente de verdad.
