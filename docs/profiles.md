# Perfiles: componentes exactos y límites

## Los dos perfiles

`setup.sh` instala **dos perfiles**, no dos versiones de OpenCode:

| | **Dev Workstation** | **Remote Server** |
|---|---|---|
| Comando | `bash setup.sh --profile workstation` | `bash setup.sh --profile server` |
| Objetivo | Entorno completo de desarrollo | Administración y trabajo por SSH |

## Fuente única de componentes

`installer/components.sh` declara las herramientas de cada perfil con el formato
`<kind> <command> <description>`, donde `kind` es `required` u `optional`:

- **required** — el perfil está incompleto sin la herramienta; `--check` falla.
- **optional** — recomendable; su ausencia se informa pero nunca es un error.

`show_actions` la muestra y `verify_profile` la comprueba. Añadir una herramienta
en ese archivo la refleja en ambos lados, así no pueden divergir.

### Añadir una herramienta

Una herramienta nueva es **una línea de manifiesto + sus descriptores** en
`installer/components.sh` (más nada):

```bash
required pi - Pi agent harness                 # manifiesto (perfil, nombre, mínimo, descripción
tool_packages pi ...                           # paquete nativo por gestor (vacío si no aplica)
tool_source    pi npm:@earendil-works/pi-coding-agent   # canal de instalación
tool_requires  pi node>=22.19                  # dependencias con gate de versión
tool_upgrade   pi self:pi update               # canal de actualización
```

Canales que `install_source_tools` posee por completo (instalación y
actualización automáticas): `npm:` y `uv-tool:`. El canal `installer:` se sirve
de `run_installer` y las herramientas con lógica propia conservan su wrapper
(`installer/opencode.sh`, `installer/workstation.sh`); `fnm:` existe para
proveer Node a las dependencias. Los tests del catálogo exigen que cada
herramienta declare ruta de aprovisionamiento y método de actualización, así
que una herramienta añadida a medias rompe la suite antes que una instalación.

### Server — 15 herramientas requeridas

```text
git curl ssh rsync tmux nvim rg fd fzf bat jq htop python3 opencode pi
```

Sin escritorio, sin toolchains de desarrollo y sin instaladores de apps gráficas.

### Workstation — 23 requeridas + 4 opcionales

Requeridas (las 15 anteriores, más):

```text
zsh node pnpm go rustup uv claude zed
```

Opcionales:

```text
lazygit lazydocker zoxide atuin
```

## Qué garantiza Server

La verificación automática cubre estos límites (tests en `tests/test_profiles.py`):

- **No desinstala nada.** No hay comandos de eliminación (`apt-get remove`,
  `dnf remove`, `pacman -R`, `brew uninstall`, `userdel`, …) en ningún punto del
  instalador, para ningún perfil.
- **No toca escritorio, firewall ni servicios.** Un test inspecciona las fuentes y
  exige que `systemctl` aparezca únicamente dentro del guard `hardware == true`,
  que es una selección explícita con `--hardware`. No existe código de ufw,
  iptables, nftables ni sshd.
- **No borra la configuración de Workstation.** Aplicar Server sobre un HOME que
  ya tenga `~/.config/zed`, `~/.config/alacritty`, `~/.oh-my-zsh`, `~/.cargo` o el
  árbol de Neovim de LazyVim deja esos elementos intactos.
- **No cambia el shell de login.** `--change-shell` es opt-in y está prohibido para
  Server, tanto en `setup.sh` como en la capa privilegiada.

Cuando Server gestiona un archivo que ya existía (por ejemplo `~/.tmux.conf` o
`~/.config/nvim/init.lua`), lo sustituye tras guardar el original en el directorio
de respaldos de la ejecución. Eso es coherente con haber elegido ese perfil; no es
una desinstalación silenciosa.

## Qué hace cada modo

| Modo | Instala paquetes | sudo | Cambia config de usuario | Servicios/hardware |
|---|---|---|---|---|
| `--dry-run` | no | no | no | no |
| `--check` | no | no | no | no |
| `--config-only` | no | no | sí | no |
| instalación normal | sí | una fase | sí | no |
| `--hardware` / `--apply-linux` | según modo | sí | según modo | **sí, opt-in** |
| `--check-sudo` | no | una fase de identidad | no | no |
| `--harden-existing-service` | no | sí, acotado | no | copia root + respaldo |

## Hardware y shell de login: siempre explícitos

Ninguno se aplica por defecto:

```bash
bash setup.sh --profile workstation --hardware        # CPU, memoria, batería 60%
bash setup.sh --profile workstation --apply-linux     # solo esos ajustes
bash setup.sh --profile workstation --change-shell    # shell de login → Zsh
```

Server rechaza las tres opciones en cualquiera de sus capas.

## Verificación

```bash
bash setup.sh --profile server --check
bash setup.sh --profile workstation --check
python3 -B -m unittest discover -s tests -p 'test_profiles.py' -v
```

`--check` es de solo lectura: comprueba herramientas y enlaces de configuración
sin instalar ni escribir nada.

## Límites conocidos

- macOS está cubierto por tests lógicos y por `--dry-run`, pero **no se ha
  instalado en un Mac real** durante esta refactorización; queda en la validación
  de integración.
- Los mínimos de versión se declaran **por perfil** en `installer/components.sh`.
  Neovim exige `>= 0.11` en Workstation (LazyVim) y `>= 0.10` en Server
  (`vim.ui.clipboard.osc52`, con degradación elegante vía `pcall`); un Neovim
  anterior a 0.10 solo pierde el portapapeles OSC 52 sobre SSH.
- `--check` comprueba presencia de ejecutables, no que cada uno funcione en su
  contexto real (por ejemplo que un provider de OpenCode esté autenticado).
- Los paquetes `optional` se intentan instalar solo en Workstation con gestor
  nativo; si la distribución no los publica, se informa y no se aborta.
