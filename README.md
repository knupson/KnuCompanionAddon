# KnuCompanion (addon)

Addon de WoW Forever que le pasa a la app de escritorio KnuCompanion tus bolsas, banco, equipo, posición, misiones y correo. Los escribe en `Logs/General.log` y la app los lee de ahí. Solo, no muestra nada en el juego.

- App: código en `knupson/WOWCompanion` (privado); descarga en `knupson/KnuCompanion` (público, sólo releases).
- Comandos: `/wowc on`, `off`, `send`, `status`, `gps on`, `gps off`, `app`.
- Tests: `luajit tests/run.lua` desde la raíz del repo.
- Íconos: `python tools/generar_media.py` (necesita Pillow). Genera `media/*.tga` y los PNG de `tools/preview/` para CurseForge.
- Texto de la página de CurseForge: `docs/curseforge.md`.

La carpeta del addon en el juego se llama `WOWCompanion` (`.pkgmeta`, `package-as`). La app, su instalador y las SavedVariables dependen de ese nombre.

## Opiniones y errores

Si te sirve, marcalo como favorito en [CurseForge](https://www.curseforge.com/wow/addons/knucompanion) y dejá un comentario: así lo encuentran otros jugadores de Forever. Las ideas y los pedidos también van en los comentarios. Si encontrás un error, abrí un issue en https://github.com/knupson/KnuCompanion/issues con el texto del error (BugSack lo copia) y qué estabas haciendo.

If you like it, favorite it on CurseForge and leave a comment. Bugs go to https://github.com/knupson/KnuCompanion/issues, with the BugSack text and what you were doing.

## Publicar

Una etiqueta `v*` dispara `.github/workflows/release.yml`, que arma el zip con BigWigsMods/packager y lo sube a GitHub Releases. Para que también suba a CurseForge faltan el secreto `CF_API_KEY` en el repo y `## X-Curse-Project-ID` en `WOWCompanion.toc`. Las notas salen de `CHANGELOG.md`.
