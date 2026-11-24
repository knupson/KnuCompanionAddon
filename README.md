# KnuCompanion (addon)

Addon de WoW Forever que le pasa a la app de escritorio KnuCompanion lo que pasa en tu personaje: bolsas, banco, equipo, posición, misiones, chat, grupo y el camino a tu destino, entre otras cosas (lista completa en `docs/protocolo.md`). Los escribe en `Logs/General.log` y la app los lee de ahí. Solo, no muestra nada en el juego.

- App: código en `knupson/WOWCompanion` (privado); descarga en `knupson/KnuCompanion` (público, sólo releases).
- Comandos: `/wowc on`, `off`, `send`, `status`, `gps on`, `gps off`, `chat on`, `chat off`, `chat canales on`, `chat canales off`, `app`, `diag`, `tipos`, `tipo <nombre> on`, `tipo <nombre> off`.
- Opcionales: Syndicator (banco sin abrirlo antes), TomTom (destino de la flecha), FarstriderLib o ShortestPathForever (camino al destino).
- Tests: `luajit tests/run.lua` desde la raíz del repo. Para ver si las pruebas detectan errores: `python tools/mutar.py` (rompe una línea por vez en una copia y espera que cada cambio haga fallar alguna prueba). `python tools/mutar_auto.py` hace lo mismo con todos los operadores de `Core.lua` (unas 1300 mutaciones, alrededor de una hora) y deja las que sobreviven en `%TEMP%/wowc-mutar-auto/vivas.txt`.
- Íconos: `python tools/generar_media.py` (necesita Pillow). Genera `media/*.tga` y los PNG de `tools/preview/` para CurseForge.
- Texto de la página de CurseForge: `docs/curseforge.md`.
- Formato de cada tipo que lee la app: `docs/protocolo.md`.

La carpeta del addon en el juego se llama `WOWCompanion` (`.pkgmeta`, `package-as`). La app, su instalador y las SavedVariables dependen de ese nombre.

## Opiniones y errores

Si te sirve, marcalo como favorito en [CurseForge](https://www.curseforge.com/wow/addons/knucompanion) y dejá un comentario: así lo encuentran otros jugadores de Forever. Las ideas y los pedidos también van en los comentarios. Si encontrás un error, abrí un issue en https://github.com/knupson/KnuCompanion/issues con el texto del error (BugSack lo copia) y qué estabas haciendo.

If you like it, favorite it on CurseForge and leave a comment. Bugs go to https://github.com/knupson/KnuCompanion/issues, with the BugSack text and what you were doing.

## Publicar

Una etiqueta `v*` dispara `.github/workflows/release.yml`: BigWigsMods/packager arma `KnuCompanion-<versión>-forever.zip` (adentro, la carpeta `WOWCompanion`) y lo sube a GitHub Releases y al proyecto 1826508 de CurseForge con el secreto `CF_API_KEY`. Las notas salen de `CHANGELOG.md`.
