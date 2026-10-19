# OpenCode: configuración V2, secretos y sincronización

## Dos archivos con responsabilidades distintas

| Archivo | Contenido | ¿Se sincroniza? |
|---|---|---|
| `opencode/cli.json` | Preferencias del **cliente** de terminal (tema, previews, clipboard) | Sí, sin secretos |
| `opencode/opencode.jsonc` generado | Config del **servidor/proyecto**: agents, MCP, permissions, plugins | Sí, sin secretos |
| `opencode/secrets.env` | Credenciales por host, en formato `export` seguro | **No** — solo en cada host |
| Sesiones y `opencode.db` | Estado local de OpenCode | **No** |

`cli.json` nunca lleva `permissions`, `mcp`, `agents`, `plugins` ni credenciales.
El instalador solo lo crea si no existe y preserva cualquier `cli.json` propio.

## La plantilla usa sintaxis nativa V2

`opencode/opencode.template.jsonc` fue migrada de V1 a V2:

| V1 (antes) | V2 (ahora) |
|---|---|
| `agent` | `agents` |
| `prompt` | `system` |
| `permission` | `permissions` (array `action`/`resource`/`effect`) |
| `mcp` plano | `mcp.servers` |
| `enabled: true` | omitido (`disabled: true` para desconectar) |
| `plugin` | `plugins` |
| `tools` dentro del agente | eliminado; V2 controla acceso con `permissions` |

`render-config.py` **rechaza** cualquier forma V1 al generar: una config que parezca
completa pero se ignoraría en silencio no debe salir del instalador. La validación
cubre claves superiores, campos de agentes, forma de MCP, forma de plugins y reglas
de permisos.

`check-config.py`, en cambio, inspecciona configs **existentes** que pueden seguir
usando sintaxis V1 (OpenCode la normaliza en memoria). Esas formas se reportan como
*notes*, no como error, para no marcar como roto algo que funciona.

## Secretos: nunca dentro de la config

La plantilla referencia credenciales como `{env:NAME}`:

```jsonc
"environment": { "Z_AI_API_KEY": "{env:Z_AI_API_KEY}" },
"headers":     { "Authorization": "{env:Z_AI_API_KEY}" }
```

El archivo generado **no contiene valores de credenciales**, por lo que se puede
respaldar y sincronizar entre hosts. Los valores se entregan en tiempo de ejecución
desde `~/.config/opencode/secrets.env`, que el instalador escribe con modo `0600`
al usar `--opencode-template`.

`opencode/load-secrets.sh` carga ese archivo desde el shell. Es deliberadamente
estricto: **no sourcea** un symlink, un archivo de otro propietario ni uno legible
por grupo/otros. Los valores se emiten como `export KEY=<shell-quoted>`, de modo que
un valor con `$(...)` o backticks se trata como dato y **no se ejecuta**. Borra
`secrets.env` para desactivarlo por completo.

La regla del validador es: una clave con forma de credencial (`key`, `secret`,
`token`, `auth`, `password`, `credential`) o un valor largo y denso que no parezca
URL debe usar `{env:...}`. Literales inocuos como `Z_AI_MODE=ZAI` están permitidos.

## Plugins: compatibilidad V2 verificada

Los plugins V1 **no se ejecutan en V2** (la API cambió; renombrar la entrada no
basta). Comprobado contra el registro npm el 2026-10-16, registrado en
`opencode/plugin-compat.json`:

| Paquete | ¿V2? | Motivo |
|---|---|---|
| `@mohak34/opencode-notifier` | **Sí** | declara `@opencode/plugin >=2.0.18 <3` (API V2) |
| `@franlol/opencode-md-table-formatter` | **No** | exige `@opencode-ai/plugin >=0.13.7` (API V1) |
| `opencode-pty` | **No** | depende de `@opencode-ai/sdk` y `@opencode-ai/plugin` 1.x |

Por eso la plantilla solo lleva `@mohak34/opencode-notifier@^1.1.0`. Los otros dos
fueron retirados: estaban declarados pero **no hacían nada en V2**.

`check-config.py` usa esa tabla: en modo plantilla un plugin V1-only es error; en
una config independiente se reporta como nota. Volver a añadirlos exige que sus
autores publiquen un puerto V2.

## Dependencias MCP

Los servidores `local` arrancan un comando. `--check` avisa si falta en el `PATH`:

- `Vision-Zai` → `npx` (requiere **Node**, ya gateado a `>=20`)
- `engram` → binario `engram` local, que este repo **no instala**

Los servidores `remote` con credenciales por cabecera llevan `oauth: false`; sin
ello OpenCode intentaría OAuth e ignoraría la cabecera. `context7` usa OAuth
(normal) y no lleva cabecera.

## Sincronización entre hosts

La fuente compartida es **este repositorio Git**. El flujo es `git pull` en cada
host y volver a aplicar la config.

**Nunca entra en Git:**
- `opencode/.env` (gitignored) — credenciales por host
- `opencode/secrets.env` (generado, fuera del repo)
- configuración generada `opencode.jsonc`
- sesiones, `opencode.db` y credenciales OAuth de OpenCode

Un test (`test_repo_never_tracks_credentials_or_generated_configs`) impide que
cualquiera de esos nombres se versione por accidente.

### Pasos en un host nuevo

```bash
git clone <repo> && cd Portillo.Dots
cp opencode/.env.example opencode/.env   # rellenar credenciales de ESTE host
bash setup.sh --profile workstation --opencode-template
bash setup.sh --profile workstation --check
```

### Sobre una config independiente existente

El instalador **no sobrescribe** un `opencode.jsonc`/`opencode.json` que no haya
creado él. Para adoptar los cambios sin perder tus ajustes:

1. `bash setup.sh --profile server --dry-run` para ver la lista del perfil.
2. Comparar con `opencode/base.jsonc` + `opencode/server.jsonc` (o la plantilla).
3. Copiar a mano solo las reglas que quieras, en particular los `permissions` de
   Server. La verificación falla si el baseline conservador no está presente.
4. `bash setup.sh --profile <perfil> --check` hasta que pase.

## Verificación

```bash
bash setup.sh --profile workstation --check
bash setup.sh --profile server --check
python3 -B -m unittest discover -s tests -p 'test_opencode_sync.py' -v
```

`--check` valida forma V2, ausencia de secretos literales, baseline de Server,
compatibilidad de plugins y dependencias de comandos MCP.

## Límites conocidos

- La compatibilidad de plugins se comprobó contra el registro npm en una fecha
  concreta; un cambio posterior de esos paquetes no se detecta automáticamente.
- El baseline de Server comprueba la config **instalada**, no la política efectiva
  combinada con configs de proyecto, agentes ni aprobaciones persistidas. No es un
  sandbox.
- `engram` debe instalarse aparte; el instalador solo avisa si falta.
- El template `--opencode-template` sigue siendo **tu** config personalizada (modelo
  `zai-coding-plan/glm-5.1`, agentes `sdd-*`); este repo la hace válida para V2 y
  libre de secretos, pero no garantiza que cada proveedor/modelo esté autenticado.
- La migración V2 de la plantilla no se ha probado contra un servidor OpenCode real
  ejecutando esos MCP; falta la validación de integración.
