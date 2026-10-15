# Cierre de la revisión de cambios pendientes — punto 2

Fecha: 2026-10-14.

Este registro cubre la revisión y separación de los cambios que estaban sin
commit. No certifica la instalación completa ni cierra los siguientes puntos de
la refactorización.

## Cambios revisados y separados

| Commit | Alcance |
| --- | --- |
| `74b1be0` | Instalador: conservar originales de sistema hasta el reemplazo, preservar conffiles de apt, comprobar Neovim y el baseline global de Server, respetar rustup en PATH y limitar los helpers de diagnóstico a Linux. |
| `11dfecb` | GNOME: conservar atajos ajenos, evitar duplicados en las entradas administradas y no desactivar el tiling nativo si o-tiling está inactivo. |
| `e679b39` | Neovim: separar el atajo de DBUI del debugger, conservar valores del dotenv sin ejecutarlos, escapar rutas y cargar OSC 52 con fallback. |
| `ce2a2ac` | Shell/tmux: ordenar memoria con comandos portables y seleccionar un backend de copia disponible, con fallback sin escritorio. |
| `63bead7` | Lint y diagnóstico: documentar globals compartidas, declarar el dialecto del fragmento de shell y mostrar rutas explícitas. |

Los cambios de recuperación gráfica y el arreglo de Alacritty ya tenían sus
propios commits y no se mezclaron nuevamente con estos grupos.

## Verificación de las dependencias entre commits

Antes de cada commit de código se exportó únicamente el índice de Git a un
directorio temporal, sin ocultar, revertir ni modificar los cambios restantes.
Se ejecutó la suite desde esa copia, no desde el árbol de trabajo completo:

| Grupo preparado | Pruebas pasando en la copia del índice |
| --- | ---: |
| Instalador | 41 |
| GNOME | 46 |
| Neovim | 50 |
| Shell/tmux | 52 |
| Lint y diagnóstico | 52 |

Así se comprobó que los nuevos archivos necesarios, como
`opencode/check-config.py`, se incluyen junto a sus consumidores y pruebas, sin
depender accidentalmente de archivos aún sin commit.

## Qué comprueban las pruebas

- Validación de perfiles, preservación de configuraciones y enlaces, y detención
  ante un fallo de sudo simulado.
- Baseline global explícito de permisos Server, precedencia de reglas y errores
  de JSONC sin exponer fragmentos de configuración.
- Gate de versión de Neovim y selección lógica de configuración Linux/macOS con
  HOME temporal.
- Manipulación de atajos de GNOME con comandos simulados, nunca con el dconf real.
- Compilación de los Lua versionados y comportamiento del debugger/clipboard con
  dependencias simuladas, sin instalar plugins.
- Selección de clipboard en servidores tmux con sockets privados de prueba.
  Los comandos de clipboard son dobles que detectarían una ejecución inesperada;
  las pruebas no leen ni escriben el portapapeles real.
- Orden numérico y límite de resultados de `memtop` con procesos simulados.

Los scripts revisados también pasan ShellCheck v0.11.0 a nivel `warning`. El
validador se descargó temporalmente y se verificó su SHA-256 publicado antes de
ejecutarlo; no se instaló ningún paquete del sistema.

## Límites y trabajo que sigue pendiente

- No se ejecutaron instalaciones, sudo real, gestores de paquetes, cambios de
  servicios, ajustes de hardware ni despliegues a `.2`.
- La comprobación de OpenCode es un baseline local explícito. No evalúa la
  configuración efectiva combinada con proyectos, agentes, plugins o aprobaciones
  persistidas; no es un sandbox ni una auditoría completa de permisos.
- La prueba lógica de macOS no sustituye una instalación en un Mac. Tampoco se
  validó una instalación limpia en una VM Linux.
- Los dobles de GNOME y Neovim no equivalen a probar toda la sesión gráfica o
  todos los plugins reales, ni a migrar exhaustivamente configuraciones legacy.
- La comprobación real tras reiniciar y restaurar tmux sigue pendiente, como se
  detalla en [clipboard.md](clipboard.md).
- La fase privilegiada y su única autenticación necesitan la validación real del
  punto 3, que no se ha iniciado durante este trabajo.
