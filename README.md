# Portillo.Dots

Automatización para dejar listo un entorno con **Alacritty** y **Neovim** en macOS o Linux. El script `setup.sh` instala las dependencias principales (usando Homebrew, apt o pacman) y copia las configuraciones versionadas en este repositorio a `~/.config`.

## Requisitos

- macOS 12+ o una distro Linux con `apt` (Debian/Ubuntu) o `pacman` (Arch/Endeavour).
- Acceso a `sudo`.
- Conexión a internet (descarga paquetes y plugins de Neovim).
- Fuente *Iosevka Term Nerd Font* u otra Nerd Font instalada para aprovechar iconos en terminal y Neovim.

## Qué hace el script

1. Mantiene la sesión `sudo` viva mientras corre el proceso.
2. Instala paquetes base: `alacritty`, `neovim`, `node`, `ripgrep`, `fd`, `fzf`, `git`, `curl`, `python` y dependencias básicas.
3. Crea un alias `fd` -> `fdfind` en sistemas basados en Debian si es necesario.
4. Copia las configuraciones:
	- `alacritty/alacritty.toml` → `~/.config/alacritty/`
	- `nvim/init.lua` → `~/.config/nvim/`
5. Bootstrap automático de `lazy.nvim` para gestionar plugins en Neovim (instala temas, Treesitter, Telescope, Lualine y Gitsigns).

## Uso

```bash
chmod +x setup.sh
./setup.sh
```

El script detecta el sistema operativo y selecciona el gestor de paquetes apropiado. Si ya existe una configuración previa de Alacritty o Neovim, se mueve a un respaldo con el sufijo `.bak-YYYYMMDD-HHMMSS` antes de copiar la nueva.

## Estructura del repo

- `setup.sh`: script principal de instalación.
- `alacritty/alacritty.toml`: configuración del emulador de terminal.
- `nvim/init.lua`: configuración mínima de Neovim con Lazy y un conjunto de plugins listo para usar.

## Notas

- En Debian/Ubuntu antiguos `alacritty` puede no estar disponible en los repos oficiales; instala el paquete manualmente en ese caso.
- Los plugins de Neovim se instalarán en `~/.local/share/nvim` la primera vez que abras Neovim.
- Si prefieres conservar configuraciones previas, detén el script tras el paso de instalación de paquetes y restaura los respaldos generados.