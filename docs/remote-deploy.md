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

Incluye: `nvim/init.lua`, `nvim/lua/**/*.lua`, `nvim/lazy-lock.json`,
`nvim/lazyvim.json`, `nvim/stylua.toml`, `nvim/.neoconf.json`, `zsh/.dircolors`,
`.markdownlint.jsonc` y `server/tmux.conf`.

Excluye siempre: `opencode/`, `.env`, `secrets.env`, `nvim/db_ui/connections.lua`,
`.claude/`, logs, backups y cualquier archivo no versionado. El manifiesto falla si
un archivo permitido no existe o es un symlink.

Los binarios se transfieren con `rsync --include` explícito por nombre de artefacto
— nunca un directorio completo de caché.

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
- `install-binaries.sh` sigue instalando LazyVim/TPM para el caso de "desarrollo
  remoto"; no es el perfil `server` de `setup.sh`, que es más ligero. Son dos
  flujos distintos y no deben confundirse.
