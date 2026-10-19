# Despliegue remoto: contrato y garantías verificadas

`remote.sh` despliega un runtime de trabajo (`~/.portillo-remote`) en un host SSH.
Este documento describe el contrato que las pruebas de integración garantizan.

## Garantías verificadas

Las pruebas en `tests/test_remote_integration.py` ejecutan los scripts reales de
despliegue contra un transporte SSH/rsync **falso**, sobre un HOME temporal que
modela el servidor. No hay red ni servidor real.

| Garantía | Cómo se verifica |
|---|---|
| El payload es una **lista permitida** | Ningún archivo `opencode/`, `.env`, `secrets.env` o `connections.lua` llega al runtime |
| **Rollback** ante fallo de transferencia | El despliegue anterior sobrevive; el staging parcial se elimina |
| **Rollback** ante fallo de instalación de binarios | El runtime anterior sobrevive; no quedan directorios `*-old-*` |
| **Actualización** en sitio | Un redeploy restaura el contenido versionado y no deja staging ni rollback |
| **Teardown** selectivo | Borra solo el runtime administrado; los archivos ajenos quedan intactos |
| **Limpieza con tmux activo** | Una sesión dedicada en curso preserva el runtime |
| **Limpieza sin tmux** | El runtime transitorio se elimina |
| **Conexión** con `--cleanup` | Despliega, conecta, limpia lo transitorio y conserva el estado persistente |
| **Conexión** con `--no-cleanup` | Conserva el runtime para reutilizarlo |
| **Conexión fallida** | No deja runtime transitorio |
| **tmux aislado** | Ningún script remoto invoca tmux sin `-L`; ninguno escribe `~/.tmux.conf` |
| **Rutas con espacios** | `save_host_path`/`get_host_path` hacen round-trip con `/srv/my app (v2)/dir` |
| **Delimitadores** | `|` y saltos de línea se rechazan y no se registran; `=` se permite y viaja bien |
| **Plataforma no soportada** | Rechaza antes de descargar nada y sugiere `--skip-bins` |
| **Arquitectura no soportada** | Se reporta explícitamente |
| **`--skip-bins`** | Despliega configuración sin descargar ni transferir binarios |
| **Caché corrupta** | El SHA-256 no coincide → se aborta **antes** de transferir |
| **`--refresh-bins`** | Borra solo los artefactos conocidos; los archivos ajenos de la caché sobreviven |

## Qué entra en la transferencia

`remote/deploy-manifest.py` emite una lista NUL-delimitada de archivos
**versionados y sin secretos**. `rsync --from0 --files-from` transmite solo esos.
El argumento de perfil selecciona la carga:

| Perfil (`--like`) | Contenido |
|---|---|
| `workstation` (por defecto) | La base compartida + el árbol LazyVim (`nvim/init.lua`, `nvim/lua/**/*.lua`, `nvim/lazy-lock.json`, `nvim/lazyvim.json`, `nvim/stylua.toml`, `nvim/.neoconf.json`) |
| `server` | Solo la base compartida: `shared/shell/common.sh`, `shared/tmux/base.conf`, `shared/nvim/base.lua` |

Ambos perfiles incluyen además `zsh/.dircolors` y `.markdownlint.jsonc`. La base
compartida es la misma que `setup.sh` despliega en `~/.config/portillo-dots/`,
de modo que un runtime remoto se siente idéntico a un host instalado.

Excluye siempre: `opencode/`, `.env`, `secrets.env`, `nvim/db_ui/connections.lua`,
`.claude/`, logs, backups y cualquier archivo no versionado. El manifiesto falla si
un archivo permitido no existe o es un symlink.

Los binarios se transfieren con `rsync --include` explícito por nombre de artefacto
— nunca un directorio completo de caché.

## Toolset del runtime

El conjunto de binarios portátiles lo declara `remote_runtime_components` en
`installer/components.sh` (una sola fuente, compartida con `remote.sh status`):
el runtime `workstation` lleva la toolchain de LazyVim (nvim, rg, fd, fzf,
lazygit, node/npm, stylua, tmux); el runtime `server` solo nvim, rg, fd, fzf y
tmux. Como los scripts de instalación corren en el host remoto sin el repo, la
lista viaja con la llamada en `PORTILLO_RUNTIME_BINS` y el perfil en
`PORTILLO_RUNTIME_PROFILE`.

## Coexistencia con `setup.sh`

Un host puede tener el perfil `server` instalado (`setup.sh --profile server`) y
recibir además un runtime `remote.sh`. No se rompe nada ni se pierde nada:

