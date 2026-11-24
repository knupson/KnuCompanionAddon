# Changelog

## 0.15.3

- Los errores se reportan en el repo del addon, que ahora es público: https://github.com/knupson/KnuCompanionAddon/issues
- La página del addon apunta a la web de la app: https://companion.knunet.com
- Al pie de la ayuda (`/wowc` sin nada) figura dónde ver los otros addons de KNU.

## 0.15.2

- La app ve tu banco aunque no tengas Syndicator: alcanza con abrirlo una vez con cada personaje.
- La app dibuja el camino hasta tu destino (la flecha de TomTom o el punto que marcás en el mapa) con el próximo paso. Lo calcula FarstriderLib y, si no lo tenés, ShortestPathForever.
- Datos nuevos para la app: piedra de hogar (dónde está atada y cuándo vuelve a estar lista), profesiones, reputaciones, integrantes del grupo o la banda, monedas, mejoras activas (fuera de combate), estado JcJ de la zona, hora del próximo reinicio diario y semanal, tu blanco actual, quién de tu hermandad está conectado, las recompensas de tus misiones, puntos de talento sin gastar, experiencia descansada y tus personajes con su oro. Cada personaje aparece después de conectarse una vez con esta versión.
- Cuando morís, la app sabe dónde quedó tu cuerpo y si ya sos fantasma.
- `/wowc tipo <nombre> off` deja de mandar ese dato, por ejemplo `alts` o `grupo`. `/wowc tipos` muestra cuáles están apagados.
- `/wowc status` muestra de dónde salió la última ruta y cuánto tardó en calcularse.
- `/wowc diag` muestra cuándo se mandó cada dato por última vez y cuánto pesaba.
- Si un dato falla al armarse, los demás se siguen mandando y `/wowc status` dice cuál falló.
- Una vez por cuenta, un mensaje en el chat dice dónde dejar un comentario o reportar un error. También aparece al pie de la ayuda de `/wowc`.

## 0.15.1

- La app sabe en qué mazmorra o banda estás, para abrir su mapa sola.
- Al tomar un vuelo, la app recibe la ruta hasta el destino.
- La app recibe la durabilidad del equipo, para avisarte cuándo reparar.
- El nombre se escribe KnuCompanion, como los otros addons Knu. La carpeta sigue siendo `WOWCompanion`.

## 0.15.0

- La app recibe el chat de hermandad, oficiales, susurros, grupo, banda y estancia. General, Comercio y los demás canales sólo con `/wowc chat canales on`. `/wowc chat off` lo corta.

## 0.14.0

- La app recibe el registro de misiones completo, con la categoría, el nivel, si está lista o fallida y los objetivos.

## 0.13.0

- El addon pasa a llamarse KNU Companion. La carpeta sigue siendo `WOWCompanion`.
- La primera vez que entrás al juego, un mensaje en el chat avisa que hace falta la app de escritorio y de dónde se baja. `/wowc app` lo repite.
- Ícono en la lista de addons.
- Si usás TomTom (o una guía que lo usa, como WoWPro), la app recibe el destino de la flecha: mapa, coordenadas y título.

## 0.12.0

- Misiones del mapa actual con sus objetivos, y la misión seguida.
- Aviso de correo nuevo con los remitentes.
