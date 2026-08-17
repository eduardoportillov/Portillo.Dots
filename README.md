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
  - Hack Nerd Font, Kanagawa Dragon theme
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
│   ├── .dircolors          # Readable permission colors for Kanagawa Dragon
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
- `~/.dircolors` → `$REPO/zsh/.dircolors`; Linux also installs a protected copy for `sudo -i`
- `~/.markdownlint.jsonc` → `$REPO/.markdownlint.jsonc`

## Mapa de colores de `ls` (Kanagawa Dragon)

GNU `ls` decide el color mediante `LS_COLORS`, generado desde
[`zsh/.dircolors`](zsh/.dircolors). Alacritty renderiza los colores ANSI con la
paleta oficial de [`kanagawa_dragon.toml`](alacritty/themes/kanagawa_dragon.toml).

### Azul, blanco y rojo

| Color | Significado principal | Ejemplo de permisos |
|---|---|---|
| Azul Kanagawa | Directorio sin una condición especial de `LS_COLORS` | `drwxrwxr-x` (`0775`) o `drwxrwx---` (`0770`) |
| Blanco Kanagawa | Archivo regular sin otra regla especial | `-rw-------` (`0600`), `-rw-r--r--` (`0644`) o `-rw-rw-rw-` (`0666`) |
| Rojo Kanagawa `#e46876` | Directorio con escritura global (`o+w`), tenga sticky bit o no | `drwxrwxrwx` (`0777`) o `drwxrwxrwt` (`1777`) |
| Amarillo Kanagawa `#e6c384` | Sticky bit sin escritura global | `drwxr-xr-t` (`1755`) |

#### El color y los permisos son datos distintos

Una línea de `ll` muestra, entre otras cosas, dos piezas de información separadas:

```text
-rw-rw-rw- 1 eduardoportillo eduardoportillo 317 Mar 24 19:51 .env
^^^^^^^^^^                                                   ^^^^
 permisos                                              nombre con color
```

La primera columna (`-rw-rw-rw-`) siempre describe el tipo y los permisos del
objeto. El color se aplica principalmente al **nombre** (`.env`) y sirve para
clasificar rápidamente su tipo o alguna condición especial. El color no sustituye
la lectura de los permisos y no es una auditoría completa de seguridad.

Por eso no existe una relación como "blanco significa `0666`". Un archivo regular
puede ser `0600`, `0644`, `0664` o `0666` y continuar blanco: si no es ejecutable,
no coincide con una extensión coloreada y no tiene otra condición especial, cae
en la categoría genérica de archivo regular. En esta configuración esa categoría
usa el foreground normal de Kanagawa Dragon (`#c5c9c5`), que se percibe blanco.

#### Cómo leer `-rw-rw-rw-`

La cadena tiene diez posiciones, divididas como `- | rw- | rw- | rw-`:

| Posición | Fragmento | Significado |
|---|---|---|
| 1 | `-` | Es un archivo regular. `d` indicaría directorio y `l`, enlace simbólico. |
| 2-4 | `rw-` | El propietario puede leer (`r`) y escribir (`w`), pero no ejecutar (`-`). |
| 5-7 | `rw-` | Los miembros del grupo pueden leer y escribir, pero no ejecutar. |
| 8-10 | `rw-` | Los demás usuarios (`others`) pueden leer y escribir, pero no ejecutar. |

En notación octal, `r=4`, `w=2` y `x=1`. Cada bloque `rw-` suma `4+2=6`,
por lo que `rw-rw-rw-` equivale a `0666`:

```text
usuario   grupo     others
rw-       rw-       rw-
 6         6         6       -> 0666
```

Esto permite que cualquier cuenta local, o proceso ejecutado bajo otra cuenta,
lea y modifique el archivo. No significa por sí solo que el archivo sea accesible
desde Internet: eso depende del servicio y de los directorios que lo contienen.
Sin embargo, para un `.env` con secretos suele ser demasiado permisivo; normalmente
debería ser `0600` (`rw-------`). Un archivo de configuración sin secretos suele
usar `0644` (`rw-r--r--`), salvo que la aplicación requiera otra cosa.

#### Qué significa "directorio normal" en azul