- **`~/.tmux.conf` es solo de `setup.sh`**: un test prohíbe a `remote.sh`
  escribirlo. Las sesiones remote usan el servidor dedicado `tmux -L
  portillo-dots` con la **misma base compartida** (`shared/tmux/base.conf`).
- **Bloques de shell con marcadores distintos** (`Portillo.Dots Remote Server`
  frente a `Portillo.Dots ls colors`): conviven y ninguno pisa al otro.
- **`~/.dircolors` lo gestionan ambos temporalmente**: `remote.sh` lo respalda y
  `teardown` lo restaura (ida y vuelta sin pérdida; el contenido de colores es
  el mismo `zsh/.dircolors`).
- **Mientras un runtime esté desplegado manda su experiencia**: su bloque
  antepone sus binarios al PATH y exporta `NVIM_APPNAME`, así que `nvim` usa la
  config del runtime. Con `--like server` esa config **es la misma base
  compartida** que la instalada (sesión indistinguible); con `--like
  workstation` es LazyVim, el entorno de desarrollo remoto.
- `setup.sh --check` avisa si `~/.dircolors` lo está gestionando un runtime:
  la verificación describe el estado real, no un fallo.

Práctica recomendada en hosts ya instalados: `remote.sh connect HOST --like
server`, y `remote.sh teardown HOST -f` para volver al estado instalado puro.

## Ciclo de vida del runtime

```text
prepare_remote_base   crea stage con sentinel + deploy-id
deploy_configs        copia la lista permitida y hace swap atómico
deploy_binaries       descarga, verifica SHA-256, transfiere e instala
deploy_shell_environment  bloque gestionado en ~/.bashrc o ~/.zshrc
finalize_remote_deploy    confirma el deploy-id y retira el rollback
```

El swap preserva `bin/`, `downloads/`, `fzf/`, `node/`, `zig/`, `nvim-runtime/` y
`tmux/plugins/` del runtime anterior. Si algo falla, `abort_remote_deploy` restaura
el directorio `*-old-*` y elimina el staging.

`SIGKILL` o un apagado abrupto pueden dejar staging u operaciones de instalación a
medio camino; no se afirma rollback automático en ese caso. El sentinel y el
deploy-id evitan que un directorio no administrado sea borrado por error.

## tmux: servidor dedicado

Todo uso remoto de tmux pasa por `-L portillo-dots`:

- No se escribe `~/.tmux.conf` ni se toca `~/.tmux/plugins`.
- No se crea ni se habilita ningún servicio de tmux.
- El alias `tm` del shell remoto usa `tmux -L portillo-dots new-session -A -s portillo`.

Un test estático recorre los scripts y exige `-L` en toda invocación real; otro
prohíbe escrituras a `~/.tmux.conf`.

## Plataformas y binarios

- Solo Linux se soporta para binarios portables; x86_64 y ARM64.
- La arquitectura **del servidor** decide las descargas, no la del cliente.
- `--skip-bins` despliega solo configuración, sin red.
- `--refresh-bins` descarta la caché conocida para forzar descargas nuevas.

Cada descarga se verifica contra el SHA-256 publicado por el release y se validan
las rutas y enlaces de los archivos comprimidos antes de transferirlos.

## Cómo probarlo

```bash
python3 -B -m unittest discover -s tests -p 'test_remote_integration.py' -v
python3 -B -m unittest discover -s tests -p 'test_remote.py' -v
```

## Límites conocidos

- El transporte de las pruebas es un **modelo local**: resuelve `~` en el cliente y
  ejecuta los scripts remotos con un `HOME` temporal. No sustituye una prueba real
  contra SSH, rsync ni un servidor con otro shell/sistema de archivos.
- **No se ha desplegado a `.2`** durante esta refactorización. La validación de
  integración real sigue pendiente y debe hacerse primero con `--dry-run` de
  `setup.sh` y después con `remote.sh status`.
- Las pruebas de binarios con red real (`download_binaries_locally`) están fuera de
  la suite: se mockean. La verificación de integridad sí se prueba con datos
  locales y caché corrupta.
- Los nombres de archivo permitidos se contrastan con `git ls-files`; un archivo
  renombrado en el repo requiere actualizar `deploy-manifest.py` o las pruebas
  fallarán, que es el comportamiento deseado.
- `remote.sh --like server` replica la experiencia del perfil server de
  `setup.sh` (base compartida, sin LazyVim ni toolchains), pero no instala los
  paquetes nativos del perfil ni sus herramientas de catálogo (`opencode`,
  `pi`): son dos mecanismos distintos — runtime transitorio sin sudo frente a
  instalación de sistema — y no deben confundirse.
