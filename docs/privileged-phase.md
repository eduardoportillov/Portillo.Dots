# Fase privilegiada: contrato y verificación

## Una autenticación, sin privilegios permanentes nuevos

El instalador propio invoca `sudo` una sola vez por operación privilegiada.
No usa `sudo -v`, keepalive, `sudo -k`, cambios de timeout ni reglas nuevas
`NOPASSWD`. Tampoco captura o guarda la contraseña.

- Si la autenticación ya está en caché, sudo puede no pedir contraseña.
- Con una contraseña correcta y una política local normal, hay una sola
  autenticación. Los reintentos por contraseña incorrecta o los factores de PAM
  pertenecen a la política del sistema: el instalador no los cambia ni vuelve a
  ejecutar sudo tras un fallo.
- El resto de la instalación se ejecuta como el usuario. En macOS los casks de
  aplicaciones apuntan a `~/Applications`, no a `/Applications`.
- Un cask personalizado, una instalación previa con permisos especiales o un
  hook externo puede necesitar una revisión adicional. No se debe conceder una
  segunda elevación ni modificar sudoers para forzar su funcionamiento. La
  validación completa en un Mac real sigue pendiente.

## Cómo se carga el código privilegiado

`privileged_phase` verifica la presencia y sintaxis de los dos archivos que
forman el payload antes de solicitar autenticación. Envía las definiciones de
`installer/privileged-core.sh` y el entrypoint `installer/privileged.sh` por stdin
a `/bin/bash -p -s`.

El modo `-p` impide importar funciones del entorno o ejecutar `BASH_ENV` antes de
las comprobaciones. El entrypoint fija PATH/IFS, elimina variables de arranque,
comprueba UID, usuario invocante, plataforma, perfil y opciones. La llamada final
usa `/dev/null` como stdin para que un comando hijo no consuma el script ni pida
respuestas en ese flujo.

No hay un servicio de elevación persistente, un lector de comandos arbitrarios o
un helper root que apunte continuamente a código modificable por el usuario.
Como cualquier instalador administrativo, se debe ejecutar desde un checkout
confiable, sin ediciones concurrentes. Esto no sustituye el control de acceso
del sistema ni limita las facultades de una cuenta que ya puede usar sudo.

## Copias y retiro de la regla antigua

- Las copias de sistema validan propietarios y permisos de la jerarquía destino.
  No aceptan directorios como destino, incluidos enlaces a directorios, ni un
  padre directo escribible por grupo u otros usuarios.
- Se preserva el archivo original en un respaldo privado. El reemplazo se prepara
  en el mismo filesystem y se publica mediante rename; los enlaces a archivos se
  reemplazan, no se escriben a través de ellos.
- Un archivo previamente escribible por grupo/otros o de otro propietario se
  reemplaza aunque el contenido coincida: `chown/chmod` no revocaría un descriptor
  de escritura que otro proceso ya tuviera abierto sobre el inode antiguo.
- Un fallo o SIGINT/SIGTERM limpia el temporal de copia y conserva originales y
  respaldos. SIGKILL/apagado abrupto puede dejar un temporal o una operación de
  paquetes incompleta; no se afirma que exista rollback automático de paquetes.
- Solo se retira el fragmento legacy que coincide exactamente con la regla
  creada para el usuario invocante. Se valida un comentario con `visudo` y se
  reemplaza atómicamente el contenido, conservando el nombre. Así un `@include`
  explícito no queda apuntando a un archivo ausente. Reglas distintas o enlaces
  se preservan para revisión manual.

## Comprobación real sin instalar ni configurar nada

Desde una terminal propia, como usuario normal:

```bash
bash setup.sh --profile server --check-sudo --dry-run
bash setup.sh --profile server --check-sudo
```

La segunda operación autentica y comprueba la identidad efectiva. No instala
paquetes, cambia sudoers, crea estado del instalador ni configura/reinicia
servicios. Sudo puede actualizar su caché y el registro de auditoría normal del
sistema. La salida esperada incluye `uid=0` y el UID del usuario invocante.

No compartir la contraseña. Solo hace falta registrar si la operación terminó
correctamente y cuántas veces se solicitó autenticación.

## Reparar únicamente el enlace legacy del servicio de hardware

La revisión de solo lectura de este host encontró que:

```text
/usr/local/bin/apply-linux-hardware-settings.sh
  → Portillo.Dots/linux/optimize.sh
```

La unidad instalada coincide con la plantilla versionada, pero ese enlace
permite que cambios posteriores en el repo cambien lo que ejecutará root.
Para corregir exclusivamente ese caso, después de autorizarlo:

```bash
bash setup.sh --profile workstation --harden-existing-service --dry-run
bash setup.sh --profile workstation --harden-existing-service
```

Esta operación verifica la unidad exacta y el enlace esperado, guarda un respaldo
privado y deja una copia regular propiedad de root con modo `0755`. No cambia la
unidad, sudoers, paquetes, CPU, memoria o batería, ni ejecuta el optimizador ni
reinicia el servicio. No requiere daemon-reload porque la unidad no cambia.
Un archivo o una unidad desconocidos se rechazan, no se sobrescriben.

No equivale a `--hardware` o `--apply-linux`, que sí aplican ajustes de hardware.
La reparación existente no debe darse por realizada hasta comprobar que el
destino ya no es un enlace y pertenece a root; el dry-run no lo modifica.

## Pruebas y límites

```bash
python3 -B -m unittest discover -s tests -p 'test_privileged.py' -v
```

Las pruebas de filesystem usan archivos privados temporales y la identidad sin
privilegios del test. Cubren backups, permisos, enlaces, padres inseguros, fallos
de instalación, SIGTERM y retiro de reglas ficticias. Las pruebas de paquetes y
sudo usan dobles; nunca llaman al gestor ni a sudo reales. También comprueban
rechazo de payload inválido, una invocación única, no reintentar tras un fallo y
el modo de comprobación sin crear estado de usuario.

No sustituyen probar PAM/sudo real ni la instalación completa en una VM limpia.
La comprobación de identidad y cualquier reparación real deben registrarse por
separado. Las instalaciones reales Linux/macOS y las interrupciones reales de
gestores de paquetes siguen perteneciendo a la validación de integración.

### Estado de esta revisión (2026-10-16)

- Suite completa: 78 pruebas pasando, incluidas las pruebas aisladas de esta fase.
- Sintaxis Bash/Python y ShellCheck v0.11.0: sin errores en los archivos revisados.
- El usuario ejecutó personalmente la reparación limitada desde su terminal y
  mostró una sola solicitud de contraseña. Se creó el respaldo privado en
  `/usr/local/bin/.portillo-backup.snP2ku20`.
- Se verificó que `/usr/local/bin/apply-linux-hardware-settings.sh` es un archivo
  regular, propiedad de root, con permisos `0755`. La unidad instalada no cambió
  y coincide byte a byte con la plantilla versionada. El servicio no se reinició
  y no se aplicó ajuste de hardware durante esta reparación.
- El directorio de respaldo está protegido con permisos root; no se ejecutó sudo
  adicional ni se leyó su contenido para auditarlo. Su existencia se confirmó
  desde la salida de instalación y mediante un cambio de identidad de usuario,
  que no inspeccionó archivos privilegiados.
