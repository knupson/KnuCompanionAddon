# WoW Compañon (addon)

Addon de World of Warcraft: Forever que le pasa a la app de escritorio **WoW Compañon** tus bolsas, banco, equipo, posición, misiones y correo, escribiéndolos en `Logs/General.log`. Solo no muestra nada en el juego: hace falta la app.

- App: repo `knupson/WOWCompanion` (privado por ahora).
- Comandos: `/wowc on`, `off`, `send`, `status`, `gps on`, `gps off`.
- Tests: `luajit tests/run.lua` desde la raíz del repo.

La carpeta del addon en el juego se llama `WOWCompanion` (`.pkgmeta`, `package-as`): la app y las SavedVariables dependen de ese nombre.
