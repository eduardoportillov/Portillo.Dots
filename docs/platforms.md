# Paquetes, versiones y plataformas

## Plataformas declaradas

| Plataforma | Arquitecturas | Estado |
|---|---|---|
| Linux | x86_64, ARM64 | Comprobada sobre este host; instalación limpia en VM pendiente |
| macOS | Apple Silicon, Intel | Lógica y rutas verificadas con mocks; **instalación real pendiente** |
| Windows | — | No soportado |
| Otros Unix | — | Rechazados en `detect_platform` |

`setup.sh` rechaza explícitamente todo lo que no sea Linux/macOS en x86_64 o
ARM64. Nada más se declara soportado.

## Gestores de paquetes nativos

`installer/privileged-core.sh` cubre tres familias con los nombres correctos de
cada distribución:

| Herramienta | apt (Debian/Ubuntu) | dnf (Fedora) | pacman (Arch) | Ejecutable |
|---|---|---|---|---|
| fd | `fd-find` | `fd-find` | `fd` | `fd` |
| bat | `bat` (alias `batcat`) | `bat` | `bat` | `bat` |
| ripgrep | `ripgrep` | `ripgrep` | `ripgrep` | `rg` |
| Neovim | `neovim` | `neovim` | `neovim` | `nvim` |
| Go | `golang-go` | `golang` | `go` | `go` |
| OpenSSH | `openssh-client` | `openssh-clients` | `openssh` | `ssh` |

Los alias `fdfind→fd` y `batcat→bat` viven en `installer/components.sh`
(`tool_aliases`). El instalador crea un shim en `~/.local/bin` **solo** cuando el
nombre canónico no existe; una entrada que ya posea el usuario nunca se
reemplaza. Si esa entrada existe pero no es ejecutable, se avisa y se deja igual.

`installer/components.sh` es la única fuente de esta tabla y del manifiesto de
herramientas: instalación, resumen y verificación leen lo mismo.

## Versiones mínimas declaradas

Solo se declara un mínimo cuando la configuración gestionada **depende** de esa
sintaxis o API. No se inventan requisitos.

| Herramienta | Mínimo | Por qué |
|---|---|---|
| `tmux` | 3.3 | `allow-passthrough` se añadió en 3.3 y lo usa `tmux/tmux.conf` |
| `nvim` | 0.11 | LazyVim requiere Neovim 0.11 |
| `opencode` | 2.0 | Los dotfiles usan la API y la config nativa de V2 |
| `node` | 20 | Los servidores MCP del template se lanzan con `npx` |
| `alacritty` | 0.13 | La clave `terminal.osc52` existe desde 0.13 |

`--check` y la instalación comparan la versión reportada con el mínimo. Si un
build no expone una versión legible (por ejemplo un bundle de app de macOS), se
informa y no se trata como error.

La comparación (`version_at_least`) es Bash puro: funciona también en macOS, donde
`sort -V` no está garantizado. Los sufijos de proveedor se normalizan
(`tmux 3.6b` → `3.6.0`).

## Rutas por plataforma

| Componente | Linux | macOS Apple Silicon | macOS Intel |
|---|---|---|---|
| Homebrew prefix | `/home/linuxbrew/.linuxbrew` | `/opt/homebrew` | `/usr/local` |
| Zsh | se resuelve por `PATH` | `/bin/zsh` | `/bin/zsh` |
| Alacritty config | `alacritty/alacritty.toml` | `alacritty/alacritty.macos.toml` | igual |
| Zed | CLI del instalador | bundle `Zed.app` | bundle `Zed.app` |

`homebrew_prefix` centraliza esos valores. Si `brew --prefix` no coincide con el
documentado, se avisa sin romper.

### macOS: requisitos y límites

- **Homebrew debe venir preinstalado** con su instalador oficial. El instalador
  no lo clona: hacerlo requeriría `/usr/local` en Intel, que nunca está vacío, y
  daría un prefijo que no podemos verificar en una plataforma sin probar.
- **Apple Command Line Tools son obligatorias** (`xcode-select --install`). El
  preflight las comprueba antes de instalar nada.
- **Una instalación normal de macOS no pide sudo.** Homebrew gestiona los paquetes
  como usuario. Solo `--change-shell` necesita la fase privilegiada; `--hardware`
  y `--harden-existing-service` son exclusivos de Linux.
- Las aplicaciones de escritorio se instalan en `~/Applications`, no en el
  `/Applications` propiedad de root, para no requerir una segunda autenticación.

## Instalación y actualización de toolchains

| Herramienta | Instalación | Actualización (`--upgrade`) |
|---|---|---|
| fnm + Node 24 | instalador oficial, prefijo de usuario | — (ya instalado) |
| pnpm | `npm install -g --prefix ~/.local` | `pnpm self-update` |
| SDKMAN | instalador oficial | `sdk selfupdate` (manual) |
| rustup | instalador oficial, `--no-modify-path` | `rustup update` |
| Go | paquete nativo o brew | según el gestor |
| uv | instalador oficial | `uv self update` |
| markitdown | `uv tool install` | `uv tool upgrade` |

Detalles que evitan trabajo repetido o fallos silenciosos:

- Los targets `wasm32-wasip1/wasip2` de Rust **solo se descargan si faltan**;
  re-ejecutar setup no hace una llamada de red innecesaria.
- `pnpm` se instala resolviendo `npm` de forma explícita, y se comprueba que
  tanto `node` como `pnpm` quedan disponibles; si no, se aborta con un mensaje.
- **El instalador nunca crea un shim ni un alias de `npm`.** El shim legacy del
  repo anterior se respalda y retira; `zsh/.zshrc` ya no define `alias npm=pnpm`,
  de modo que las herramientas externas conservan la semántica real de npm.

## Verificación

```bash
bash setup.sh --profile workstation --check
bash setup.sh --profile server --check
python3 -B -m unittest discover -s tests -p 'test_platforms.py' -v
```

`--check` comprueba presencia, versiones mínimas y enlaces de configuración, sin
instalar ni escribir nada.

## Límites conocidos

- **macOS no se ha instalado en un Mac real** durante esta refactorización. Las
  rutas, la exigencia de Homebrew/CLT y la ausencia de sudo están cubiertas por
  mocks; falta la validación de integración.
- Los nombres de paquetes están verificados contra las tres familias de gestores,
  pero no se ha hecho una instalación limpia en Debian, Fedora y Arch.
- `--check` comprueba presencia y versión, no que cada herramienta funcione en su
  contexto real (por ejemplo que un provider de OpenCode esté autenticado).
- El gate de Alacritty cubre la sintaxis `osc52`, no el bug de OSC 52 en Wayland
  documentado en `TODO.md`; ese sigue abierto.
- Los paquetes `optional` se intentan solo en Workstation con gestor nativo; si la
  distribución no los publica se informa y no se aborta.
