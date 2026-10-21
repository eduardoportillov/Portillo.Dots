# Clipboard: OpenCode, Alacritty y tmux

## Incidente comprobado

En OpenCode V2.0.28, una copia de texto podía terminar correctamente y mostrar
«Copied to clipboard», mientras aparecía este error sobre la interfaz:

```text
Authorization required, but no authorization protocol specified
```

Es un error de acceso a X11, no de autenticación del proveedor de IA. Que aparezca
visualmente sobre el campo de entrada no demuestra que forme parte del texto del
prompt: una salida de error puede interferir con el dibujo de una TUI.

En el host afectado se comprobó:

- Alacritty y los clientes nuevos tenían `DISPLAY`, `XAUTHORITY` y
  `WAYLAND_DISPLAY` correctos.
- Dos clientes anteriores seguían abiertos con un entorno incompleto heredado de
  tmux. Cambiar el entorno de tmux no cambia el de procesos que ya se ejecutan.
- La conexión X11 fallaba con ese entorno antiguo y funcionaba con los metadatos
  de la sesión gráfica actual.
- El usuario dejó de reproducir el mensaje en el cliente nuevo.

No se leyeron contenidos privados del portapapeles ni se imprimieron cookies X11.
No se deshabilitó la autenticación y no fue necesario reiniciar el servicio de
OpenCode, que ya tenía el entorno correcto.

## Prevención y recuperación multihost

`linux/graphical-environment.sh` consulta el gestor de sesión de usuario y emite
únicamente exportaciones escapadas de los metadatos gráficos pertinentes. Valida
la existencia y propiedad del archivo de autorización y del socket Wayland.

El bloque de inicio de `zsh/.zshrc` lo utiliza en **todas las shells locales Linux**,
dentro o fuera de tmux. Comprueba el acceso real con `wl-paste --list-types` y
`xdpyinfo`, conserva un display alternativo si funciona y repara el entorno desde
`systemctl --user show-environment` cuando el heredado está obsoleto. Elimina de la
shell solo las variables de los backends que no logra validar. SSH queda excluido:
no importa el escritorio local sobre X11 forwarding.

No cambia permisos, no obtiene cookies nuevas y no puede reparar procesos Pi que
ya estaban ejecutándose. Tras desplegar los dotfiles, abre una shell nueva y
reinicia Pi cuando sea seguro. Las sesiones tmux restauradas también quedan
cubiertas al crear una shell nueva; los panes/procesos ya existentes deben
reiniciarse individualmente cuando termine su trabajo.

## Recuperar un cliente antiguo sin perder trabajo

1. No cerrar tmux ni interrumpir tareas activas.
2. Abrir una ventana nueva de tmux con `Ctrl+A`, después `C`, y situarse en el
   proyecto correspondiente.
3. En esa shell, comprobar que Wayland/X11 está accesible y volver a iniciar Pi u
   OpenCode solo cuando sea seguro. El cliente antiguo conserva su entorno previo.
4. Cerrar los clientes antiguos únicamente cuando sus tareas hayan terminado.

Si es necesario reutilizar una shell antigua, salir primero del cliente cuando
sea seguro y, desde la raíz de Portillo.Dots, ejecutar:

```bash
eval "$(bash linux/graphical-environment.sh)"
```

Después regresar al directorio del proyecto e iniciar de nuevo el cliente. Una
shell nueva es preferible cuando se acaba de actualizar la configuración.

No usar `xhost +`, copiar cookies entre usuarios ni abrir permisos de
`XAUTHORITY`. En SSH no importar el entorno gráfico local sobre el forwarding.

## Diagnóstico sin leer el portapapeles

Estas comprobaciones solo prueban la conexión gráfica o consultan tipos MIME;
no imprimen el texto o los bytes de la imagen almacenada:

```bash
xdpyinfo >/dev/null
wl-paste --list-types >/dev/null
```

La primera requiere X11/Xwayland; la segunda, Wayland. No se espera que ambas
funcionen en equipos headless, sesiones SSH ni sistemas sin esos backends.

Si el error reaparece, registrar el tipo de sesión, si el cliente era nuevo o
restaurado y si ocurrió al seleccionar, copiar o pegar. No compartir el contenido
del portapapeles, archivos de autorización, credenciales ni logs completos.

## Pruebas y límites de verificación

```bash
python3 -B -m unittest discover -s tests -p 'test_graphical_environment.py' -v
```

Cubren recuperación desde shells normales y tmux, validación de sockets/display,
X11 sin Wayland, gestor de sesión no disponible, y conservación de SSH y displays
alternativos funcionales. No equivalen a automatizar la selección con el ratón en
Pi/OpenCode ni a probar cada host remoto o cada gestor de escritorio.
