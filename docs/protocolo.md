# Protocolo addon → app

El addon escribe líneas en `Logs/General.log` con `C_Log.LogMessage` y la app las lee de ahí. Este documento describe lo que sale hoy de `Core.lua` y `Proto.lua`; si no coinciden, manda el código.

## Líneas

```
KC1|sid|seq|parte|total|tipo|datos
```

- `sid`: 8 dígitos hexadecimales, nuevo en cada carga de la interfaz.
- `seq`: número de envío, sube de a uno dentro de la sesión.
- `parte` y `total`: una foto puede ocupar hasta 64 líneas de unos 3900 bytes. Pegando `datos` de las partes 1 a `total` en orden se recupera la foto completa.
- `tipo`: minúsculas, hasta 16 letras.
- `datos`: `encabezado#registro;registro;…`. Sin registros queda `encabezado#`.

Después de cada tanda van 12 líneas `KCP` + 4086 `x`, para que el juego vuelque el log al disco. Una tanda que sólo trae `pos` lleva relleno nada más si la posición cambió desde el último volcado y pasó el intervalo `VOLCADO_GPS` de `Core.lua`.

### Escape

Texto libre (nombres, títulos, zonas) va escapado con `\`:

| Carácter | Escrito |
|---|---|
| `\` | `\\` |
| `|` | `\p` |
| `;` | `\s` |
| `,` | `\c` |
| `#` | `\h` |
| CR | `\r` |
| LF | `\n` |

El `:` no se escapa. En los tipos que separan campos con `:`, el texto va siempre último.

### Valores secretos y vacíos

Un valor que el juego marca como secreto, o que no se pudo leer, va como campo vacío. Una foto que todavía no se puede armar (por ejemplo, el banco antes de que Syndicator esté listo) no se manda y se reintenta hasta 3 veces cada 2 s.

### Cuándo se manda

Cada tipo se pide con un evento del juego, pasa por un antirrebote común y se manda sólo si cambió respecto del último envío exitoso. `/wowc send` manda todo de nuevo. El jugador puede apagar un tipo con `/wowc tipo <nombre> off` (todos menos `hello`); un tipo apagado deja de mandarse sin aviso.

## Tipos anteriores a 0.15.1

Los arma cada función de `Core.lua`: `bags` (`Bolsas`), `bank` (`Banco`), `equip` (`Equipo`), `char` (`Personaje`), `look` (`Look.lua`), `hello` (`Hello`), `pos` (`Posicion`), `quest` (`Misiones`), `mail` (`Correo`), `dest` (`Destino`), `log` (`Registro`), `chat` (`Chat`).

`bank` desde 0.15.2 no depende de Syndicator: con el banco abierto, el addon lee las pestañas del personaje (`C_Bank.FetchPurchasedBankTabData`) y las guarda en `WOWCompanionDB.bancos`. Si Syndicator está y tiene el banco, se usa Syndicator; si no, esa copia; sin copia, `nodata`. Ya no sale `nosyn`. El formato de `ok` y de los registros no cambió.

`hello` sumó dos campos en 0.15.2: `versión,interfaz,tipos,apagados`, con `tipos` = los tipos que manda esta versión y `apagados` = los que apagó el jugador, separados por espacio. Se reenvía al apagar o prender un tipo.

`char` sumó dos campos al final en 0.15.2: el 14 es la experiencia descansada (`GetXPExhaustion`, vacío sin descanso) y el 15 es `1` o `0` según `IsResting`.

### tip

Tooltips de los objetos que aparecen en `bags`, `bank` y `equip`. Encabezado vacío; un registro por línea del tooltip, hasta 30:

```
clave,línea,total,textoIzquierda,textoDerecha,colorIzquierda,colorDerecha
```

- `clave`: `idioma|item:…` (el idioma del cliente y el itemString del enlace), escapada. Es el mismo valor que va en el campo `tip` de los registros de `bags`, `bank` y `equip`, sin el idioma. Hay una foto `tip` por objeto.
- `línea` y `total`: número de línea desde 1 y cantidad de líneas.
- Los textos van escapados y recortados a 200 bytes. Los colores son `RRGGBB` en hexadecimal, o vacío.

Se lee con `C_TooltipInfo` (`GetBagItem`, `GetInventoryItem` o `GetHyperlink` según de dónde salga el objeto). Cada tooltip se manda una vez por día y por versión del addon (se recuerda en `WOWCompanionDB.tipsEnviados`; `/wowc send` vacía esa memoria). Una tanda lleva hasta 12 líneas de tooltips; lo que no entra espera la tanda siguiente. Un tooltip que no se pudo leer se reintenta 3 veces cada 2 s.

## Tipos nuevos

### inst (0.15.1)

`instanceID,tipo,nombre#`. Fuera de una instancia: `,none,#`. Con el tipo secreto: `,,#`. Se manda con cada `ZONE_CHANGED*`.

### taxi (0.15.1)

`uiMapID,destino#nodeID:x:y;…`, con los nodos del vuelo desde el origen hasta el destino. Al aterrizar, o si el vuelo no arranca en 10 s: `,#`. El juego no da el tiempo que falta.

### dur (0.15.1)

`slot:actual:máximo;…#`, sólo con los slots 1 a 19 que tienen durabilidad. Sin nada: `#`. Se manda con `UPDATE_INVENTORY_DURABILITY` y `PLAYER_EQUIPMENT_CHANGED`.

### ruta (0.15.2)

Encabezado `destino,segundosTotales,fuente`, con `fuente` igual a `fsl` (FarstriderLib) o `spf` (ShortestPathForever). Sin ruta: `,,#`.

Registros de tramo, 9 campos separados por `:`:

