KnuCompanion needs the KnuCompanion desktop app. On its own it shows nothing in game.

Keep the app open on a second monitor and you see your bags, bank, gear and a map with your position, live, while you play.

Get the app: https://github.com/knupson/KnuCompanion/releases/latest

## What it sends to the app

- Bags and gear, with the game's tooltips.
- Bank, if you have Syndicator installed.
- Level, gold, experience, zone and your character's look.
- Your position on the map and the quests of the map you are on.
- Your quest log, with objectives.
- The dungeon or raid you are in, the route of the flight you are on and the durability of your gear.
- Where your Hearthstone is bound and when it is ready again.
- Your professions, weapon skills and languages, with their level.
- Your reputations.
- Your party or raid: class, level, online and dead.
- Your characters on this account, with class, level and gold. Each one shows up after it logs in once.
- The TomTom arrow target, if you have TomTom installed.
- The path to your destination, if you have FarstriderLib or ShortestPathForever installed.
- New mail alert, with the senders.
- Guild, officer, whisper, party, raid and instance chat. General, Trade and the other public channels only if you turn them on.

The addon writes this to `Logs/General.log` in the game folder and the app reads it from there. The addon does not connect to the internet.

If you already have the app, you do not need this page: the app ships the addon and installs it with its "Instalar addon" button.

## Commands

- `/wowc off`, `/wowc on`: stop or resume sending.
- `/wowc gps off`, `/wowc gps on`: stop or resume the live position.
- `/wowc send`: send everything again.
- `/wowc status`: check that it is sending.
- `/wowc chat off`, `/wowc chat on`: stop or resume sending chat.
- `/wowc chat canales on`, `/wowc chat canales off`: add or remove General, Trade and the other public channels.
- `/wowc app`: show where to get the app again.
- `/wowc tipos`, `/wowc tipo <name> off`, `/wowc tipo <name> on`: list what the addon sends and turn one kind of data off or on, for example `alts` or `grupo`.

In game messages are in Spanish for now. Made for WoW Forever. MIT license.

## Feedback and bugs

If you like it, add it to your favorites (the star on this page) and leave a comment. That helps other Forever players find it. Ideas and requests are welcome in the comments.

Found a bug? Open an issue at https://github.com/knupson/KnuCompanion/issues or leave a comment. Paste the error text (BugSack copies it) and say what you were doing.

## En castellano

Este addon necesita la app de escritorio KnuCompanion. Solo, no muestra nada en el juego. La app la abrís en otro monitor y ahí ves en vivo tus bolsas, el banco, el equipo y el mapa con tu posición mientras jugás.

Descarga de la app: https://github.com/knupson/KnuCompanion/releases/latest

Si ya tenés la app, no hace falta bajarlo de acá: la app trae el addon y lo instala con el botón «Instalar addon».

Si te sirve, marcalo como favorito (la estrella de esta página) y dejá un comentario: así lo encuentran otros jugadores de Forever. Las ideas y los pedidos también van en los comentarios.

Si encontrás un error, abrí un issue en https://github.com/knupson/KnuCompanion/issues o dejá un comentario. Pegá el texto del error (BugSack lo copia) y contá qué estabas haciendo.
