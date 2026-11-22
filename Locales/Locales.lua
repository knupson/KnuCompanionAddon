local _, ns = ...
ns.L = LibStub('KnuLib-1.0'):NewLocale({
    ['Enabled'] = 'Activado', ['Disabled'] = 'Desactivado',
    ['Usage: /wowc on | off | send | status'] = 'Uso: /wowc on | off | send | status',
    ['Bag companion: on | off | send | status'] = 'Bolsas en vivo: on | off | send | status',
    ['sid=%s seq=%d enabled=%s last=%s padding=%d bytes failure=%s duration=%.2f ms max=%.2f ms'] =
        'sid=%s seq=%d activo=%s último=%s relleno=%d bytes fallo=%s duración=%.2f ms máxima=%.2f ms',
    ['none'] = 'ninguno', ['yes'] = 'sí', ['no'] = 'no',
    ['Log write failed'] = 'Falló la escritura al log',
})
