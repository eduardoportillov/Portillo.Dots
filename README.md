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
  
- **tmux** — Terminal multiplexer with plugins via TPM
  - Kanagawa Dragon theme, vim mode, floating scratch window
  - Plugins: tmux-sensible, tmux-yank, tmux-resurrect, tmux-which-key, vim-tmux-navigator

### Shell & Prompt

- **zsh** + **Oh My Zsh** — Shell with plugin framework
  - **powerlevel10k** — Fast, customizable prompt
  
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

- **NVM** — Node Version Manager
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

## Feedback & Issues

Report issues or suggest improvements at: https://github.com/eduardoportillov/Portillo.Dots/issues

## License

MIT License — See repository for details.
