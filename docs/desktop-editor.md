# Escritorio, tmux y Neovim

## Clipboard: selección por servidor de display

`nvim/lua/config/options.lua` elige el proveedor según lo que realmente está
disponible, en este orden:

| Contexto | Proveedor | Comportamiento |
|---|---|---|
| SSH (`SSH_TTY`, `SSH_CONNECTION`, o `NVIM_APPNAME=portillo-remote/nvim`) | OSC 52 | **solo copia** |
| Wayland (`WAYLAND_DISPLAY` + `wl-copy`) | wl-clipboard | copia y pega |
| X11 (`DISPLAY` + `xclip`) | xclip | copia y pega |
| macOS o sin proveedor | proveedor integrado de Neovim | copia y pega |

### Bug corregido

La versión anterior seleccionaba `wl-copy` con solo `command -v wl-copy`, sin
comprobar `WAYLAND_DISPLAY`. En una sesión **X11 con wl-clipboard instalado**,
Neovim elegía `wl-copy`, que no puede alcanzar ningún portapapeles: el yank se
perdía silenciosamente. Ahora cada proveedor exige su display server.

También se hicieron dos ajustes:

- **OSC 52 en SSH es solo copia**, igual que la config de Server. El paste por
  OSC 52 le pediría al terminal el portapapeles del cliente, que muchas terminales
  no soportan; con el registro unnamed el comportamiento es predecible.
- `require("vim.ui.clipboard.osc52")` va con `pcall`: en un Neovim sin ese módulo
  la config **no rompe al cargar**, cae al proveedor local.

### Cobertura

`tests/test_editor_configs.py` cubre la matriz completa: SSH (tres variantes),
SSH sin osc52, Wayland, X11, ambos displays a la vez (gana Wayland), ausencia de
display y macOS. El stub de OSC 52 **lanza error si se invoca paste**, de modo que
la prueba falla si alguien reintroduce lecturas del portapapeles del cliente.

## Neovim: política de atajos

Un test carga cada spec con stubs, ejecuta sus `init`/`config` y recolecta todos
los `keys` y `vim.keymap.set`. Falla si dos archivos definen el mismo `(modo, lhs)`.

**Conflicto resuelto:** `<leader>db` pertenecía a DBUI y al breakpoint del debugger.
Ahora:

- `<leader>db` — toggle breakpoint (debugger)
- `<leader>dB` — condición del breakpoint (debugger)
- `<leader>Db` — Database UI

Son distintos porque los atajos de Neovim son sensibles a mayúsculas. El grupo
`<leader>d` queda reservado para depuración; `Db` está deliberadamente fuera del
patrón `d<minúscula>` para no invadirlo.

El debugger también conserva los cambios de robustez: rutas escapadas con
`fnameescape`, y valores del `.env` entrecomillados, vacíos o con puntuación se
conservan **sin evaluar** sustituciones de shell.

## Server no descarga nada automáticamente

`server/nvim/init.lua` y `server/tmux.conf` no arrancan gestores de plugins ni
toolchains. Un test prohíbe en Server:

- `require("lazy")`, `lazy.nvim`, `git clone`, `install_plugins`, TPM
- `npm install`, `npx`, `cargo`, `rustup`, `uv tool`, `curl`, `wget`, `markitdown`
- `@plugin`, `continuum`, `resurrect` y unidades systemd en tmux

Es la diferencia con `remote.sh`, que sí prepara LazyVim/TPM para el caso de
"desarrollo remoto". Son flujos distintos.

## tmux: arranque y restauración

El orden de carga está documentado en `tmux/tmux.conf` y ahora se verifica:

```text
tpm → sensible → yank → navigator → resurrect → which-key → extrakto
    → kanagawa → continuum → run tpm
```

`tmux-continuum` debe ir **después de `tmux-resurrect`** (depende de él) y
**después de `tmux-kanagawa`**: el tema sobrescribe `status-right` al cargar y
borraría el hook de auto-save de continuum si este cargara antes. Un test exige
ese orden y que TPM se inicialice al final.

`@continuum-restore 'on'` y `@continuum-boot 'on'` son explícitos, y el drop-in
`linux/tmux.service.d/continuum-autoboot-fixes.conf` que el autoboot necesita está
versionado. Ese drop-in inyecta el PATH de Linuxbrew y espera la sincronización
del reloj antes de arrancar tmux.

La config de Server **no** lleva TPM, continuum ni resurrect.

## Alacritty: regresión

`tests/test_desktop.py` y `tests/test_editor_configs.py` cubren:

- `terminal.shell` correcto por plataforma (`/usr/bin/env zsh` en Linux,
  `/bin/zsh` en macOS)
- `osc52 = "onlycopy"` en ambas configs
- `hints.enabled.command` en forma de objeto, no string
- el tema Kanagawa referenciado existe

## GNOME: conservación de atajos

`gnome/configure.sh` hace **merge** de la lista de atajos personalizados en vez de
sobrescribirla, usa entradas con nombre (`portillo-terminal`,
`portillo-tiling-reset`) y rechaza escribir si el formato GVariant es inesperado.
El tiling nativo de Mutter solo se desactiva si o-tiling está habilitada.

`tests/test_gnome.py` lo cubre con `gsettings`/`gnome-extensions` simulados; nunca
se toca el dconf real durante las pruebas.

## Cómo probarlo

```bash
python3 -B -m unittest discover -s tests -p 'test_editor_configs.py' -v
python3 -B -m unittest discover -s tests -p 'test_desktop.py' -v
python3 -B -m unittest discover -s tests -p 'test_gnome.py' -v
python3 -B -m unittest discover -s tests -p 'test_lua.py' -v
```

## Límites conocidos

- Las specs de Neovim se cargan con stubs; no se ejecuta un Neovim real con
  LazyVim, ni se valida que cada plugin instalado acepte estos atajos. Un plugin
  externo puede reclamar un binding ya usado.
- La matriz de clipboard valida la **selección**, no que wl-copy/xclip/OSC 52
  funcionen en un terminal real. No se lee ni se escribe ningún portapapeles.
- macOS está cubierto por lógica y TOML; no se ha probado el clipboard con
  pbcopy/pbpaste en un Mac.
- El arranque automático de tmux (systemd user service) no se ha ejecutado en un
  arranque real; se valida la configuración y el drop-in que lo soporta.
- `o-tiling` sigue deshabilitado por el bug upstream documentado en `TODO.md`; la
  configuración lo trata como opt-in y no lo activa automáticamente.