"Normal" es una categoría visual de `LS_COLORS`, no una garantía absoluta de que
los permisos sean correctos. La regla `DIR 01;34` pinta azul cualquier directorio
que no active una regla más específica:

- `OTHER_WRITABLE`: escritura permitida a `others` (`o+w`).
- `STICKY_OTHER_WRITABLE`: ambas condiciones a la vez.
- `STICKY`: sticky bit activo (`+t`) sin `o+w`.

Por eso varios permisos diferentes pueden aparecer azules:

| Permisos | Octal | Interpretación |
|---|---:|---|
| `drwx------` | `0700` | Solo el propietario puede usar el directorio. |
| `drwxr-x---` | `0750` | Propietario completo; el grupo puede entrar y listar; `others` no accede. |
| `drwxrwx---` | `0770` | Propietario y grupo tienen control completo; `others` no accede. |
| `drwxr-xr-x` | `0755` | Solo el propietario escribe; todos pueden entrar y listar. |
| `drwxrwxr-x` | `0775` | Propietario y grupo escriben; `others` puede entrar y listar, pero no escribir. |

En un directorio, `r` permite listar nombres, `w` permite crear, borrar o renombrar
entradas, y `x` permite atravesarlo y acceder a su contenido. Las operaciones
reales suelen requerir una combinación de `w` y `x`.

En la captura, `apps` y `config` son `0775`, mientras que `nextcloud_data` es
`0770`; todos aparecen azules porque ninguno concede escritura a `others` ni usa
sticky bit. Aun así, los permisos de grupo deben ser apropiados para quién integra
ese grupo: el azul no evalúa si el grupo es demasiado amplio.

`themes`, en cambio, es `drwxrwxrwx` (`0777`). Tiene `o+w`, así que cualquier
usuario local puede crear, reemplazar o borrar entradas allí; la regla roja tiene
prioridad sobre el azul de directorio.

#### Sticky bit: diferencia entre `1755`, `0777` y `1777`

El sticky bit es el bit especial octal `01000`, también llamado *restricted
deletion flag*. En un directorio compartido evita que un usuario sin privilegios
borre o renombre entradas de otro usuario: solo puede hacerlo el propietario de
la entrada, el propietario del directorio o `root`.

| Permisos | Octal | Color | Efecto |
|---|---:|---|---|
| `drwxr-xr-x` | `0755` | Azul | Directorio común, sin escritura global ni sticky. |
| `drwxr-xr-t` | `1755` | Amarillo | Sticky activo, pero `others` no puede escribir; es un estado especial protegido. |
| `drwxrwxrwx` | `0777` | Rojo | Todos pueden escribir y cualquiera podría borrar entradas ajenas. |
| `drwxrwxrwt` | `1777` | Rojo | Todos pueden escribir, pero sticky restringe el borrado; `/tmp` usa normalmente este modo. |

La `t` minúscula ocupa la posición de ejecución de `others` y significa sticky
con `x`; una `T` mayúscula significa sticky sin `x`. Sticky no concede escritura
por sí mismo. Por eso `1755` es amarillo, mientras `0777` y `1777` son rojos por
su `o+w`.

### Leyenda completa

| Apariencia | Tipo o estado |
|---|---|
| Blanco (foreground `#c5c9c5`) | Archivo regular sin regla especial |
| Azul | Directorio normal |
| Rojo brillante sin fondo (`#e46876`) | Directorio `OTHER_WRITABLE` o `STICKY_OTHER_WRITABLE` |
| Amarillo brillante sin fondo (`#e6c384`) | Directorio `STICKY` sin escritura global |
| Verde | Archivo ejecutable |
| Cian | Enlace simbólico y archivos de audio |
| Magenta | Imágenes, video, sockets y doors |
| Naranja Kanagawa (`#b6927b`) | Comprimidos y paquetes (`.tar`, `.zip`, `.deb`, etc.) |
| Gris | Backups y temporales (`.bak`, `.old`, `.swp`, `.tmp`, etc.) |
| Amarillo sobre fondo oscuro | Pipes y dispositivos de bloque o carácter |
| Negro Kanagawa sobre rojo Kanagawa | Ejecutable con `setuid` |
| Negro sobre amarillo | Ejecutable con `setgid` |
| Rojo sobre fondo oscuro | Enlace simbólico huérfano o inaccesible |

