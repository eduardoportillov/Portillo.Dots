Checklist de validación para Dotstack

1) Preflight
   - Ejecutar `dotstack preflight` en un entorno limpio y verificar que reporte dependencias faltantes o "OK".

2) Instalación básica
   - Clonar un repo de ejemplo a `~/.dotstack/repo` o usar `dotstack clone --repo <url>`.
   - Ejecutar `dotstack install --yes` y comprobar que `~/.dotstack/opt`, `~/.dotstack/share`, `~/.dotstack/bin` se poblen según manifests.

3) Sync
   - Colocar archivos en `~/.dotstack/repo/configs` y ejecutar `dotstack sync --dry-run`.
   - Ejecutar `dotstack sync` y comprobar que haga backups y cree symlinks/copies.

4) Update
   - Modificar un manifest (cambiar version) y ejecutar `dotstack update` para verificar el flujo de actualización.

5) Export/Import
   - Ejecutar `dotstack export` y luego `dotstack import <file>` y verificar que la importación solicite revisión.

6) Activate
   - Ejecutar `dotstack activate --append --yes` y verificar que `source ~/.dotstack/activate` se agregue a shells soportados.

Notas
- Las pruebas deben realizarse en Linux y macOS x86_64/aarch64 cuando sea posible.
- Validar que siempre se hagan backups antes de sobrescribir archivos del host.
