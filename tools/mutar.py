"""Pruebas de mutación: copia el addon a una carpeta temporal, rompe una línea por vez y corre luajit tests/run.lua.
Cada mutación tiene que hacer fallar alguna prueba («MUERTA»); una «VIVA» es un hueco en las pruebas.
Uso: python tools/mutar.py desde la raíz del repo."""
import os, shutil, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(os.environ.get('TEMP') or os.environ.get('TMPDIR') or '/tmp', 'wowc-mutar')

# (descripción, texto original, texto mutado). Cada original tiene que aparecer una sola vez en Core.lua.
MUTACIONES = [
    ('grupo: online nil no cuenta como desconectado', "if conectado == nil then conectado = false end", ""),
    ('skill: deja pasar la categoría 7', "categoriaID and categoriaID ~= 7", "categoriaID"),
    ('rep: grupo de hijos', "if cabecera and not (Limpiar(info.isChild) == true) then grupo = nombre end", "if cabecera then grupo = nombre end"),
    ('hogar: sin redondeo a 10 s', "lista = falta > 0 and math.floor((servidor + falta) / 10 + 0.5) * 10 or 0", "lista = falta > 0 and math.floor(servidor + falta) or 0"),
    ('auras: sin postergar en combate', "        aurasEnCombate = true\n        return nil\n", "        aurasEnCombate = true\n"),
    ('ruta: no recalcula al salir de combate', "if rutaEnCombate then rutaEnCombate = false; Pedir('event', 'ruta') end", ""),
    ('cuerpo: no sube a mapas padre', "mapa = type(info) == 'table' and Numero(info.parentMapID) or nil", "mapa = nil"),
    ('alts: no ordena', "    table.sort(claves)\n", ""),
    ('reinicio: no agenda el siguiente', "C_Timer.After(math.min(diario, 86400) + 5, function() Pedir('event', 'reinicio') end)", ""),
    ('pvp: subzona invertida', "subzona = sub == true and '1' or (sub == false and '0' or '')", "subzona = sub == true and '0' or (sub == false and '1' or '')"),
    ('banco: Syndicator sin datos no usa copia propia', "if type(tabs) ~= 'table' or not next(tabs) then return BancoPropio() end", "if type(tabs) ~= 'table' or not next(tabs) then return 'nodata', {} end"),
    ('enviar: sin pcall por tipo', "local okFoto, r1, r2, r3, r4 = pcall(fotos[tipo])", "local okFoto, r1, r2, r3, r4 = true, fotos[tipo]()"),
    ('enviar: seq no vuelve atrás', "fallo, seq = tostring(partes), seq - 1", "fallo = tostring(partes)"),
    ('tipos: hello se puede apagar', "return tipo ~= 'hello' and type(WOWCompanionDB) == 'table'", "return type(WOWCompanionDB) == 'table'"),
    ('rutaFSL: clave nil coincide', "if type(paso) == 'table' and clave ~= nil and clave == Limpiar(paso.id) then", "if type(paso) == 'table' and clave == Limpiar(paso.id) then"),
    ('dur: no omite máximo cero', "if actual and maximo and maximo > 0 then", "if actual and maximo then"),
    # Código anterior a 0.15.2.
    ('tips: sin tope de 30 líneas', "local registros, total = {}, math.min(#lines, 30)", "local registros, total = {}, #lines"),
    ('bags: no agrega la bolsa 5', "    if limite < 5 then ids[#ids + 1] = 5 end\n", ""),
    ('mail: invierte el aviso', "return nuevo and '1' or '0', registros", "return nuevo and '0' or '1', registros"),
    ('chat: canales públicos siempre', "return evento ~= 'CHAT_MSG_CHANNEL' or WOWCompanionDB.chatCanales == true", "return true"),
    ('chat: buffer sin tope', "    if #bufferChat >= 50 then\n        table.remove(bufferChat, 1)\n        chatEnviados = math.max(0, chatEnviados - 1)\n    end\n", ""),
    ('chat: confirmar no borra', "    for _ = 1, chatEnviados do table.remove(bufferChat, 1) end\n", ""),
    ('enviar: reintentos sin tope', "if intentos[tipo] < 3 then Pedir('retry', tipo) end", "Pedir('retry', tipo)"),
    ('pos: umbral de movimiento 10 veces mayor', "CambioLugar(posicion, ultimaPos, 0.002)", "CambioLugar(posicion, ultimaPos, 0.02)"),
    ('relleno: 11 líneas', "            for _ = 1, 12 do", "            for _ = 1, 11 do"),
    ('pedir: send no fuerza', "if motivo == 'send' or motivo == 'retry'", "if motivo == 'retry'"),
    ('taxi: no revisa a los 10 s', "        C_Timer.After(10, RevisarVuelo)\n", ""),
    ('inst: none como instancia', "if not tipo or tipo == 'none' then return (tipo and ',none,' or ',,'), {} end", "if not tipo then return ',,', {} end"),
    ('monedas: no cuenta plegados', "if Limpiar(info.isHeaderExpanded) == false then plegados = plegados + 1 end", ""),
    ('grupo: solo cuenta como party', "    if total > 1 then\n        for i = 1, math.min(total - 1, 4) do", "    if total > 0 then\n        for i = 1, math.min(total - 1, 4) do"),
    ('aviso: la app no marca el aviso', "    if ns.desdeApp then WOWCompanionDB.avisoApp = true end\n", ""),
    ('opinar: sale siempre', "    elseif not WOWCompanionDB.avisoOpinar then", "    elseif true then"),
]

def copiar():
    if os.path.isdir(BASE):
        shutil.rmtree(BASE)
    shutil.copytree(REPO, BASE, ignore=shutil.ignore_patterns('.git', 'media', 'tools', 'docs'))

def correr():
    r = subprocess.run(['luajit', 'tests/run.lua'], cwd=BASE, capture_output=True, text=True, encoding='utf-8', errors='replace')
    return r.returncode, (r.stdout.strip().splitlines() or [''])[-1]

copiar()
original = open(os.path.join(BASE, 'Core.lua'), encoding='utf-8').read()
codigo, ultima = correr()
print('base:', ultima)
if codigo != 0:
    sys.exit('Las pruebas fallan sin mutar: arreglalas antes de correr las mutaciones.')
vivas = []
for desc, viejo, nuevo in MUTACIONES:
    if original.count(viejo) != 1:
        print('NO APLICA', desc, '(aparece', original.count(viejo), 'veces)')
        continue
    open(os.path.join(BASE, 'Core.lua'), 'w', encoding='utf-8', newline='').write(original.replace(viejo, nuevo, 1))
    codigo, ultima = correr()
    estado = 'MUERTA' if codigo != 0 else 'VIVA'
    if codigo == 0:
        vivas.append(desc)
    print(estado, '|', desc, '|', ultima)
open(os.path.join(BASE, 'Core.lua'), 'w', encoding='utf-8', newline='').write(original)
print('vivas:', len(vivas))
for v in vivas:
    print('  -', v)
