Dotstack - gestión de dotfiles y componentes

Estructura

~/.dotstack/
  bin/            -> scripts y wrappers (dotstack entrypoint)
  repo/           -> repo clonado con configs/, manifests/, scripts/
  opt/            -> binarios extraídos por versión
  share/          -> clones git y recursos
  backups/        -> backups creados por sync/update
  logs/           -> logs por comando
  state.json      -> estado del sistema

Uso rápido

- dotstack preflight     # comprueba dependencias
- dotstack clone --repo <url>
- dotstack install --yes
- dotstack activate --append --yes
- dotstack sync --dry-run

Ver TESTS.md para checklist de validación.
