# TODO

Pendientes después de la sesión de troubleshooting completo del 2026-05-26.

---

## 1. OSC 52 en Alacritty (sin tmux) no copia al system clipboard

### Síntoma
Al seleccionar texto en Claude Code dentro de Alacritty (sin tmux), aparece el mensaje:

> `sent 98 chars via OSC 52 · check terminal clipboard settings if paste fails`

El clipboard del sistema queda vacío. `Ctrl+V` en otra app no pega el texto seleccionado.

### Diagnóstico hecho
- ✅ `alacritty/alacritty.toml` tiene `osc52 = "onlycopy"` (lowercase, confirmado válido por `strings` del binario).
- ✅ `wl-clipboard` instalado (provee protocolo `wayland-data-control`).
- ✅ Symlink `~/.config/alacritty/alacritty.toml` → repo correcto.
- ✅ Sesión Wayland confirmada (`XDG_SESSION_TYPE=wayland`).
- ✅ Test directo: `printf '\033]52;c;%s\a' "$(echo -n TEST | base64)"` imprime la secuencia raw — Alacritty 0.16.1 **no procesa OSC 52** en este Wayland.

### Hipótesis pendientes
- **Alacritty 0.16.1 (Ubuntu apt) tiene bug con OSC 52 en Wayland**. Versión 0.17.0 upstream pudo arreglarlo.
- Conflicto entre Alacritty y otro clipboard manager (CopyQ está en autostart).

### Próximos pasos
1. **Actualizar Alacritty a 0.17.0 desde source**:
   ```bash
   # Instalar rustup
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source $HOME/.cargo/env
   # Build alacritty 0.17.0
   cargo install alacritty
   ```
   Automatizar en `setup.sh` con detección de versión apt (si <0.17, compilar).
2. **Verificar CopyQ no interfiere**: desactivar temporalmente `~/.config/autostart/com.github.hluk.copyq.desktop` y reabrir alacritty.
3. **Test desde alacritty NUEVO** tras update — esperar que el comando del Próximo paso 1 imprima `TEST_FINAL`.

### Workaround actual
Ninguno funcional desde Claude Code. Para copiar al system clipboard manualmente desde un comando:
```bash
echo "texto" | wl-copy
```

---

## 2. OSC 52 dentro de tmux no llega al system clipboard

### Síntoma
Al seleccionar texto en Claude Code dentro de `tmux` (dentro de Alacritty), aparece:

> `copied 98 chars to tmux buffer · paste with prefix + ]`

Solo entra al buffer interno de tmux. `Ctrl+V` en Chrome no pega. Hay que usar `prefix + ]` que pega dentro de tmux, no fuera.

### Diagnóstico hecho
- ✅ `tmux/tmux.conf` tiene `set -g set-clipboard on` y `set -g allow-passthrough on`.
- ✅ tmux 3.6b runtime confirmó `set-clipboard on`, `allow-passthrough on`.
- ✅ Symlink `~/.tmux.conf` → repo correcto.
- ❌ Claude Code detecta `$TMUX` y usa `tmux load-buffer` directo (no OSC 52). Como consecuencia, depende de tmux para propagar al system clipboard.
- ❌ tmux DEBERÍA propagar OSC 52 al terminal anfitrión (Alacritty) cuando `set-clipboard on`. Como Alacritty no procesa OSC 52 (problema #1), el clipboard se queda en el buffer de tmux.

### Causa raíz
Está **encadenada con el problema #1**: si Alacritty no acepta OSC 52, tmux no tiene a dónde reenviar. Resolver #1 probablemente resuelve este también.

### Próximos pasos
1. **Resolver primero el problema #1** (Alacritty 0.17.0).
2. Si #1 se resuelve pero #2 persiste, configurar tmux para escribir directo a `wl-copy` en lugar de delegar a OSC 52:
   ```bash
   # tmux/tmux.conf — copy en vim-mode también va a system clipboard
   bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "wl-copy"
   ```
   El bind ya existe para `xclip` cuando es Linux; cambiar a `wl-copy` si Wayland.
3. **Workaround inmediato**: usar `prefix + ]` para pegar desde el buffer de tmux a tmux. No es ideal pero funciona dentro de tmux.

### Workaround actual
- Dentro de tmux: `prefix + ]` para pegar (pega al pane activo, NO al clipboard del sistema).
- Para copiar al clipboard del sistema: salir de tmux y usar `wl-copy` directo.

---

## Bugs de Forge upstream (no fixables localmente)

### St.Icon already disposed
`lib/extension/indicator.js:125` no desconecta el listener al desactivarse, lo que causa crashes cuando un setting de Forge cambia.

**Mitigación aplicada**:
- Removido binding de `prefs-tiling-toggle` (Alt+Shift+R)
- Removido binding de `window-toggle-float` (Alt+Shift+;)
- Removido toggle off→on de `tiling-mode-enabled` en `restore-gnome-keybindings.sh`

**Próximos pasos**: Reportar issue en https://github.com/forge-ext/forge/issues. Cuando se publique release con el fix, re-habilitar bindings en `forge/configure.sh`.

---

## Versiones y actualizaciones automatizadas

| Tool | Actual | Última upstream | `./setup.sh` actualiza? |
|---|---|---|---|
| Alacritty | 0.16.1 (apt) | 0.17.0 | ❌ No (apt Ubuntu no tiene 0.17 todavía) — ver TODO #1 |
| tmux | 3.6b (brew) | 3.6b | ✅ Sí |
| Forge | main `0319a712` | mismo | ❌ Skip si ya instalado — usar `bash forge/install.sh --force` para forzar |

### Mejora pendiente en `forge/install.sh`
Agregar check de "is HEAD up-to-date" para auto-actualizar Forge cuando upstream tenga commits nuevos sin requerir `--force`:

```bash
# Comparar commit local vs HEAD remoto
local_commit=$(grep ^commit "$MARKER" | cut -d= -f2 | head -c8)
remote_commit=$(git ls-remote "$FORGE_REPO" "$FORGE_BRANCH" | cut -c1-8)
if [[ "$local_commit" != "$remote_commit" ]]; then
  echo "Forge desactualizado: $local_commit → $remote_commit. Reinstalando."
  # ... continuar con install normal
fi
```
