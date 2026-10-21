# Perfiles: componentes exactos y límites

## Los dos perfiles

`setup.sh` instala **dos perfiles**, no dos versiones de OpenCode:

| | **Dev Workstation** | **Remote Server** |
|---|---|---|
| Comando | `bash setup.sh --profile workstation` | `bash setup.sh --profile server` |
| Objetivo | Entorno completo de desarrollo | Administración y trabajo por SSH |

## La base compartida: todo host se siente como el mismo host

`shared/` es el baseline que todos los contextos consumen, para que una
workstation, un server instalado y un runtime `remote.sh` sean indistinguibles
en el uso diario:

| Base | Contenido | Consumidores |
|---|---|---|
| `shared/shell/common.sh` | Aliases, `memtop`, `EDITOR/VISUAL`, colores Kanagawa, PATH del usuario, fnm bajo demanda, **PS1 Kanagawa** | `zsh/.zshrc`, `server/shell.sh`, `remote/generate-rc.sh` |
| `shared/tmux/base.conf` | Prefix `C-a`, splits, índices, copy-mode con backends de clipboard, popup scratch, status Kanagawa | `tmux/tmux.conf` (+ plugins), `server/tmux.conf`, generación del tmux remoto |
| `shared/nvim/base.lua` | Opciones, leader, keymaps base, OSC 52 copy-only sobre SSH | `nvim/lua/config/options.lua` en ambos perfiles y runtimes |

Ambos perfiles despliegan **el árbol completo `nvim/`**, LazyVim, sus extras,
el mismo `lazy-lock.json` y Kanagawa Dragon. El servidor también recibe los
plugins interactivos de tmux y su tema por defecto; únicamente la persistencia
(resurrect/continuum/autoboot) queda fuera. **El prompt es literalmente el mismo
en todos los host**: `zsh/.zshrc` + `zsh/p10k.zsh` (Powerlevel10k) se instalan y
enlazan en cada perfil, con la paleta Kanagawa Dragon compartida con el status de
tmux (`#8ba4b0`, `#c5c9c5`); el PS1 compartido queda como fallback para sesiones
bash. Como el login shell solo cambia con `--change-shell` (opt-in para ambos
perfiles), un host puede seguir entrando en bash con la misma identidad visual.

`setup.sh` despliega las bases en `~/.config/portillo-dots/`
(`shell-common.sh`, `tmux-base.conf`, `nvim-base.lua`) y `remote.sh` lleva el
mismo árbol dentro del runtime.

Los contextos **no** pueden redefinir la superficie compartida: un test lo
vigila (`SharedBaselineTests`).

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

### Server — 16 herramientas requeridas

```text
git curl ssh rsync tmux nvim rg fd fzf bat jq htop python3 zsh opencode pi
```

Sin escritorio ni instaladores de apps gráficas. Incluye soporte de compilación
para Tree-sitter y el runtime Node necesario para Pi; no instala la pila completa
de toolchains de Workstation.
`zsh` es la identidad de shell compartida (mismo prompt en todos los host).

### Workstation — 24 requeridas + 4 opcionales

Requeridas (las 16 anteriores, más):

```text
node pnpm go rustup uv claude zed alacritty
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
- **Preserva las herramientas ajenas al perfil.** No borra `~/.config/zed`,
  `~/.config/alacritty`, `~/.oh-my-zsh` ni `~/.cargo`. Neovim y tmux sí son
  configuraciones gestionadas en ambos perfiles: se reemplazan con respaldo.
- **No cambia el shell de login por su cuenta.** `--change-shell` sigue siendo
  **opt-in explícito** para ambos perfiles (incluido Server, donde la paridad de
  prompt con el resto de host lo justifica); nada se ejecuta sin esa flag.
  Los ajustes de hardware siguen **prohibidos** para Server.

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
bash setup.sh --profile server --change-shell         # idéntico en el server
bash setup.sh --profile server --timezone America/La_Paz # zona horaria del sistema
```

Server rechaza `--hardware` y `--apply-linux` en cualquiera de sus capas.
`--change-shell` vale para ambos perfiles porque la premisa es que todos los
host se sientan igual, pero **solo** con la flag explícita.
`--timezone IANA` también es explícita, solo Linux, valida el nombre contra
`/usr/share/zoneinfo` y aplica el cambio en la única fase privilegiada.
En Server, Kanagawa, segmentos git/CPU/RAM y plugins interactivos son el valor
por defecto. `--tmux-visual` se conserva como flag de compatibilidad; ya no hace
falta. No habilita resurrección de sesiones, servicios ni autoboot.

En la consola física Linux (`TERM=linux`), Zsh omite el *instant prompt* y
Powerlevel10k porque la fuente bitmap del kernel no incluye los glifos Nerd
Font. Usa el mismo orden user/host/ruta y la hora, con colores ANSI básicos y
sin iconos corruptos. SSH, tmux y terminales gráficos conservan el prompt
Powerlevel10k completo. Instalar una Nerd Font de usuario no cambia la fuente
del kernel: TTF/OTF es para emuladores gráficos; la consola requiere fuentes
bitmap y no puede representar todo el set de glifos de Powerlevel10k.

## Verificación

```bash
bash setup.sh --profile server --check
bash setup.sh --profile workstation --check
python3 -B -m unittest discover -s tests -p 'test_profiles.py' -v
```

`--check` comprueba herramientas, todos los enlaces de Neovim y plugins de tmux.
Para Neovim valida el recibo de un arranque real exitoso: hashes de configuración,
revisiones Git de los plugins activos y carga real del tema Dragon. Ejecuta
Neovim con `-u NONE`, sin hooks de inicio, descargas ni reparación; los archivos
temporales de diagnóstico se eliminan. Si falta el recibo, ejecuta setup normal.
La instalación restaura los plugins desde el lockfile y genera ese recibo solo
si pasan las comprobaciones. `--config-only` no descarga plugins ni certifica
que estén instalados. La segunda instalación evita restaurar si todo coincide.

## Límites conocidos

- macOS está cubierto por tests lógicos y por `--dry-run`, pero **no se ha
  instalado en un Mac real** durante esta refactorización; queda en la validación
  de integración.
- Los mínimos se declaran en `installer/components.sh`: Neovim exige
  `>= 0.11.2` en ambos perfiles por la revisión fijada de LazyVim.
- `--check` comprueba presencia de ejecutables, no que cada uno funcione en su
  contexto real (por ejemplo que un provider de OpenCode esté autenticado).
- Los paquetes `optional` se intentan instalar solo en Workstation con gestor
  nativo; si la distribución no los publica, se informa y no se aborta.
