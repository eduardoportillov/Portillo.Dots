# Rendimiento: mediciones y optimizaciones

Todas las cifras son medianas sobre este host (Linux x86_64, Zsh de Linuxbrew).
Sirven para justificar qué se optimiza, no como objetivo universal.

## Medidas

### Arranque de shell

| Escenario | Mediana |
|---|---:|
| `zsh -f` (sin rc) | 1.0 ms |
| `zsh -i` con el `.zshrc` completo | 118–126 ms |
| `zsh -i` dentro de tmux (activa el helper gráfico) | 118–126 ms |

**La recuperación gráfica no ralentiza el shell** (diferencia dentro del ruido).
El coste del `.zshrc` viene de Oh My Zsh + Powerlevel10k + plugins, no del helper.

Contribución aislada de los helpers al arranque:

| Helper | Coste |
|---|---:|
| `linux/graphical-environment.sh` | 6.1 ms |
| `opencode/load-secrets.sh` | 1.3 ms |
| `systemctl --user show-environment` (dentro del anterior) | 3.6 ms |

Y cuando no hay nada que hacer no se ejecutan: fuera de tmux **no se consulta** la
sesión gráfica, y sin `secrets.env` no se lanza ningún proceso auxiliar. Dos tests
lo aseguran.

### Modos del instalador

| Modo | Antes | Después |
|---|---:|---:|
| `--help` | 6.9 ms | 6.9 ms |
| `--dry-run` | 11–13 ms | 11–13 ms |
| `--check` (frío) | 138 ms | 138 ms |
| `--check` (repetido) | 138 ms | **40 ms** |
| `--config-only` | 244 ms | 229 ms |

### Dónde se iba el tiempo en `--check`

| Parte | Coste |
|---|---:|
| `detect_platform` + iteración del manifiesto | 11.1 ms |
| `tool_executable` × 14 | 6.2 ms |
| **`tool_version` × 3** | **77 ms** |
| `verify_configs` | 13.0 ms |

Sondas individuales de versión:

| Herramienta | Coste |
|---|---:|
| `opencode --version` | **71.2 ms** |
| `curl --version` | 5.3 ms |
| `nvim --version` | 3.0 ms |
| `tmux -V` | 1.2 ms |
| `git --version` | 1.0 ms |

`opencode --version` concentraba casi todo el coste.

## Optimizaciones aplicadas

### 1. Caché de versiones de herramientas

`tool_version` cachea la respuesta en
`~/.cache/portillo-dots/tool-versions.tsv`, con clave
`herramienta|ruta|mtime:tamaño`. Un upgrade del binario cambia mtime/tamaño y
invalida la entrada automáticamente. Es la optimización que llevó `--check` de
138 ms a **40 ms** en repeticiones.

La caché no contiene credenciales (solo nombres, rutas y versiones), se escribe
con modo `0600` y es dato derivado: los modos de consulta pueden poblarla sin
que eso cuente como escritura de configuración o estado.

### 2. Una sola consulta por gestor de paquetes

- `install_brew_tools` hacía `brew list --versions <pkg>` **una vez por paquete**
  (~18 invocaciones). Ahora hace **una** consulta masiva y parsea el resultado.
- El bucle de casks de macOS hacía `brew list --cask <app>` por app. Ahora una
  consulta `brew list --cask --versions`.
- `rustup target list --installed` se ejecutaba **dos veces** (una por target).
  Ahora una, y ambos targets se evalúan contra esa lista.
- `install_opencode` llamaba `opencode --version` hasta dos veces. Ahora una.

### 3. Un solo proceso Python para verificar OpenCode

`verify_configs` lanzaba `check-config.py` y después `verify_opencode_dependencies`
— dos arranques de Python (~34 ms solo el arranque). Ahora `check-config.py --deps`
cubre forma V2, baseline de Server, secretos **y** dependencias MCP en una sola
invocación.

### 4. Paralelismo: medido, no aplicado

Se comparó ejecutar las 3 sondas de versión en serie vs en paralelo:

| Estrategia | Coste |
|---|---:|
| serie | 74.7 ms |
| paralelo | 70.5 ms |

La diferencia es mínima porque **una sola llamada** (`opencode --version`) domina.
Paralelizar aquí añadiría complejidad sin ganancia real. La caché es la respuesta
correcta.

## Qué NO se hizo

- No se tocó el `.zshrc` para acelerar el arranque: 118 ms es el coste de Oh My
  Zsh + Powerlevel10k, una elección consciente. Si llega a molestar, la palanca
  sería revisar los plugins de OMZ, no los helpers de este repo.
- No se eliminó ninguna comprobación de integridad ni de seguridad para ganar
  velocidad: la caché de versiones no reemplaza SHA-256, ni los gates de versión.
- No se paralelizaron instalaciones: la mayoría dependen de un gestor de paquetes
  con su propia serialización.

## Pruebas de regresión

```bash
python3 -B -m unittest discover -s tests -p 'test_performance.py' -v
```

Aseguran **estructura**, no tiempo de pared (que varía con la carga del runner):

- una versión cacheada no vuelve a lanzar la herramienta
- cambiar el binario invalida la entrada
- sin versión parseable no se escribe caché
- la caché es `0600` y no contiene material de credenciales
- brew se consulta **una** vez por ejecución, no una por paquete
- `rustup target list` se consulta **una** vez
- las comprobaciones de OpenCode usan **un** proceso Python
- fuera de tmux no se consulta la sesión gráfica
- sin `secrets.env` el cargador no lanza ningún proceso

## Límites conocidos

- Las mediciones son de este host y de una ejecución concreta; sirven para
  comparar antes/después, no como SLA.
- La caché de versiones asume que el binario cambia de mtime o tamaño al
  actualizarse. Un replace in-place idéntico en ambas no invalidaría la entrada.
- `--config-only` sigue siendo el modo más caro (~230 ms) porque arranca Python
  dos veces (render + check) y escribe varios enlaces; no se optimizó al no ser
  un camino caliente.
- No se midió una instalación completa con red: los gestores de paquetes dominan
  ese caso y su coste depende del mirror, no de este repo.