### Auditoría de contraste

Los valores se calcularon contra el fondo opaco Kanagawa Dragon `#181616`. Se usa
como umbral conservador `4.5:1`, habitual para texto normal:

| Uso | Colores | Ratio |
|---|---|---:|
| Archivo regular | `#c5c9c5` sobre `#181616` | `10.76:1` |
| Directorio | `#8ba4b0` sobre `#181616` | `6.90:1` |
| Escritura global | `#e46876` sobre `#181616` | `5.61:1` |
| Sticky sin `o+w` | `#e6c384` sobre `#181616` | `10.73:1` |
| Comprimido/paquete | `#b6927b` sobre `#181616` | `6.34:1` |
| `setuid` | `#0d0c0c` sobre `#e46876` | `6.08:1` |
| `setgid` | `#0d0c0c` sobre `#c4b28a` | `9.38:1` |

El mapa reemplaza específicamente el azul sobre verde predeterminado de GNU para
directorios escribibles y el blanco sobre rojo de `setuid`, que con esta paleta
solo alcanzaba `1.88:1`. Alacritty permanece idéntico al tema oficial; los ajustes
viven exclusivamente en `zsh/.dircolors`.

La misma configuración se aplica al usuario local y, como copia protegida
`root:root 0644`, a `sudo -i`.

### SSH directo y `remote.sh`

`remote.sh deploy` y `remote.sh connect` usan `zsh/.dircolors` como única fuente
de verdad y organizan los archivos remotos de la siguiente forma:

| Ruta en el host | Contenido | Ciclo de vida |
|---|---|---|
| `~/.dircolors` | Copia del mapa de colores Kanagawa Dragon | **Persistente** (para herramientas estándar) |
| `~/.portillo-dots-remote-state/` | `ls-colors.sh` (resuelto), checksums y respaldo original | **Persistente** (no requiere GNU `dircolors` remoto) |
| Bloque en `~/.bashrc` o `~/.zshrc` | Carga de `ls-colors.sh` y alias de color | **Persistente** (delimita inicio/fin administrado) |
| `~/.portillo-remote/` | Dotfiles completos (`nvim`, etc.) y binarios portables | **Persistente** con `deploy`; **transitorio** con `connect --cleanup` |

El cleanup normal de `remote.sh connect` elimina `~/.portillo-remote`, pero
conserva ese estado pequeño para que SSH directo siga funcionando. Si ya existía
un `~/.dircolors`, se respalda una sola vez. `remote.sh teardown HOST` retira solo
el bloque administrado y restaura el archivo original.

Para tmux remoto, `remote.sh` usa un servidor dedicado (`tmux -L portillo-dots`),
por lo que nunca modifica ni reutiliza sesiones tmux normales del servidor. Las
nuevas ventanas ejecutan el Bash administrado. Cuando cambia la versión del mapa,
conserva todos los panes existentes y selecciona una ventana nueva con el entorno
actualizado; una shell que ya estaba ejecutándose no puede cambiar
retroactivamente sus variables. También crea otra ventana si se solicita una ruta
`--cd` diferente.

Con `--cleanup`, el runtime transitorio se elimina cuando no hay una sesión tmux
dedicada; si la sesión sigue activa, se conserva para no romper panes o clientes.
`remote.sh teardown` termina únicamente el servidor `portillo-dots`, nunca el tmux
predeterminado del host.

Comandos habituales:

```bash
./remote.sh deploy HOST       # instala dotfiles/binarios y activa SSH directo
./remote.sh connect HOST      # despliega y entra por tmux dedicado
./remote.sh status HOST       # audita versión, Bash, SSH directo y tmux
./remote.sh teardown HOST -f  # desinstala todo y restaura la configuración previa
```

El sufijo `*` que muestra `ls -F` no es una alerta del mapa: significa que el
archivo tiene algún bit de ejecución. El sufijo `/` identifica directorios.

## Moving the Repo

If you move the repo to a different path, symlinks will break because they use absolute paths. Fix them by running:

```bash
bash /nueva/ruta/Portillo.Dots/setup.sh --config-only
```

This recreates all symlinks to point to the new location without reinstalling packages.

## Customization

