# tmux

Configuración de tmux de estos dotfiles. El archivo principal es [`tmux.conf`](./tmux.conf),
que se enlaza a `~/.tmux.conf` (lo hace `setup.sh`). Los plugins se gestionan con **TPM** y se
instalan en `~/.tmux/plugins/` (no se versionan; quedan declarados por las líneas `@plugin`).

> **Prefix:** `Ctrl-a` (reemplaza al `Ctrl-b` por defecto).

---

## Plugins instalados

| Plugin | Qué hace | Cómo se usa |
|--------|----------|-------------|
| **tpm** | Gestor de plugins de tmux. Lee las líneas `@plugin` de la config y descarga, actualiza y borra los demás plugins. | `Ctrl-a` + `I` instalar · `Ctrl-a` + `U` actualizar · `Ctrl-a` + `Alt-u` limpiar |
| **tmux-sensible** | Ajustes por defecto razonables (quita el retardo de Esc, sube el historial de scroll, arregla UTF-8, recarga rápida). | Automático |
| **tmux-yank** | Hace que al copiar dentro de tmux el texto llegue al **portapapeles real del sistema** (pegar con `Ctrl-V` en otras apps). | En copy-mode: selecciona y pulsa `y` |
| **vim-tmux-navigator** | Mueve el foco entre **paneles de tmux** y **splits de Neovim** con las mismas teclas, sin distinguir uno de otro. | `Ctrl-h/j/k/l` (sin prefix) |
| **tmux-resurrect** | Motor de guardado: toma una foto de las sesiones (ventanas, paneles, directorios) y la guarda en disco para recuperarla tras cerrar tmux o reiniciar. Manual por sí solo. | `Ctrl-a` + `Ctrl-s` guardar · `Ctrl-a` + `Ctrl-r` restaurar |
| **tmux-continuum** | Automatiza a resurrect: **auto-guarda cada 1 min**, **auto-restaura** al abrir tmux y levanta tmux al iniciar sesión (autoboot vía systemd). | Automático |
| **tmux-which-key** | Menú emergente con todos los atajos y lo que hace cada uno, para no memorizarlos. | `Ctrl-a` + `Espacio` |
| **tmux-kanagawa** | Tema visual (paleta Dragon): pinta la barra de estado y bordes, y muestra git / CPU / RAM en la barra. | Automático |
| **extrakto** | Agarra cualquier texto en pantalla (rutas, URLs, hashes, comandos) con un buscador difuso (fzf) para insertarlo o copiarlo, sin mouse. | `Ctrl-a` + `Tab` → `Enter` insertar · `Tab` alternar copiar |

---

## Atajos propios (definidos en `tmux.conf`, no de plugins)

| Acción | Tecla |
|--------|-------|
| Split horizontal | `Ctrl-a` + `v` |
| Split vertical | `Ctrl-a` + `d` |
| Popup flotante `scratch` (toggle) | `Alt-g` |
| Matar todas las demás sesiones | `Ctrl-a` + `K` |
| Enviar el prefix a una app interna | `Ctrl-a` + `Ctrl-a` |

Otros ajustes activos: modo de teclas `vi` en copy-mode, ratón habilitado, barra de estado arriba,
índices empezando en 1, y clipboard end-to-end vía OSC 52 (`set-clipboard on` + `allow-passthrough on`).

---

## Persistencia de sesiones (resurrect + continuum)

Cómo sobreviven las sesiones a un reinicio, sin intervención manual:

1. **continuum** auto-guarda el estado cada **1 minuto** (llama al motor de resurrect), y también
   re-lanza programas listados en `@resurrect-processes` (opencode, claude; nvim ya por defecto).
2. **Al iniciar sesión**, continuum levanta tmux mediante un servicio systemd de usuario que él
   mismo genera y habilita (`@continuum-boot 'on'` → `~/.config/systemd/user/tmux.service`).
3. Al arrancar el servidor, continuum **auto-restaura** la última foto (`@continuum-restore 'on'`).

Fallback manual si algo no restaura solo: `Ctrl-a` + `Ctrl-r`.

> **`@continuum-boot 'on'` REQUIERE el drop-in `linux/tmux.service.d/10-path.conf`** (desplegado
> por `setup.sh`). El servicio systemd arranca tmux con un PATH que **no incluye**
> `/home/linuxbrew/.linuxbrew/bin` (donde vive el `tmux` de Homebrew); TPM llama a `tmux` por
> nombre, no lo encuentra y **falla** → ni kanagawa ni continuum se inicializan (server sin tema y
> sin auto-restore). El drop-in inyecta `Environment=PATH=...` con linuxbrew y lo arregla; además
> sobrevive a que continuum regenere su unit. Verificar: `systemctl --user show tmux.service -p Environment`
> debe incluir linuxbrew.

> **Orden de carga importante:** `tmux-continuum` debe declararse **después** del tema
> `tmux-kanagawa`. continuum engancha su auto-guardado anteponiéndolo a `status-right`, y el tema
> sobrescribe `status-right` al cargar; si continuum cargara antes, el tema borraría el hook y el
> auto-guardado dejaría de funcionar.

---

## Mantenimiento

- **Instalar plugins nuevos:** añade la línea `@plugin` en `tmux.conf` y pulsa `Ctrl-a` + `I`
  (o corre `~/.tmux/plugins/tpm/bin/install_plugins`).
- **Recargar la config sin reiniciar tmux:** `tmux source-file ~/.tmux.conf`.
- **Requisito de extrakto:** `fzf` instalado en el sistema.
