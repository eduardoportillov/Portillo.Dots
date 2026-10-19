# Documentación de la refactorización

Cada documento cubre un área auditada de Portillo.Dots. El índice existe para que
todo sea descubrible desde `docs/` sin depender del README principal.

| Documento | Área |
|---|---|
| [refactor-review.md](refactor-review.md) | Cierre de la revisión de cambios pendientes |
| [profiles.md](profiles.md) | Perfiles Workstation y Server, componentes y límites |
| [platforms.md](platforms.md) | Paquetes, versiones mínimas y plataformas soportadas |
| [privileged-phase.md](privileged-phase.md) | Contrato de sudo y respaldos de sistema |
| [opencode.md](opencode.md) | Config V2, secretos y sincronización entre hosts |
| [remote-deploy.md](remote-deploy.md) | Despliegue remoto, rollback y aislamiento de tmux |
| [security-backups.md](security-backups.md) | Permisos, escaneo de secretos y recuperación |
| [desktop-editor.md](desktop-editor.md) | Clipboard, atajos de Neovim, tmux y Alacritty |
| [hardware-otiling.md](hardware-otiling.md) | Scripts de hardware y o-tiling |
| [operation-modes.md](operation-modes.md) | Modos de operación, resumen y códigos de salida |
| [performance.md](performance.md) | Mediciones y optimizaciones |
| [clipboard.md](clipboard.md) | Incidente del clipboard y recuperación segura |

## Cómo se prueba

```bash
python3 -B -m unittest discover -s tests -v
```

Cobertura por archivo de test:

| Archivo | Cubre |
|---|---|
| `test_installer.py` / `test_profiles.py` | instalador, perfiles, respaldos |
| `test_privileged.py` | fase privilegiada, copias de sistema, sudo |
| `test_platforms.py` | versiones, alias de ejecutables, rutas por plataforma |
| `test_opencode_sync.py` / `test_opencode_checks.py` | config V2, secretos, plugins |
| `test_remote.py` / `test_remote_integration.py` | despliegue remoto contra transporte falso |
| `test_security.py` | permisos, escaneo de secretos, respaldos, logs |
| `test_desktop.py` / `test_editor_configs.py` / `test_lua.py` | Alacritty, Neovim, clipboard, tmux |
| `test_gnome.py` | conservación de atajos de GNOME |
| `test_hardware_otiling.py` | scripts de hardware y o-tiling |
| `test_operation_modes.py` | modos, validación de argumentos, códigos de salida |
| `test_performance.py` | caché de versiones y consultas a gestores |
| `test_graphical_environment.py` / `test_shell_helpers.py` | entorno gráfico y utilidades |
| `test_config.py` / `test_workstation.py` | render de config y toolchains |
| `test_validation.py` | sintaxis Bash/Zsh/Python/TOML/JSONC/Lua + estructura |
| `test_shellcheck.py` | ShellCheck reproducible sobre todos los `.sh` |

### CI

`.github/workflows/ci.yml` corre la suite en **ubuntu-latest** y **macos-latest**,
más un job dedicado de ShellCheck y otro de escaneo de secretos. La matriz está
definida en [platforms.md](platforms.md).

ShellCheck se resuelve en este orden: `$SHELLCHECK_BIN` → `shellcheck` del `PATH`
→ descarga de la versión pineada con verificación de su SHA-256 publicado. Sin red
y sin binario, ese test se salta con un motivo claro; nunca rompe la suite por
falta de una herramienta.
