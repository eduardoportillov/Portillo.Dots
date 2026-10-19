# Seguridad de configuración, logs y respaldos

## Modelo de permisos

Todo lo que puede contener credenciales pertenece únicamente a su propietario:

| Ruta | Modo | Por qué |
|---|---|---|
| `opencode/.env` | `0600` | credenciales por host |
| `opencode/opencode.jsonc` | `0600` | generada; aunque no lleva valores, se trata como sensible |
| `~/.config/opencode/secrets.env` | `0600` | exporta las credenciales en tiempo de ejecución |
| `~/.local/state/portillo-dots/` | `0700` | logs, respaldos y descargas temporales |
| `~/.local/state/portillo-dots/setup.log` | `0600` | la salida de instaladores externos puede ser impredecible |
| respaldos (`backup.*`) | `0700` | contienen los archivos que se reemplazaron |

`secure_file` / `secure_dir` **solo aprietan**, nunca amplían: si el archivo ya es
`0400` no se cambia a `0600`. Nunca atraviesan un symlink y nunca tocan un archivo
de otro propietario. Un symlink en una ruta de credenciales se **reporta y se
rechaza**, no se sigue.

La comprobación vive en `verify_secret_permissions` y forma parte de `--check`:
informa cualquier ruta de credenciales accesible por grupo u otros. La corrección
(`secure_known_secrets`) solo ocurre al aplicar configuración, no durante `--check`.

**Hallazgo corregido:** al iniciar este punto, `opencode/.env`,
`opencode/opencode.jsonc` y `logs/` tenían modo `0664`/`0775` — legibles y
editables por el grupo. Ya fueron restringidos a `0600`/`0700`, y el instalador
ahora lo garantiza en cada ejecución.

## Escaneo de secretos

La comprobación de nombres por sí sola no basta; se escanea el **contenido**:

```bash
python3 -B -m unittest discover -s tests -p 'test_security.py' -v
```

El escaneo cubre:

- **Archivos versionados**: 120 archivos.
- **Historial de Git**: todos los blobs cuyo nombre coincide con patrones sensibles
  (`.env`, `secret`, `credential`, `opencode.jsonc`, `.pem`, claves SSH, `.key`).
- **Patrones**: AWS (`AKIA…`), GitHub (`ghp_…`, `github_pat_…`), OpenAI/Anthropic
  (`sk-…`), Slack (`xox…`), Google (`AIza…`), Stripe live, JWT, bloques
  `BEGIN PRIVATE KEY` y asignaciones tipo `api_key/token/authorization` con valores
  densos.
- **Entropía**: asignaciones de credenciales con valores de alta entropía.

Los placeholders (`{env:…}`, `{{VAR}}`, `example`, `fake`, `do-not-…`) se excluyen
para no generar ruido.

**Resultado de la ejecución de este punto:** 120 archivos versionados y 830 blobs
de historial inspeccionados, **cero hallazgos**. Los tres tests del escaneo son
permanentes: un secreto añadido por accidente rompe la suite.

## Respaldos

### Dónde quedan

```text
~/.local/state/portillo-dots/
├── setup.log                     0600
├── backup.<aleatorio>/           0700  ← respaldos de ESTA ejecución
│   └── home/<usuario>/...               ← copia con la ruta absoluta original
└── setup.<aleatorio>/            0700  ← descargas temporales (se borran al salir)
```

Las copias de sistema con privilegios van aparte, en
`/usr/local/bin/.portillo-backup.<aleatorio>/` o el directorio equivalente,
propiedad de root.

### Por qué no hay colisiones

El destino del respaldo **refleja la ruta absoluta** del original
(`~/.zshrc` → `backup.XXXX/home/user/.zshrc`), no solo su nombre base. Dos
`settings.json` de directorios distintos nunca colisionan. Si el destino ya existe,
`backup` **detiene la ejecución** con `Backup collision` en lugar de sobrescribir;
el origen queda intacto.

### Cómo recuperar

No hay un "deshacer todo": borrar trabajo posterior sería más dañino que el
problema. La recuperación es manual y selectiva:

```bash
# 1. Localizar el respaldo de la ejecución que te interesa
ls -1 ~/.local/state/portillo-dots/

# 2. Ver qué contiene, sin tocar nada
find ~/.local/state/portillo-dots/backup.* -type f -o -type l

# 3. Comparar antes de decidir
diff ~/.zshrc ~/.local/state/portillo-dots/backup.XXXX/home/$USER/.zshrc

# 4. Restaurar SOLO el archivo concreto
cp -a ~/.local/state/portillo-dots/backup.XXXX/home/$USER/.zshrc ~/.zshrc
```

Para los respaldos root:

```bash
sudo find /usr/local/bin/.portillo-backup.* -type f -o -type l
sudo cp -a /usr/local/bin/.portillo-backup.XXXX/<archivo> <destino>
```

Los respaldos **no se limpian automáticamente**: son la única red de recuperación.
Bórralos a mano cuando hayas confirmado que la instalación es estable.

## Preservación ante fallos

- Una **generación de configuración fallida** conserva el archivo anterior y no
  deja staging: se escribe en un temporal y se publica con `os.replace`.
- Un **respaldo rechazado** deja el origen intacto.
- `cleanup_setup` borra únicamente el directorio temporal `setup.*`; **nunca**
  toca respaldos, logs ni estado.
- Las copias de sistema con privilegios se preparan en el mismo filesystem y se
  publican por rename; un `SIGINT`/`SIGTERM` limpia el temporal y conserva
  originales y respaldos. `SIGKILL` o un apagado abrupto pueden dejar un temporal
  huérfano; no se afirma rollback automático de paquetes.

## Logs

La salida de los instaladores externos se redirige a `setup.log` (`0600`) porque
no controlamos lo que imprimen. Lo que **sí** controlamos nunca escribe valores de
credenciales: el renderizador de OpenCode no las imprime, y el generador de
`secrets.env` no las vuelca a stdout. Un test verifica que un valor de `.env` no
aparezca en el log ni en la salida de la instalación.

## Límites conocidos

- El escaneo usa patrones y entropía, no un detector de secretos comercial como
  gitleaks. Puede no detectar un secreto con un formato desconocido o un valor
  corto y poco característico.
- No se ha ejecutado el escaneo sobre **todo** el contenido de todos los blobs del
  historial, solo sobre los que llevan nombres sensibles. Es una decisión de
  coste/riesgo: los archivos sin nombre sensible y con contenido secreto quedarían
  fuera.
- Los permisos se comprueban sobre los paths conocidos. Un archivo de credenciales
  fuera de esa lista no se detecta automáticamente.
- No se auditaron los respaldos root existentes de hosts reales; su contenido no
  se inspeccionó.
- La limpieza de respaldos es manual por diseño; no hay política de retención.
