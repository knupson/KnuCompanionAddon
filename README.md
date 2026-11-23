# KNU Companion (addon)

Addon de WoW Forever que le pasa a la app de escritorio KNU Companion tus bolsas, banco, equipo, posición, misiones y correo. Los escribe en `Logs/General.log` y la app los lee de ahí. Solo, no muestra nada en el juego.

- App: repo `knupson/WOWCompanion` (privado). La descarga pública está pendiente.
- Comandos: `/wowc on`, `off`, `send`, `status`, `gps on`, `gps off`, `app`.
- Tests: `luajit tests/run.lua` desde la raíz del repo.
- Íconos: `python tools/generar_media.py` (necesita Pillow). Genera `media/*.tga` y los PNG de `tools/preview/` para CurseForge.
- Texto de la página de CurseForge: `docs/curseforge.md`.

La carpeta del addon en el juego se llama `WOWCompanion` (`.pkgmeta`, `package-as`). La app, su instalador y las SavedVariables dependen de ese nombre.

## Publicar

Una etiqueta `v*` dispara `.github/workflows/release.yml`, que arma el zip con BigWigsMods/packager y lo sube a GitHub Releases. Para que también suba a CurseForge faltan el secreto `CF_API_KEY` en el repo y `## X-Curse-Project-ID` en `WOWCompanion.toc`. Las notas salen de `CHANGELOG.md`.
