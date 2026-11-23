# KNU Companion

Este addon necesita la app de escritorio KNU Companion. Solo, no muestra nada en el juego.

La app la abrís en otro monitor y ahí ves en vivo tus bolsas, el banco, el equipo y el mapa con tu posición mientras jugás.

Descarga de la app: PENDIENTE (URL)

## Qué le pasa a la app

- Bolsas y equipo, con los tooltips del juego.
- Banco, si tenés Syndicator instalado. Sin Syndicator el banco queda vacío.
- Nivel, oro, experiencia, zona y la apariencia del personaje.
- Tu posición en el mapa y las misiones del mapa en el que estás.
- Aviso de correo nuevo, con los remitentes.

El addon escribe estos datos en `Logs/General.log`, dentro de la carpeta del juego, y la app los lee de ahí. El addon no se conecta a internet.

## Si ya tenés la app

La app trae el addon y lo instala con el botón «Instalar addon». No hace falta bajarlo de acá.

## Comandos

- `/wowc off` y `/wowc on`: apagar o prender el envío.
- `/wowc gps off` y `/wowc gps on`: apagar o prender la posición en vivo.
- `/wowc send`: mandar todo de nuevo.
- `/wowc status`: ver si está mandando.
- `/wowc app`: ver de nuevo de dónde se baja la app.

Hecho para WoW Forever. Licencia MIT.