```
modo:mapa1:x1:y1:mapa2:x2:y2:segundos:texto
```

- `modo` con `fsl`: `walk`, `flight`, `portal`, `boat`, `zeppelin`, `item`, `spell`, `leave` (salir de la instancia) o `tram`. Con `spf`, los modos de su API.
- Con `fsl`, la punta 1 es dónde se hace el paso y la punta 2 dónde termina.
- Coordenadas 0–1 con 4 decimales. Una punta que no se pudo ubicar va con sus tres campos vacíos.
- Hasta 30 tramos.

Registros de punto, sólo con `fsl`, después de los tramos y en orden: `punto:mapa:x:y`. Son los nodos del camino completo, hasta 200.

El destino sale de la flecha de TomTom, del punto marcado en el mapa (`C_Map.GetUserWaypoint`) o de la meta del viaje de ShortestPathForever. Se recalcula al cambiar el destino, al entrar a otra zona (`ZONE_CHANGED_NEW_AREA`), cuando FarstriderLib reconstruye su grafo y con los avisos `started`, `changed`, `ended`, `leg` y `replan` de ShortestPathForever. Nunca en cada curva. Con FarstriderLib no se calcula en combate: se calcula al salir (`PLAYER_REGEN_ENABLED`).

### hogar (0.15.2)

`posada,listaEpoch,piedra#`

- `listaEpoch`: hora del servidor (`GetServerTime`) en que la piedra vuelve a estar lista, redondeada a 10 s; `0` si ya está lista.
- `piedra`: `1` si está en las bolsas, `0` si no.

Se manda con `HEARTHSTONE_BOUND` y `BAG_UPDATE_COOLDOWN`.

### skill (0.15.2)

`plegadas#skillID,categoriaID,categoria,nombre,nivel,máximo,modificador;…`

Mismo filtro que la ventana de habilidades de Forever: sólo líneas principales, sin la categoría 7 (habilidades de clase). `plegadas` cuenta las categorías plegadas, cuyas habilidades no se listan. Hasta 80. Se manda con `SKILL_LINES_CHANGED`.

### rep (0.15.2)

`plegados#factionID,grupo,nombre,reacción,actual,umbralActual,umbralSiguiente,guerra,vigilada;…`

`reacción` va de 1 (odiado) a 8 (exaltado). `guerra` y `vigilada` son `1` o `0`. Un encabezado con reputación propia va como registro con `grupo` vacío. Hasta 100. Se manda con `UPDATE_FACTION`.

### monedas (0.15.2)

`plegados#currencyID,grupo,nombre,cantidad,máximo,iconFileID;…`

`máximo` 0 es sin tope. Hasta 80. Se manda con `CURRENCY_DISPLAY_UPDATE`.

### grupo (0.15.2)

`modo#nombre,claseArchivo,nivel,subgrupo,zona,conectado,muerto,rango;…`

- `modo`: `raid`, `party` o vacío si estás solo.
- En banda incluye al jugador, con zona y rango (0 miembro, 1 asistente, 2 líder).
- En grupo no incluye al jugador; `subgrupo` es 1 y zona y rango van vacíos.
- `claseArchivo` es el token en inglés (`WARRIOR`, `MAGE`…).

Se manda con `GROUP_ROSTER_UPDATE`, y con `UNIT_LEVEL` y `UNIT_CONNECTION` de unidades `party*` o `raid*`.

### alts (0.15.2)

`cantidad#nombre,reino,claseArchivo,nivel,oroEnCobre,visto;…`

Cada personaje se guarda en `WOWCompanionDB.alts` al conectarse y cuando cambian su oro o su nivel. `visto` es `GetServerTime` del último cambio. Va ordenado por nombre y reino, hasta 50. Un personaje aparece recién después de conectarse una vez con 0.15.2.

### cuerpo (0.15.2)

`estado,mapa,x,y#`, con `estado` igual a `vivo`, `muerto` o `fantasma`. Vivo o sin cuerpo ubicable: `estado,,,#`. El cuerpo se busca con `C_DeathInfo.GetCorpseMapPosition` en el mapa del jugador y, si no está ahí, en sus mapas padre hasta el continente. Se manda con `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST` y `ZONE_CHANGED_NEW_AREA`.

### auras (0.15.2)

`cantidad#spellId,nombre,icono,cargas,duración,venceEpoch;…`

Mejoras activas del jugador (`C_UnitAuras.GetAuraDataByIndex` con `HELPFUL`), hasta 40. `venceEpoch` es la hora del servidor en que se termina, redondeada a 10 s; `0` si no vence. En combate no se lee (la API las vuelve secretas): se manda al salir (`PLAYER_REGEN_ENABLED`). Sin la API: `#`. Se manda con `UNIT_AURA` del jugador.

### pvp (0.15.2)

`tipoZona,subzona,facción,marcado#`. `tipoZona` es lo que devuelve `C_PvP.GetZonePVPInfo` (`sanctuary`, `friendly`, `hostile`, `contested`, `combat`, `arena`…); `subzona` y `marcado` (`UnitIsPVP`) van como `1`/`0`. Sin la API: `,,,#`. Se manda con `ZONE_CHANGED*`, `PLAYER_FLAGS_CHANGED` y `UNIT_FACTION` del jugador.

### reinicio (0.15.2)

`diarioEpoch,semanalEpoch#`: hora del servidor del próximo reinicio diario y semanal (`C_DateAndTime.GetSecondsUntilDailyReset`/`GetSecondsUntilWeeklyReset`), redondeada al minuto. Sin la API: `,#`. Se manda al entrar y otra vez 5 s después de cada reinicio diario.
