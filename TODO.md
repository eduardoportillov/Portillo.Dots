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

## Migración de tiling: Forge → Tiling Shell → o-tiling (2026)

**Por qué se fue Forge**: `forge@jmmaranan.com` quedó sin maintainer e incompatible con
GNOME 50.1. Corrompía el window-stack de Mutter en multi-monitor (bug upstream
[forge-ext/forge#303](https://github.com/forge-ext/forge/issues/303)), dejando las
ventanas nuevas sin allocation (invisibles) y atascando el dispatch de atajos del
shell — rompía Ctrl+Alt+T y Win+Shift+S a la vez. Firma:
```
meta_window_set_stack_position_no_sync: assertion 'window->stack_position >= 0' failed
JS ERROR: TypeError: can't access property "clone", record is undefined  @ workspaceAnimation.js:135 (_syncStacking)
```

**Tiling Shell (intermedio, descartado)**: estable en 50.1 pero usa layouts/zonas
fijas (FancyZones), no splits dinámicos — no replica el feel de Forge/AeroSpace.

**Solución actual: o-tiling** (`o-tiling@oliwebd.github.com`, fork de Pop Shell):
tiling BSP **dinámico** estilo Forge, soporta shell 48/49/50, atajos globales directos.
Scripts en `o-tiling/` (`install.sh` desde release ZIP de GitHub con `OTILING_VERSION`
pineado, `configure.sh` con gsettings). `setup.sh` y `restore-gnome-keybindings.sh`
desmontan Tiling Shell e instalan/habilitan o-tiling. Atajos: Alt+Ctrl/Shift+HJKL.

**Riesgo conocido / a observar**:
- **Solo UN tiler activo a la vez** — dos corrompen el stack (lección aprendida: el
  servicio de login re-habilitaba Tiling Shell y convivía con o-tiling → 224 assertions).
- o-tiling auto-floata diálogos; tiene "floating exceptions" para apps puntuales.

---

## 3. o-tiling DESHABILITADA (2026-07-17): corrompe stack_position en cada ventana nueva

**Estado actual**: `o-tiling@oliwebd.github.com` está **instalada pero deshabilitada**
(`enabled-extensions` vacío, `OTILING_AUTO_ENABLE=false` en `install.sh` y
`restore-gnome-keybindings.sh` — no se auto-prende en login). Sin tiler activo por ahora.

**Síntoma**: ya no es la corrupción intermitente que describía la sección de arriba —
ahora `meta_window_set_stack_position_no_sync: assertion 'window->stack_position >= 0'
failed` se dispara al 100% con **cualquier ventana nueva**, y el tiling/atajos
(`Ctrl+Alt+HJKL`) directamente no funcionan.

**Confirmado por aislamiento** (reproducible a demanda):
- Extensión deshabilitada → 0 errores, con cualquier app.
- Extensión habilitada → error en cada ventana nueva, sin excepción.
- Esto descarta que sea config nuestra o un bug genérico de Mutter sin relación —
  es el propio código de tiling de o-tiling el que dispara la corrupción.

**Se probaron y fallaron 4 mitigaciones**:
1. Actualizar el pin `v2.8.8 → v2.9.12` (varios releases con fixes de restack/teardown).
2. Patch local: diferir `auto_tile()` en `notify::wm-class` a `Meta.LaterType.BEFORE_REDRAW`.
3. Patch local: delay real de 150ms tras la señal `first-frame` (el punto que Mutter
   mismo recomienda como "seguro" para tocar una ventana nueva) — **falló igual**, lo
   que descarta timing/race como causa arreglable con solo un delay.
4. **Update a v2.9.21** (2026-07-29), después de que el maintainer respondiera en el
   issue #50 con un fix (`8483c91`: espera la señal `'restacked'` de Mutter antes de
   `raise()`/`activate()` en `grab_focus()`, en vez de un delay a ciegas) — **también
   falló**, confirmado en vivo (`journalctl --user -f` mientras se reproducía): el
   assertion se sigue disparando (esta vez con Chrome), y aparte, **incluso cuando NO
   se dispara ningún error**, el tiling y los atajos (`Ctrl+Alt+H/J/K/L`) tampoco
   funcionan — sin ningún error visible en `journalctl` ni en Looking Glass.

El patch 2 (`window.js`, `wm_class_changed`) sigue aplicado (no hace daño, no resolvió
el bug). El patch 3 se sacó de `apply-patches.sh`: dejó de aplicar limpio contra
v2.9.21 porque el fix del maintainer reescribió esa misma zona.

**Pista concreta para el fix, reportada en el comentario de seguimiento**: el fix
`8483c91` solo protege el `raise()` dentro de `grab_focus()` (camino de ventana nueva).
Hay un segundo `raise()` sin proteger en `window/window.js`, función standalone
`activate()` (línea ~773), usada por **22 sitios** en `extension.js` — incluidos los
4 atajos `focus-left/down/up/right` (`Ctrl+Alt+HJKL`). Como no tiene el mismo guard de
`'restacked'`, cualquier cambio de foco entre ventanas existentes puede pisar la misma
carrera, lo que explicaría por qué los atajos no responden aunque no haya ventana nueva
de por medio.

**Conclusión**: bug real de Mutter 50.1-0ubuntu2.2 (o de cómo o-tiling lo dispara),
todavía sin resolver pese al primer intento de fix upstream. Bug relacionado (misma
assertion, sin fix) en una extensión no relacionada:
[ubuntu/Tiling-Assistant#329](https://github.com/ubuntu/Tiling-Assistant/issues/329).

**Reportado upstream**: [oliwebd/o-tiling#50](https://github.com/oliwebd/o-tiling/issues/50)
(2 rondas: reporte inicial + seguimiento del 2026-07-29 con el hallazgo del segundo
`raise()`).

**Alternativa evaluada, no adoptada**: `tiling-assistant@ubuntu.com` (viene con Ubuntu,
ya está en el sistema, deshabilitada) no dispara el bug en uso normal — pero es un
paradigma distinto (snap manual arrastrando/atajos, sin auto-tile ni foco direccional
`Ctrl+Alt+HJKL`), no un reemplazo transparente.

**Próximos pasos**: revisar el issue #50 de tanto en tanto. Si upstream manda un fix
nuevo, `bash o-tiling/install.sh --force` con la versión nueva y `OTILING_AUTO_ENABLE=true
gnome-extensions enable o-tiling@oliwebd.github.com` para reactivar y volver a probar
(idealmente con `journalctl --user -f` corriendo en vivo mientras se reproduce, no
revisando el log después — así se distingue si el assertion se dispara de si el tiling
simplemente no hace nada). Si no hay movimiento, evaluar migrar a Tiling Assistant en
serio (requiere reconfigurar atajos desde cero, ver conversación de auditoría del
2026-07-17/29 para el detalle de por qué no es 1:1).

---

## Versiones y actualizaciones automatizadas

| Tool | Actual | Última upstream | `./setup.sh` actualiza? |
|---|---|---|---|
| Alacritty | 0.16.1 (apt) | 0.17.0 | ❌ No (apt Ubuntu no tiene 0.17 todavía) — ver TODO #1 |
| tmux | 3.6b (brew) | 3.6b | ✅ Sí |
| o-tiling | v2.9.21 (release ZIP) | mismo | ❌ Skip si ya instalado — `bash o-tiling/install.sh --force` para forzar. **Deshabilitada por bug, ver TODO #3** |
