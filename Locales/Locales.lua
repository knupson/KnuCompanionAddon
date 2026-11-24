local _, ns = ...
local es = {
    ['Enabled'] = 'Activado', ['Disabled'] = 'Desactivado',
    ['Usage: /wowc on | off | send | status'] = 'Uso: /wowc on | off | send | status | gps off | gps on | chat off | chat on | chat canales on | chat canales off | app | diag | tipos | tipo <nombre> on | tipo <nombre> off',
    ['Bag companion: on | off | send | status'] = 'KnuCompanion: on | off | send | status | gps off | gps on | chat off | chat on | chat canales on | chat canales off | app | diag | tipos | tipo <nombre> on | tipo <nombre> off',
    ['GPS enabled'] = 'GPS en vivo activado', ['GPS disabled'] = 'GPS en vivo desactivado',
    ['Chat enabled'] = 'La app recibe hermandad, oficiales, susurros, grupo, banda y estancia',
    ['Chat disabled'] = 'La app ya no recibe el chat',
    ['Public channels enabled'] = 'La app también recibe General, Comercio y los demás canales',
    ['Public channels disabled'] = 'La app ya no recibe General, Comercio ni los demás canales',
    ['sid=%s seq=%d enabled=%s last=%s padding=%d bytes failure=%s duration=%.2f ms max=%.2f ms'] =
        'sid=%s seq=%d activo=%s último=%s relleno=%d bytes fallo=%s duración=%.2f ms máxima=%.2f ms',
    ['Route: source=%s found=%s duration=%.2f ms records=%d'] = 'Ruta: fuente=%s encontrada=%s duración=%.2f ms registros=%d',
    ['Types (off in parentheses): %s'] = 'Tipos (entre paréntesis, los apagados): %s',
    ['Unknown type: %s. List them with /wowc tipos'] = 'No existe el tipo %s. Los ves con /wowc tipos',
    ['Type %s off'] = 'La app ya no recibe %s', ['Type %s on'] = 'La app vuelve a recibir %s',
    ['Last type error: %s'] = 'Último tipo con error: %s',
    ['Last send per type: %s'] = 'Último envío por tipo (hace cuánto y tamaño): %s',
    ['off'] = 'apagado',
    ['none'] = 'ninguno', ['yes'] = 'sí', ['no'] = 'no',
    ['Log write failed'] = 'Falló la escritura al log',
    ['This addon shows nothing in game: it sends your data to the desktop app. Get it at %s. Repeat this with /wowc app.'] =
        'KnuCompanion necesita la app de escritorio, sin ella no muestra nada. Bajala de %s',
    ['Like it? Favorite it or comment at %s. Errors: %s, with the BugSack text.'] =
        '¿Te sirve KnuCompanion? Marcalo como favorito o dejá un comentario en %s. Si algo falla, contalo en %s con el texto del error (BugSack lo copia).',
    ['Other KNU addons: %s'] = 'Otros addons de KNU: %s',
}
-- La UI del addon se mantiene en castellano también con el cliente en otro idioma.
ns.L = LibStub('KnuLib-1.0'):NewLocale(es, es)
