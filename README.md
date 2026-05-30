# Portillo.Dots

Dotfiles for terminal setup across macOS and Linux. Fully idempotent setup script with Homebrew, Neovim (LazyVim), tmux, zsh with powerlevel10k, and dev tools.

## Quick Setup

```bash
git clone https://github.com/eduardoportillov/Portillo.Dots.git ~/Portillo.Dots
cd ~/Portillo.Dots
chmod +x setup.sh
./setup.sh
```

The setup script is **idempotent**: run it multiple times without issues. Symlinks are always updated to the latest repo content.

## Architecture

- **macOS & Linux**: Single setup script detects OS and applies appropriate configurations
- **Homebrew**: Primary package manager for both platforms
- **Symlink-based**: All configs symlinked from repo to home directory
- **Backup on first run**: Existing configs automatically backed up to `~/.dotfiles-backup/`

## Stack

### Terminal & Multiplexer

- **alacritty** — GPU-accelerated terminal emulator
  - Hack Nerd Font, Tokyo Night Storm theme
  - Blur, padding, custom keybindings
  - URL hints with Alt+Space (works on both macOS and Linux)
  - Note: On macOS, some users may prefer Command instead of Alt for hints. Edit `alacritty/alacritty.toml` line 73 to change `mods = "Alt"` to `mods = "Command"`
  
- **tmux** — Terminal multiplexer with plugins via TPM
  - Kanagawa Dragon theme, vim mode, floating scratch window
  - Plugins: tmux-sensible, tmux-yank, tmux-resurrect, tmux-which-key, vim-tmux-navigator

### Shell & Prompt

- **zsh** + **Oh My Zsh** — Shell with plugin framework
  - **powerlevel10k** — Fast, customizable prompt (default)
  - **starship** — Alternative prompt (available for future use, not installed by default)
  
- **Plugins**: git, z, brew, sudo, extract, web-search, zsh-autosuggestions, zsh-syntax-highlighting, you-should-use, copyfile, copypath, fzf

### Editor

- **Neovim (LazyVim)** — Modal editor with lazy.nvim plugin manager
  - **16 plugins**: Copilot, CopilotChat, nvim-dap, snacks.nvim, fzf-lua, lualine, incline, zen-mode, twilight, screenkey, precognition, smear-cursor, rip-substitute, render-markdown, opencode.nvim, which-key
  - **Extras**: docker, java, json, markdown, python, sql, yaml (LSPs via Mason)

### CLI Tools

- **git** — Version control
- **fzf, ripgrep, fd, bat** — Advanced file/text tools
- **lazygit, lazydocker** — UI wrappers for git and docker
- **zoxide, atuin** — Smart directory and command history
- **tree-sitter** — Syntax tree library
- **xclip** (Linux) / **pbcopy** (macOS) — Clipboard integration

### Fonts

- **Hack Nerd Font** — Monospace with Nerd icons

### Development Tools (optional via setup.sh)

- **FVM** — Fast Node Manager
- **SDKMAN** — Java, Kotlin, Gradle (auto-manages JAVA_HOME)
- **Go** — Via Homebrew
- **uv** — Python package/project manager

## File Structure

```
Portillo.Dots/
├── setup.sh               # Main installation script
├── README.md              # This file
├── .gitignore             # Git ignore patterns
├── tmux/
│   └── tmux.conf
├── nvim/
│   ├── init.lua
│   ├── lazy-lock.json
│   ├── lazyvim.json
│   ├── stylua.toml
│   ├── .neoconf.json
│   ├── .gitignore
│   └── lua/
│       ├── config/        # Neovim core config
│       └── plugins/       # Plugin specs
├── alacritty/
│   └── alacritty.toml
├── zsh/
│   ├── .zshrc
│   └── p10k.zsh           # Powerlevel10k config (1837 lines)
```

## Symlinks

After running `setup.sh`:

- `~/.tmux.conf` → `$REPO/tmux/tmux.conf`
- `~/.config/nvim/` → `$REPO/nvim/`
- `~/.config/alacritty/alacritty.toml` → `$REPO/alacritty/alacritty.toml`
- `~/.zshrc` → `$REPO/zsh/.zshrc`
- `~/.p10k.zsh` → `$REPO/zsh/p10k.zsh`

## Moving the Repo

If you move the repo to a different path, symlinks will break because they use absolute paths. Fix them by running:

```bash
bash /nueva/ruta/Portillo.Dots/setup.sh --config-only
```

This recreates all symlinks to point to the new location without reinstalling packages.

## Customization

- **Shell**: Edit `zsh/.zshrc` for environment variables, aliases, and tool setup
- **Prompt**: Configure `zsh/p10k.zsh` with `p10k configure` or edit directly
- **Editor**: Add/modify plugins in `nvim/lua/plugins/` (LazyVim spec format)
- **Terminal**: Adjust colors, fonts, opacity in `alacritty/alacritty.toml`
- **Multiplexer**: Edit `tmux/tmux.conf` for bindings, plugins, theme

## Alternativa: Starship

[Starship](https://starship.rs) es un prompt cross-shell minimalista escrito en Rust.

### ¿Cuándo considerar migrar?

| Situación                                   | ¿Migrar? |
| ------------------------------------------- | -------- |
| Usas múltiples shells (Fish, Bash, Nushell) | ✅ Sí    |
| Quieres unificación de prompt               | ✅ Sí    |
| Solo usas Zsh y p10k te funciona bien       | ❌ No    |

## Troubleshooting (Linux / GNOME)

### El tiling se degrada / Ctrl+Alt+T o Win+Shift+S dejan de funcionar
Forge (git main sobre GNOME 50.1) corrompe con el tiempo el window-stacking de
Mutter; las ventanas nuevas se lanzan pero quedan invisibles y los atajos del
shell se atascan. La config NO se pierde — es un problema de runtime de Forge.

- **Recuperar sin logout:** `dots-fix-tiling` (disable→enable Forge).
  Si no alcanza, **logout + login** resetea todo.
- **Capturar evidencia cuando esté roto:** `dots-diag` → guarda la
  firma del bug en `~/.local/state/dots-diag-*.txt`.
- (`dots-fix-tiling` y `dots-diag` se instalan como comandos en `~/.local/bin`
  al correr `./setup.sh`.)
- Forge está pineado a un commit reproducible en `forge/install.sh` (`FORGE_COMMIT`).
  Para bumpear: cambiar el valor, `bash forge/install.sh --force`, logout+login.

### La batería carga al 100% (debería limitarse al 60%)
El límite se aplica **únicamente** vía regla udev (`linux/99-battery-charge-threshold.rules`
→ `/etc/udev/rules.d/`), que se dispara en boot, al volver de suspensión y al
reconectar batería. `linux/optimize.sh` ya **no** toca la batería (era redundante).
Se instala con `./setup.sh`. Verificar:
`cat /sys/class/power_supply/BAT1/charge_control_end_threshold` debe decir `60`.
Nota: el límite topea cargas **futuras**; si la batería ya está al 100% no baja
sola, se queda ahí hasta descargarse y recargar (que parará en 60%).

## Feedback & Issues

Report issues or suggest improvements at: https://github.com/eduardoportillov/Portillo.Dots/issues

## License

MIT License — See repository for details.
