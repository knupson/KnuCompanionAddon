KnuCompanion needs the KnuCompanion desktop app. On its own it shows nothing in game.

Keep the app open on a second monitor and you see your bags, bank, gear and a map with your position, live, while you play.

Get the app: https://github.com/knupson/KnuCompanion/releases/latest

## What it sends to the app

- Bags and gear, with the game's tooltips.
- Bank, if you have Syndicator installed.
- Level, gold, experience, zone and your character's look.
- Your position on the map and the quests of the map you are on.
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

In game messages are in Spanish for now. Made for WoW Forever. MIT license.

## En castellano

Este addon necesita la app de escritorio KnuCompanion. Solo, no muestra nada en el juego. La app la abrís en otro monitor y ahí ves en vivo tus bolsas, el banco, el equipo y el mapa con tu posición mientras jugás.

Descarga de la app: https://github.com/knupson/KnuCompanion/releases/latest

Si ya tenés la app, no hace falta bajarlo de acá: la app trae el addon y lo instala con el botón «Instalar addon».
