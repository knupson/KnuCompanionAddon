local _, ns = ...
local es = {
    ['Enabled'] = 'Activado', ['Disabled'] = 'Desactivado',
    ['Usage: /wowc on | off | send | status'] = 'Uso: /wowc on | off | send | status | gps off | gps on',
    ['Bag companion: on | off | send | status'] = 'Compañon en vivo: on | off | send | status | gps off | gps on',
    ['GPS enabled'] = 'GPS en vivo activado', ['GPS disabled'] = 'GPS en vivo desactivado',
    ['sid=%s seq=%d enabled=%s last=%s padding=%d bytes failure=%s duration=%.2f ms max=%.2f ms'] =
        'sid=%s seq=%d activo=%s último=%s relleno=%d bytes fallo=%s duración=%.2f ms máxima=%.2f ms',
    ['none'] = 'ninguno', ['yes'] = 'sí', ['no'] = 'no',
    ['Log write failed'] = 'Falló la escritura al log',
}
-- La UI del addon se mantiene en castellano también con el cliente en otro idioma.
ns.L = LibStub('KnuLib-1.0'):NewLocale(es, es)
