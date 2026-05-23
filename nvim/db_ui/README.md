# DB UI (vim-dadbod-ui) local repo storage

Este directorio contiene plantillas y un lugar para guardar queries que serán usadas por vim-dadbod-ui.

- `connections.lua.example` - Template. Copia a `connections.lua` y pon tus URLs reales.
- `queries/` - Lugar donde se guardarán consultas persistentes (git trackeable).

Notas:
- `connections.lua` está en `.gitignore` por seguridad; no lo commitees con credenciales reales.
- Las consultas que guardes desde la UI se escribirán en `nvim/db_ui/queries`.