- **Shell**: Edit `zsh/.zshrc` for environment variables, aliases, and tool setup
- **Colores de `ls`**: Edit `zsh/.dircolors`; rerun `setup.sh --config-only` to sync the root copy
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

### Tiling: o-tiling (BSP dinámico, migrado desde Forge)
El tiling lo provee **o-tiling** (`o-tiling@oliwebd.github.com`, fork de Pop Shell),
instalado y configurado por `./setup.sh` (scripts en `o-tiling/`). Tiling BSP
dinámico automático, navegación Alt+Ctrl+HJKL (foco) / Alt+Shift+HJKL (mover/swap),
float con Shift+Super+C, toggle tiling con Super+T. Soporta N monitores (árbol por
monitor). En Wayland: **logout + login** tras instalar para que cargue.

> Historia: Forge (abandonado, bug #303 multi-monitor) → se probó Tiling Shell
> (estable pero zonas fijas, no splits dinámicos) → se migró a **o-tiling** que sí
> hace BSP dinámico estilo Forge/AeroSpace. Solo puede haber UN tiler activo: tener
> dos a la vez corrompe el window-stack de Mutter.

#### Atajos de o-tiling (sinónimos de AeroSpace)
| Acción | Atajo |
|---|---|
| Foco entre ventanas | `Alt+Ctrl+H/J/K/L` |
| Mover horizontal (cruza al otro monitor en el borde) | `Alt+Shift+H/L` |
| Mover vertical (reacomoda en el MISMO monitor, no salta) | `Alt+Shift+J/K` |
| Orientación del split horizontal ↔ vertical | `Alt+/` |
| Float / unfloat ventana | `Shift+Super+C` |
| Toggle auto-tiling on/off | `Super+T` |
| Workspaces (GNOME) | `Alt+1..5` cambiar · `Alt+Shift+1..5` mover ventana |

Gaps de tiling = **1px** (`gap-inner`/`gap-outer`).

**Mover H/L vs J/K** (parche local `o-tiling/patches/apply-patches.sh`):
- `Alt+Shift+H/L` (horizontal): si no hay ventana al lado, cruza al **otro monitor** (deseado, monitores lado a lado).
- `Alt+Shift+J/K` (vertical): reacomoda arriba/abajo **solo en el mismo monitor**; si no hay vecina, no hace nada (patcheado para NO saltar de monitor — el `move_up/move_down` upstream caía al monitor).

**Cómo apilar ventanas en VERTICAL** (arriba/abajo en el mismo monitor):
o-tiling es BSP: el eje lo decide **`Alt+/`**. Enfocá una ventana, apretá `Alt+/` para
poner el contenedor en vertical, y las ventanas se apilan arriba/abajo; ahí
`Alt+Shift+J/K` las reacomoda.

**Cómo redimensionar con teclado** (que una ventana sea más grande que otra):
o-tiling redimensiona en su "modo gestión": **`Super+Return`** (entrar) → **`Shift+H/L`**
(o `Shift+J/K`) para agrandar/achicar → **`Return`** para confirmar (`Escape` cancela).
No hay resize de una sola tecla (es el diseño de o-tiling; no `tile-resize-*-global`).

> Diferencias con AeroSpace sin equivalente: acordeón (`Alt+,` = stacking, desactivado
> por el bug de crash), resize de una tecla, `Alt+Tab` back-and-forth y mover workspace
> a otro monitor. Para un i3/AeroSpace 100% idéntico haría falta Sway (otro compositor).

### El tiling se degrada / Ctrl+Alt+T o Win+Shift+S dejan de funcionar
La config de atajos NO se pierde (es un problema de runtime de la extensión de tiling).

- **Recuperar sin logout:** `dots-fix-tiling` (disable→enable o-tiling).
  Si no alcanza, **logout + login** resetea todo.
- **Capturar evidencia cuando esté roto:** `dots-diag` → guarda la
  firma del bug en `~/.local/state/dots-diag-*.txt`.
- (`dots-fix-tiling` y `dots-diag` se instalan como comandos en `~/.local/bin`
  al correr `./setup.sh`.)
- o-tiling está pineado a una versión reproducible en `o-tiling/install.sh`
  (`OTILING_VERSION`). Para actualizar: cambiar el valor, `bash o-tiling/install.sh
  --force`, logout+login.

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
