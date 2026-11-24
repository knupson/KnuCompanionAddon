local _, ns = ...
local KL = LibStub('KnuLib-1.0')
local P, L = ns.Proto, ns.L
local Print = KL:NewPrinter('Companion')
local function Limpiar(v)
    if P.EsSecreto(v, canaccessvalue, issecretvalue) then return nil end
    return v
end
local function Numero(v)
    v = Limpiar(v)
    if type(v) == 'number' and v == v and v >= 0 and v < math.huge then return math.floor(v) end
end
local function Texto(v)
    v = Limpiar(v)
    if type(v) == 'string' then return v end
end
-- Forever no tiene math.randomseed (medido 2026-11-22: type = nil); math.random ya viene sembrado.
local server, perfil = Numero(GetServerTime()) or 0, Numero(debugprofilestop()) or 0
local sid = string.format('%08x', (server + math.floor(perfil) + math.random(0, 2147483646)) % 4294967296)
local enabled, pending = true, false
local tipos = {"bags", "bank", "equip", "char", "look", "hello", "pos", "quest", "mail", "dest", "log", "chat", "inst", "taxi", "dur", "ruta", "hogar", "skill", "rep", "grupo", "alts"}
ns.tipos = tipos -- Las pruebas cuentan líneas por ronda a partir de cuántos tipos hay.
local sinRelleno = {pos=true}
local sucio, ultima, intentos, forzar, despues = {}, {}, {}, {}, {}
local seq, relleno = 0, 0
local ultimoEnvio, ultimoVolcado, fallo
local duracion, maxima = 0, 0
local ultimaPos, posVolcada
local gpsPendiente, ultimoGiro, facingAnterior, volcadoDiferido
-- El juego escribe el log a disco por bloques (49.168 a 52.132 bytes medidos): sin relleno la posición llegó hasta 16 s tarde (2026-11-23).
local VOLCADO_GPS = 1
local events = KL:NewEvents()
local Pedir
local marcasPendientes, eventoMarcas, marcasIntentos = {}, false, {}
local function InfoMarca(id, exito)
    id = Numero(id)
    local tiposItem = id and marcasPendientes[id]
    if not tiposItem then return end
    marcasPendientes[id] = nil
    -- Si el servidor no devuelve el objeto, no se vuelve a pedir: cada pedido dispararía otro evento fallido.
    marcasIntentos[id] = (marcasIntentos[id] or 0) + 1
    if exito == false or marcasIntentos[id] > 3 then tiposItem = {} end
    if not next(marcasPendientes) then
        events:Off('GET_ITEM_INFO_RECEIVED', InfoMarca)
        eventoMarcas = false
    end
    -- Pedir agrupa ráfagas y limita el envío mediante el timer existente.
    for tipo in pairs(tiposItem) do Pedir('event', tipo) end
end
local function Marca(link, id, tipo, bag, slot)
    local api = Limpiar(KnuJunkAPI)
    if type(api) ~= 'table' or type(api.MarkFor) ~= 'function' then return '', false end
    -- No pasar secretos ni links inválidos al clasificador opcional.
    if not link or not link:match('item:%d+') then return '', false end
    local marca = Texto(api.MarkFor(link, bag, slot))
    local falta = not marca and id and (marcasIntentos[id] or 0) <= 3 and C_Item and C_Item.GetItemInfo and not Texto(C_Item.GetItemInfo(id))
    if falta then
        marcasPendientes[id] = marcasPendientes[id] or {}
        marcasPendientes[id][tipo] = true
        if not eventoMarcas then
            events:On('GET_ITEM_INFO_RECEIVED', InfoMarca)
            eventoMarcas = true
        end
    end
    return P.Escape(marca or ''), falta
end
local function LimpiarMarcas(tipo)
    for id, pendientes in pairs(marcasPendientes) do
        pendientes[tipo] = nil
        if not next(pendientes) then marcasPendientes[id] = nil end
    end
    if eventoMarcas and not next(marcasPendientes) then
        events:Off('GET_ITEM_INFO_RECEIVED', InfoMarca)
        eventoMarcas = false
    end
end

local function Real(v)
    v = Limpiar(v)
    if type(v) == 'number' and v == v and math.abs(v) < math.huge then return v end
end
local function Direccion()
    local facing = Real(GetPlayerFacing())
    if facing and facingAnterior and facing ~= facingAnterior then ultimoGiro = GetTime() end
    facingAnterior = facing
    return facing
end
local function Posicion()
    local map = Numero(C_Map.GetBestMapForUnit('player'))
    local punto = map and Limpiar(C_Map.GetPlayerMapPosition(map, 'player'))
    local x, y
    if punto then
        x, y = punto:GetXY()
        x, y = Real(x), Real(y)
        if x and (x < 0 or x > 1) then x = nil end
        if y and (y < 0 or y > 1) then y = nil end
    end
    local facing = Direccion()
    -- Twinmap Strip.lua, BuildPos: norte = 0, antihorario, pasos de 10 grados.
    -- Conservamos esa convención, pero el canal propio lleva radianes.
    if facing then facing = (math.floor(facing / (math.pi / 18) + 0.5) % 36) * (math.pi / 18) end
    local function Decimal(v, formato)
        return v and (string.format(formato, v):gsub(',', '.')) or ''
    end
    return table.concat({map or '', Decimal(x, '%.4f'), Decimal(y, '%.4f'), Decimal(facing, '%.3f')}, ','), {}, false,
        {map=map, x=x, y=y, facing=facing}
end
local function CambioLugar(a, b, umbral)
    if not b or a.map ~= b.map then return true end
    for _, campo in ipairs({'x', 'y'}) do
        local v, anterior = a[campo], b[campo]
        if (v == nil) ~= (anterior == nil) then return true end
        if v and math.abs(v - anterior) > umbral + 1e-12 then return true end
    end
    return false
end

-- La clave incluye idioma y el itemString entero; no se recorta la identidad.
local tipsEnviados, colaTips, ordenTips, tipsAgotados = {}, {}, {}, {}
-- Distinta de lo ya volcado: lugar o dirección (girar quieto también cuenta).
local function PosDistinta(a, b)
    return CambioLugar(a, b, 0) or a.facing ~= b.facing
end
local tipsGuardados, ordenGuardados
local function IniciarTips(vaciar)
    local version
    if C_AddOns and C_AddOns.GetAddOnMetadata then version = Texto(C_AddOns.GetAddOnMetadata('WOWCompanion', 'Version'))
    elseif GetAddOnMetadata then version = Texto(GetAddOnMetadata('WOWCompanion', 'Version')) end
    version = version or ''
    if type(WOWCompanionDB) ~= 'table' then WOWCompanionDB = {} end
    local cache = WOWCompanionDB.tipsEnviados
    -- Se olvida una vez por día: si la app perdió su caché de tooltips, a lo sumo pasa un día sin ellos
    -- (el canal es de una sola vía y la app no puede pedirlos; /wowc send también vacía).
    local hoy = type(date) == 'function' and Texto(date('%Y-%m-%d')) or ''
    if vaciar or type(cache) ~= 'table' or cache.version ~= version or (cache.dia ~= nil and cache.dia ~= hoy) then
        cache = {version=version, dia=hoy, claves={}}
        WOWCompanionDB.tipsEnviados = cache
    end
    if type(cache) == 'table' and cache.dia == nil then cache.dia = hoy --[[ datos de la versión anterior: desde hoy ]]
    end
    -- Normalizar al cargar y conservar las últimas 2000 claves entre todos los idiomas.
    local claves = type(cache.claves) == 'table' and cache.claves or {}
    tipsEnviados, ordenGuardados = {}, {}
    for i=math.max(1, #claves - 1999),#claves do
        local clave = claves[i]
        if type(clave) == 'string' and #clave <= 4096 and clave:find('|item:', 1, true) and not tipsEnviados[clave] then
            tipsEnviados[clave] = true
            ordenGuardados[#ordenGuardados + 1] = clave
        end
    end
    cache.claves, tipsGuardados = ordenGuardados, cache
end
local function ConfirmarTip(clave)
    if not tipsGuardados then IniciarTips() end
    if tipsEnviados[clave] then return end
    if #ordenGuardados >= 2000 then
        tipsEnviados[table.remove(ordenGuardados, 1)] = nil
    end
    ordenGuardados[#ordenGuardados + 1] = clave
    tipsEnviados[clave] = true
end
local function ItemString(link) return link and link:match('|H(item:[^|]+)|h') or '' end
local function ColorTip(color)
    color = Limpiar(color)
    if type(color) ~= 'table' then return '' end
    local metodo = Limpiar(color.GenerateHexColor)
    if type(metodo) ~= 'function' then return '' end
    local ok, hex = pcall(metodo, color)
    hex = ok and Texto(hex)
    return hex and hex:match('^%x%x(%x%x%x%x%x%x)$') or ''
end
local function PrepararTip(link, metodo, a, b)
    local item = ItemString(link)
    local idioma = Texto(GetLocale()) or ''
    if item == '' or idioma == '' or not C_TooltipInfo then return item end
    local clave = idioma .. '|' .. item
    if not tipsEnviados[clave] and not tipsAgotados[clave] and not colaTips[clave] then
        colaTips[clave] = {clave=clave, item=item, metodo=metodo, a=a, b=b, intentos=0, despues=GetTime()}
        ordenTips[#ordenTips + 1] = clave
    end
    return item
end
local function LeerTip(tip)
    if not C_TooltipInfo or type(C_TooltipInfo[tip.metodo]) ~= 'function' then return nil end
    -- Una casilla puede cambiar mientras esperaba datos: no guardar otro objeto bajo la clave anterior.
    if tip.metodo == 'GetBagItem' then
        local info = Limpiar(C_Container.GetContainerItemInfo(tip.a, tip.b))
        local link = type(info) == 'table' and Texto(info.hyperlink)
        if ItemString(link) ~= tip.item then return nil end
    elseif tip.metodo == 'GetInventoryItem' then
        if ItemString(Texto(GetInventoryItemLink('player', tip.b))) ~= tip.item then return nil end
    end
    local ok, datos = pcall(C_TooltipInfo[tip.metodo], tip.a, tip.b)
    datos = ok and Limpiar(datos)
    local lines = type(datos) == 'table' and Limpiar(datos.lines)
    if type(lines) ~= 'table' or #lines == 0 then return nil end
    local registros, total = {}, math.min(#lines, 30)
    for i=1,total do
        local linea = Limpiar(lines[i])
        if type(linea) ~= 'table' then linea = {} end
        registros[i] = table.concat({P.Escape(tip.clave), i, total,
            P.Escape(P.Recortar(Texto(linea.leftText) or '', 200)),
            P.Escape(P.Recortar(Texto(linea.rightText) or '', 200)),
            ColorTip(linea.leftColor), ColorTip(linea.rightColor)}, ',')
    end
    return registros
end

local function Bolsas()
    LimpiarMarcas('bags')
    local bolsas, registros, faltaNombre = {}, {}, false
    local limite = Numero(NUM_BAG_SLOTS) or 4
    local ids = {}
    for bag = 0, math.min(limite, 5) do ids[#ids + 1] = bag end
    if limite < 5 then ids[#ids + 1] = 5 end
    for _, bag in ipairs(ids) do
        local slots = Numero(C_Container.GetContainerNumSlots(bag))
        if bag ~= 5 or (slots and slots > 0) then
            bolsas[#bolsas + 1] = bag .. ',' .. (slots or '')
            for slot = 1, slots or 0 do
                local info = Limpiar(C_Container.GetContainerItemInfo(bag, slot))
                if type(info) == 'table' then
                    local id, count = Numero(info.itemID), Numero(info.stackCount)
                    local quality, icon = Numero(info.quality), Numero(info.iconFileID)
                    local link = Texto(info.hyperlink)
                    local name = link and link:match('|h%[(.-)%]|h')
                    if (not name or name == '') and id and C_Item and C_Item.GetItemInfo then name = Texto(C_Item.GetItemInfo(id)) end
                    if not name or name == '' then name, faltaNombre = '', true end
                    local marca, falta = Marca(link, id, 'bags', bag, slot)
                    faltaNombre = faltaNombre or falta
                    registros[#registros + 1] = table.concat({bag, slot, id or '', count or '', quality or '', icon or '',
                        P.Escape(P.Recortar(name, 200)), P.Escape(PrepararTip(link, 'GetBagItem', bag, slot)), marca}, ',')
                end
            end
        end
    end
    return table.concat(bolsas, ';'), registros, faltaNombre
end

local function Nombre(id, link)
    local nombre = link and link:match('|h%[(.-)%]|h')
    if (not nombre or nombre == '') and id and C_Item and C_Item.GetItemInfo then nombre = Texto(C_Item.GetItemInfo(id)) end
    return P.Escape(P.Recortar(nombre or '', 200)), not nombre or nombre == ''
end

local function Banco()
    LimpiarMarcas('bank')
    local faltan = false
    if not Syndicator then return 'nosyn', {} end
    if not Limpiar(Syndicator.API.IsReady()) then return nil end
    local personaje = Texto(Syndicator.API.GetCurrentCharacter())
    if not personaje then return nil end -- Ready todavía no dejó disponible al personaje.
    local datos = Limpiar(Syndicator.API.GetByCharacterFullName(personaje))
    local tabs = type(datos) == 'table' and Limpiar(datos.bankTabs)
    if type(tabs) ~= 'table' or not next(tabs) then return 'nodata', {} end
    local cab, registros = {'ok'}, {}
    for tab, datosTab in ipairs(tabs) do
        datosTab = Limpiar(datosTab)
        local slots = type(datosTab) == 'table' and Limpiar(datosTab.slots)
        if type(slots) == 'table' then
            cab[#cab + 1] = tab .. ',' .. #slots
            for slot, info in ipairs(slots) do
                info = Limpiar(info)
                if type(info) == 'table' then
                    local id = Numero(info.itemID)
                    if id then
                        local link = Texto(info.itemLink)
                        local nombre = Nombre(id, link)
                        -- Syndicator es una foto guardada: tab no es un bagID vivo.
                        local marca, falta = Marca(link, id, 'bank')
                        faltan = faltan or falta
                        registros[#registros + 1] = table.concat({tab, slot, id, Numero(info.itemCount) or '',
                            Numero(info.quality) or '', Numero(info.iconTexture) or '', nombre,
                            P.Escape(PrepararTip(link, 'GetHyperlink', link)), marca}, ',')
                    end
                end
            end
        end
    end
    if #cab == 1 then return 'nodata', {} end
    return table.concat(cab, ';'), registros, faltan
end

local function Equipo()
    LimpiarMarcas('equip')
    local registros, faltan = {}, false
    for slot = 1, 19 do
        local id = Numero(GetInventoryItemID('player', slot))
        if id then
            local calidad = Numero(GetInventoryItemQuality('player', slot))
            local icono = Numero(GetInventoryItemTexture('player', slot))
            local link = Texto(GetInventoryItemLink('player', slot))
            local nombre, falta = Nombre(id, link)
            local marca, faltaMarca = Marca(link, id, 'equip')
            faltan = faltan or falta or faltaMarca or calidad == nil
            registros[#registros + 1] = table.concat({slot, id, calidad or '', icono or '', nombre,
                P.Escape(PrepararTip(link, 'GetInventoryItem', 'player', slot)), marca}, ',')
        end
    end
    return '', registros, faltan
end

local function Personaje()
    local _, claseArchivo = UnitClass('player')
    local raza, _, raceID = UnitRace('player')
    raceID = Numero(raceID)
    local sexo = Numero(UnitSex('player'))
    sexo = (sexo == 2 and 0) or (sexo == 3 and 1) or nil
    local _, equipado = GetAverageItemLevel()
    equipado = Limpiar(equipado)
    local decimal = ''
    if type(equipado) == 'number' and equipado == equipado and equipado >= 0 and equipado < math.huge then
        -- Se fuerza el punto: una coma decimal partiría el campo en dos.
        decimal = (string.format('%.1f', equipado):gsub(',', '.'))
    end
    return table.concat({Numero(UnitLevel('player')) or '', Numero(GetMoney()) or '',
        P.Escape(P.Recortar(Texto(GetZoneText()) or '', 200)),
        P.Escape(P.Recortar(Texto(GetSubZoneText()) or '', 200)),
        P.Escape(P.Recortar(Texto(UnitName('player')) or '', 200)),
        P.Escape(Texto(claseArchivo) or ''), P.Escape(P.Recortar(Texto(raza) or '', 200)), decimal,
        raceID or '', sexo or '', Numero(UnitXP('player')) or '', Numero(UnitXPMax('player')) or '',
        P.Escape(Texto(GetRealmName()) or ''),
        -- Al final, para no correr los campos que la app ya lee: XP descansada (GetXPExhaustion, nil sin descanso) y si
        -- estás en una posada o ciudad (IsResting). Las dos están en la rama forever de wow-ui-source.
        Numero(GetXPExhaustion and GetXPExhaustion()) or '', (IsResting and (Limpiar(IsResting()) == true and '1' or '0')) or ''}, ','), {}
end
local function Hello()
    local version
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        version = C_AddOns.GetAddOnMetadata('WOWCompanion', 'Version')
    elseif GetAddOnMetadata then
        version = GetAddOnMetadata('WOWCompanion', 'Version')
    end
    local _, _, _, interface = GetBuildInfo()
    return P.Escape(version or '0.0.0') .. ',' .. tostring(interface), {}
end
-- Misiones con objetivo en el mapa actual: posición, título y objetivos (probado en Forever el 2026-11-23).
-- Grupos de 4 por objetivo (hasta 8): cumplidos, requeridos, terminado, texto. Lo comparten quest y log.
local function Objetivos(id, campos)
    local objetivos = C_QuestLog.GetQuestObjectives and Limpiar(C_QuestLog.GetQuestObjectives(id))
    if type(objetivos) ~= 'table' then return end
    for i = 1, math.min(#objetivos, 8) do
        local o = Limpiar(objetivos[i])
        if type(o) == 'table' then
            campos[#campos + 1] = Numero(o.numFulfilled) or ''
            campos[#campos + 1] = Numero(o.numRequired) or ''
            campos[#campos + 1] = Limpiar(o.finished) == true and 1 or 0
            campos[#campos + 1] = P.Escape(P.Recortar(Texto(o.text) or '', 120))
        end
    end
end
-- Una fila del registro de misiones: C_QuestLog.GetInfo o, en clientes viejos, GetQuestLogTitle (como KnuJunk/Player.lua).
local function FilaRegistro(i)
    if C_QuestLog.GetInfo then
        local info = Limpiar(C_QuestLog.GetInfo(i))
        if type(info) ~= 'table' then return nil end
        return Texto(info.title), Numero(info.level), Limpiar(info.isHeader) == true, Limpiar(info.isCollapsed), Numero(info.questID)
    elseif GetQuestLogTitle then
        local titulo, nivel, _, cabecera, plegada, _, _, id = GetQuestLogTitle(i)
        return Texto(titulo), Numero(nivel), Limpiar(cabecera) == true or Limpiar(cabecera) == 1, Limpiar(plegada), Numero(id)
    end
end
-- Registro completo en su orden, hasta 35 misiones. Las que están bajo una categoría plegada el juego no las lista:
-- el encabezado lleva cuántas categorías plegadas hay para que la app lo avise (no se despliegan solas).
local function Registro()
    local registros, plegadas = {}, 0
    if not C_QuestLog or not (C_QuestLog.GetInfo or GetQuestLogTitle) then return '0', registros end
    local total = C_QuestLog.GetNumQuestLogEntries and Numero((C_QuestLog.GetNumQuestLogEntries()))
        or GetNumQuestLogEntries and Numero((GetNumQuestLogEntries())) or 0
    local categoria = ''
    for i = 1, math.min(total, 200) do
        if #registros >= 35 then break end
        local titulo, nivel, cabecera, plegada, id = FilaRegistro(i)
        if cabecera then
            categoria = P.Escape(P.Recortar(titulo or '', 120))
            if plegada == true or (type(plegada) == 'number' and plegada ~= 0) then plegadas = plegadas + 1 end
        elseif id and id > 0 then
            local lista = C_QuestLog.ReadyForTurnIn and Limpiar(C_QuestLog.ReadyForTurnIn(id))
            if lista == nil and C_QuestLog.IsComplete then lista = Limpiar(C_QuestLog.IsComplete(id)) end
            local fallida = C_QuestLog.IsFailed and Limpiar(C_QuestLog.IsFailed(id))
            local campos = {id, nivel or '', lista == true and 1 or 0, fallida == true and 1 or 0, categoria,
                P.Escape(P.Recortar(titulo or '', 120))}
            Objetivos(id, campos)
            registros[#registros + 1] = table.concat(campos, ',')
        end
    end
    return tostring(plegadas), registros
end
local function Misiones()
    local map = Numero(C_Map.GetBestMapForUnit('player'))
    local seguida = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Numero(C_SuperTrack.GetSuperTrackedQuestID()) or nil
    -- Sin misión seguida el juego devuelve 0: se manda vacío.
    if seguida == 0 then seguida = nil end
    local registros = {}
    local lista = map and C_QuestLog and C_QuestLog.GetQuestsOnMap and Limpiar(C_QuestLog.GetQuestsOnMap(map))
    local function Coordenada(v)
        v = Real(v)
        if v and v >= 0 and v <= 1 then return (string.format('%.4f', v):gsub(',', '.')) end
    end
    if type(lista) == 'table' then
        -- Tope de 25, pero la misión seguida entra siempre para que la app dibuje la línea hacia ella.
        local orden = {}
        for _, q in ipairs(lista) do
            q = Limpiar(q)
            if type(q) == 'table' and seguida and Numero(q.questID) == seguida then table.insert(orden, 1, q) else orden[#orden + 1] = q end
        end
        for _, q in ipairs(orden) do
            if #registros >= 25 then break end
            local id = type(q) == 'table' and Numero(q.questID)
            local x, y = id and Coordenada(q.x), id and Coordenada(q.y)
            if id and id > 0 and x and y then
                local entregar = C_QuestLog.ReadyForTurnIn and Limpiar(C_QuestLog.ReadyForTurnIn(id))
                local campos = {id, x, y, entregar == true and 1 or 0,
                    P.Escape(P.Recortar(C_QuestLog.GetTitleForQuestID and Texto(C_QuestLog.GetTitleForQuestID(id)) or '', 120))}
                Objetivos(id, campos)
                registros[#registros + 1] = table.concat(campos, ',')
            end
        end
    end
    return table.concat({map or '', seguida or ''}, ','), registros
end
-- Aviso de correo sin abrir el buzón: HasNewMail y GetLatestThreeSenders son globales del cliente.
local function Correo()
    local nuevo = HasNewMail and Limpiar(HasNewMail())
    local registros = {}
    if nuevo and GetLatestThreeSenders then
        local remitentes = {GetLatestThreeSenders()}
        for i = 1, 3 do
            local nombre = Texto(remitentes[i])
            if nombre and nombre ~= '' then registros[#registros + 1] = P.Escape(P.Recortar(nombre, 60)) end
        end
    end
    return nuevo and '1' or '0', registros
end
-- Destino de la flecha de TomTom (WoWPro y otros guían por ahí). TomTom no tiene un getter público del destino
-- actual: se guarda el último uid del callback ArrowTargetChanged (TomTom/core/callbacks.lua).
local destinoFlecha
local function Destino()
    local uid = Limpiar(destinoFlecha)
    if type(uid) ~= 'table' then return ',,,,', {} end
    local map = Numero(uid[1])
    local x, y = Real(uid[2]), Real(uid[3])
    if not map or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return ',,,,', {} end
    local function Campo(v) return P.Escape(P.Recortar(Texto(v) or '', 120)) end
    return table.concat({map, (string.format('%.4f', x):gsub(',', '.')), (string.format('%.4f', y):gsub(',', '.')),
        Campo(uid.title), Campo(uid.from)}, ','), {}
end
-- Chat para el panel de la app. Los mensajes se juntan en un buffer (tope 50) y salen agrupados por el timer de Pedir;
-- sólo se borran los que llegaron a escribirse. Los canales públicos (General, Comercio...) son opcionales por el volumen.
local bufferChat, chatEnviados = {}, 0
local canalesChat = {
    CHAT_MSG_GUILD='guild', CHAT_MSG_OFFICER='officer', CHAT_MSG_WHISPER='whisper', CHAT_MSG_WHISPER_INFORM='whisper_out',
    CHAT_MSG_PARTY='party', CHAT_MSG_PARTY_LEADER='party', CHAT_MSG_RAID='raid', CHAT_MSG_RAID_LEADER='raid',
    CHAT_MSG_INSTANCE_CHAT='instance', CHAT_MSG_INSTANCE_CHAT_LEADER='instance', CHAT_MSG_CHANNEL='channel',
}
local function ChatActivo(evento)
    if not enabled or type(WOWCompanionDB) ~= 'table' or WOWCompanionDB.chat == false then return false end
    return evento ~= 'CHAT_MSG_CHANNEL' or WOWCompanionDB.chatCanales == true
end
local function MensajeChat(evento, texto, remitente, _, nombreCanal, _, _, _, _, canalBase, _, lineID)
    if not ChatActivo(evento) then return end
    -- Remitente o texto secretos (SecretInChatMessagingLockdown): el mensaje no se manda.
    texto, remitente = Texto(texto), Texto(remitente)
    if not texto or not remitente then return end
    local canal = canalesChat[evento]
    if canal == 'channel' then
        local nombre = Texto(canalBase) or Texto(nombreCanal)
        if not nombre or nombre == '' then return end
        canal = 'channel:' .. P.Recortar(nombre, 60)
    end
    if #bufferChat >= 50 then
        table.remove(bufferChat, 1)
        chatEnviados = math.max(0, chatEnviados - 1)
    end
    bufferChat[#bufferChat + 1] = table.concat({P.Escape(canal), P.Escape(P.Recortar(remitente, 60)),
        Numero(lineID) or '', P.Escape(P.Recortar(texto, 255))}, ',')
    Pedir('event', 'chat')
end
local function Chat()
    chatEnviados = #bufferChat
    local registros = {}
    for i, r in ipairs(bufferChat) do registros[i] = r end
    return '', registros
end
local function ConfirmarChat()
    for _ = 1, chatEnviados do table.remove(bufferChat, 1) end
    chatEnviados = 0
end
-- Instancia actual para que la app abra el mapa de la mazmorra. GetInstanceInfo: 1.º nombre, 2.º tipo, 8.º instanceID
-- (mismo orden que leen DBM y Details). Fuera de instancia el 8.º es el continente: se manda ',none,'.
local function Instancia()
    if not GetInstanceInfo then return ',none,', {} end
    local nombre, tipo, _, _, _, _, _, id = GetInstanceInfo()
    tipo = Texto(tipo)
    if not tipo or tipo == 'none' then return (tipo and ',none,' or ',,'), {} end
    return table.concat({Numero(id) or '', P.Escape(tipo), P.Escape(P.Recortar(Texto(nombre) or '', 120))}, ','), {}
end
-- Vuelo en curso. Se arma al llamar TakeTaxiNode (hook) con los nodos del mapa de vuelo abierto: GetTaxiMapID,
-- C_TaxiMap.GetAllTaxiNodes y los tramos de GetNumRoutes/TaxiGetNodeSlot (wow-ui-source rama forever 1.60.1.71037).
-- Se borra al aterrizar, o a los 10 s si el vuelo no arrancó (sin plata, mapa cerrado).
local vuelo, vueloEnAire, vueloInicio
local function NodoTaxi(nodo)
    nodo = Limpiar(nodo)
    if type(nodo) ~= 'table' then return nil end
    local pos, x, y = Limpiar(nodo.position)
    if type(pos) == 'table' then
        if type(Limpiar(pos.GetXY)) == 'function' then
            local ok, a, b = pcall(pos.GetXY, pos)
            if ok then x, y = a, b end
        end
        if x == nil then x, y = Limpiar(pos.x), Limpiar(pos.y) end
    end
    x, y = Real(x), Real(y)
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return {id=Numero(nodo.nodeID), slot=Numero(nodo.slotIndex), nombre=Texto(nodo.name), x=x, y=y}
end
local function ArmarVuelo(destino)
    destino = Numero(destino)
    local mapa = GetTaxiMapID and Numero(GetTaxiMapID())
    if not destino or not mapa or not C_TaxiMap or not C_TaxiMap.GetAllTaxiNodes then return nil end
    local porSlot = {}
    local nodos = Limpiar(C_TaxiMap.GetAllTaxiNodes(mapa))
    if type(nodos) ~= 'table' then return nil end
    for _, n in ipairs(nodos) do
        n = NodoTaxi(n)
        if n and n.slot then porSlot[n.slot] = n end
    end
    local slots = {}
    local tramos = GetNumRoutes and Numero(GetNumRoutes(destino)) or 0
    for i = 1, math.min(tramos, 30) do
        if i == 1 then slots[1] = TaxiGetNodeSlot and Numero(TaxiGetNodeSlot(destino, i, true)) end
        slots[#slots + 1] = TaxiGetNodeSlot and Numero(TaxiGetNodeSlot(destino, i, false))
    end
    if #slots == 0 then slots = {destino} end
    local registros = {}
    for _, slot in ipairs(slots) do
        local n = porSlot[slot]
        if not n or not n.id then return nil end
        registros[#registros + 1] = table.concat({n.id, (string.format('%.4f', n.x):gsub(',', '.')), (string.format('%.4f', n.y):gsub(',', '.'))}, ':')
    end
    local final = porSlot[destino]
    return {cab=mapa .. ',' .. P.Escape(P.Recortar(final and final.nombre or '', 120)), registros=registros}
end
local function RevisarVuelo()
    if not vuelo then return end
    local enTaxi = Limpiar(UnitOnTaxi('player')) == true
    if enTaxi then vueloEnAire = true return end
    if vueloEnAire or GetTime() - (vueloInicio or 0) >= 10 then
        vuelo, vueloEnAire = nil, false
        Pedir('event', 'taxi')
    end
end
local function Taxi()
    if not vuelo then return ',', {} end
    return vuelo.cab, vuelo.registros
end
-- Durabilidad del equipo para que la app avise cuándo reparar: slot:actual:máximo de los slots 1 a 19 que la tienen.
-- GetInventoryItemDurability(slot) existe en la rama forever de wow-ui-source (EquipmentManager.lua, Mainline).
local function Durabilidad()
    if type(GetInventoryItemDurability) ~= 'function' then return '', {} end
    local partes = {}
    for slot = 1, 19 do
        local ok, actual, maximo = pcall(GetInventoryItemDurability, slot)
        actual, maximo = ok and Numero(actual), ok and Numero(maximo)
        if actual and maximo and maximo > 0 then partes[#partes + 1] = slot .. ':' .. actual .. ':' .. maximo end
    end
    return table.concat(partes, ';'), {}
end
-- Ruta hasta el destino para que la app la dibuje. Fuente principal FarstriderLib (FarstriderLib_API, Deathwing/FarstriderLib
-- e884a6b, 1.5.0, toc 16001); respaldo ShortestPathForever (ShortestPathForever.API v1/v2, cjber/shortest-path-forever e154ee6).
local MAX_TRAMOS, MAX_PUNTOS = 30, 200
-- EdgeType de FarstriderLib~Pathfinding.lua, con los nombres de modo de SPF donde coinciden.
local MODOS_FSL = {[1000]='walk', [1001]='flight', [1002]='portal', [1003]='boat', [1004]='zeppelin', [1005]='item',
    [1006]='spell', [1007]='leave', [1008]='tram'}
local function Coord(v) return (string.format('%.4f', v):gsub(',', '.')) end
-- {map, x, y} de SPF o {mapId, pos={x,y}, isUI} de FarstriderLib, en 0-1 sobre su uiMap.
local function Lugar(lugar)
    lugar = Limpiar(lugar)
    if type(lugar) ~= 'table' then return '', '', '' end
    local mapa, x, y
    if lugar.pos ~= nil then
        local pos = Limpiar(lugar.pos)
        if Limpiar(lugar.isUI) ~= true or type(pos) ~= 'table' then return '', '', '' end
        mapa, x, y = Numero(lugar.mapId), Real(pos.x), Real(pos.y)
    else
        mapa, x, y = Numero(lugar.map), Real(lugar.x), Real(lugar.y)
    end
    if not (mapa and x and y) then return '', '', '' end
    return mapa, Coord(x), Coord(y)
end
-- Nodo del camino de FarstriderLib: su Location puede venir en coordenadas del mundo (isUI falso); se pasa al uiMap
-- con C_Map.GetMapPosFromWorldPos, como hace la propia librería en Pathfinding:GetZoneLocation.
local function PuntoFSL(nodo)
    nodo = Limpiar(nodo)
    if type(nodo) ~= 'table' or type(nodo.getLocation) ~= 'function' then return nil end
    local ok, lugar = pcall(nodo.getLocation)
    lugar = ok and Limpiar(lugar)
    if type(lugar) ~= 'table' or type(Limpiar(lugar.pos)) ~= 'table' then return nil end
    if Limpiar(lugar.isUI) ~= true then
        if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
        local pos = Limpiar(lugar.pos)
        local x, y = Real(pos.x), Real(pos.y)
        local continente = Numero(lugar.mapId)
        if not (continente and x and y) then return nil end
        local okm, mapa, uiPos = pcall(C_Map.GetMapPosFromWorldPos, continente, CreateVector2D(x, y))
        uiPos = okm and Limpiar(uiPos)
        if type(uiPos) ~= 'table' then return nil end
        lugar = {mapId=mapa, pos={x=uiPos.x, y=uiPos.y}, isUI=true}
    end
    local mapa, x, y = Lugar(lugar)
    if mapa == '' then return nil end
    return 'punto:' .. mapa .. ':' .. x .. ':' .. y
end
-- Destino: la flecha de TomTom, el punto marcado en el mapa (C_Map.GetUserWaypoint, rama forever) o la meta de SPF.
local function DestinoRuta(spf)
    local uid = Limpiar(destinoFlecha)
    if type(uid) == 'table' then
        local mapa, x, y = Numero(uid[1]), Real(uid[2]), Real(uid[3])
        if mapa and x and y then return mapa, x, y, Texto(uid.title) or '' end
    end
    if C_Map and C_Map.HasUserWaypoint and C_Map.GetUserWaypoint and Limpiar(C_Map.HasUserWaypoint()) == true then
        local punto = Limpiar(C_Map.GetUserWaypoint())
        local pos = type(punto) == 'table' and Limpiar(punto.position)
        if type(pos) == 'table' then
            local mapa, x, y = Numero(punto.uiMapID), Real(pos.x), Real(pos.y)
            if mapa and x and y then return mapa, x, y, '' end
        end
    end
    if spf then
        local ok, viaje = pcall(spf.Journey)
        local meta = ok and type(Limpiar(viaje)) == 'table' and Limpiar(viaje.goal)
        if type(meta) == 'table' then
            local mapa, x, y = Numero(meta.map), Real(meta.x), Real(meta.y)
            if mapa and x and y then return mapa, x, y, Texto(meta.title) or '' end
        end
    end
end
local function RutaFSL(fsl, mapa, x, y, titulo)
    local ok, pasos, camino, aristas = pcall(fsl.FindTrailTo, mapa, x, y, 0)
    pasos, camino, aristas = ok and Limpiar(pasos), ok and Limpiar(camino), ok and Limpiar(aristas)
    if type(pasos) ~= 'table' or #pasos == 0 or type(aristas) ~= 'table' then return nil end
    -- Cada paso optimizado cierra en la arista cuyo destino es su id; los segundos son la suma de costos hasta ahí.
    local registros, total, acumulado, k = {}, 0, 0, 1
    for i = 1, #aristas do
        local arista = Limpiar(aristas[i])
        local paso = Limpiar(pasos[k])
        if type(arista) == 'table' then
            local costo = Real(arista.cost) or 0
            acumulado, total = acumulado + costo, total + costo
            local destino = Limpiar(arista.to)
            if type(paso) == 'table' and type(destino) == 'table' and Limpiar(destino.key) == Limpiar(paso.id) then
                if #registros < MAX_TRAMOS then
                    local m1, x1, y1 = Lugar(paso.loc)
                    local m2, x2, y2 = Lugar(paso.completionLoc)
                    registros[#registros + 1] = table.concat({MODOS_FSL[Numero(arista.locaId)] or '', m1, x1, y1, m2, x2, y2,
                        math.floor(acumulado + 0.5), P.Escape(P.Recortar(Texto(paso.loca) or '', 120))}, ':')
                end
                acumulado, k = 0, k + 1
            end
        end
    end
    if type(camino) == 'table' then
        local puntos = 0
        for i = 1, #camino do
            local punto = puntos < MAX_PUNTOS and PuntoFSL(camino[i])
            if punto then registros[#registros + 1], puntos = punto, puntos + 1 end
        end
    end
    return P.Escape(P.Recortar(titulo, 120)) .. ',' .. math.floor(total + 0.5) .. ',fsl', registros
end
local function RutaSPF(spf)
    local ok, viaje, motivo = pcall(spf.Journey)
    if not ok then return ',,', {} end
    viaje = Limpiar(viaje)
    if type(viaje) ~= 'table' then
        if motivo == 'loading' then return nil end -- Se reintenta; el aviso 'replan' vuelve a pedirla.
        return ',,', {}
    end
    local meta = Limpiar(viaje.goal)
    local titulo = type(meta) == 'table' and Texto(meta.title) or ''
    local cab = P.Escape(P.Recortar(titulo, 120)) .. ',' .. (Numero(viaje.secondsLeft) or '') .. ',spf'
    local registros, tramos = {}, Limpiar(viaje.legs)
    if type(tramos) == 'table' then
        for i = 1, math.min(#tramos, MAX_TRAMOS) do
            local tramo = Limpiar(tramos[i])
            if type(tramo) == 'table' then
                local m1, x1, y1 = Lugar(tramo.from)
                local m2, x2, y2 = Lugar(tramo.to)
                registros[#registros + 1] = table.concat({P.Escape(Texto(tramo.mode) or ''), m1, x1, y1, m2, x2, y2,
                    Numero(tramo.seconds) or '', P.Escape(P.Recortar(Texto(tramo.text) or '', 120))}, ':')
            end
        end
    end
    return cab, registros
end
local function APIs()
    local fsl = type(FarstriderLib_API) == 'table' and type(FarstriderLib_API.FindTrailTo) == 'function' and FarstriderLib_API or nil
    local spf = type(ShortestPathForever) == 'table' and ShortestPathForever.API
    if type(spf) ~= 'table' or type(spf.Journey) ~= 'function' or (spf.version ~= 1 and spf.version ~= 2) then spf = nil end
    return fsl, spf
end
-- Último cálculo con fuente, para /wowc status: FindTrailTo corre en el momento y hay que poder ver cuánto tarda.
local rutaInfo
local function Medir(fuente, fn, ...)
    local inicio = debugprofilestop()
    local cab, registros = fn(...)
    rutaInfo = {fuente=fuente, ms=debugprofilestop() - inicio, registros=registros and #registros or 0, ok=cab ~= nil}
    return cab, registros
end
local function Ruta()
    local fsl, spf = APIs()
    if fsl then
        local mapa, x, y, titulo = DestinoRuta(spf)
        if mapa then
            local cab, registros = Medir('fsl', RutaFSL, fsl, mapa, x, y, titulo)
            if cab then return cab, registros end
        end
    end
    if spf then return Medir('spf', RutaSPF, spf) end
    return ',,', {}
end
-- Piedra de hogar: posada donde está atada, cuándo vuelve a estar lista y si la tenés. HEARTHSTONE_ITEM_ID (6948),
-- GetBindLocation y C_Container.GetItemCooldown están en la rama forever de wow-ui-source. «Lista» va en hora del servidor
-- (GetServerTime) redondeada a 10 s, para que el dato no cambie en cada envío mientras corre el enfriamiento.
local function Hogar()
    local posada = Texto(GetBindLocation and GetBindLocation()) or ''
    local item = Numero(HEARTHSTONE_ITEM_ID) or 6948
    local tiene = ''
    if C_Item and C_Item.GetItemCount then
        local cantidad = Numero(C_Item.GetItemCount(item))
        if cantidad then tiene = cantidad > 0 and '1' or '0' end
    end
    local lista = ''
    local enfriamiento = C_Container and C_Container.GetItemCooldown
    if enfriamiento then
        local ok, inicio, duracion = pcall(enfriamiento, item)
        inicio, duracion = ok and Real(inicio), ok and Real(duracion)
        local ahora, servidor = Real(GetTime()), Numero(GetServerTime())
        if inicio and duracion and ahora and servidor then
            local falta = (inicio > 0 and duracion > 0) and math.max(0, inicio + duracion - ahora) or 0
            lista = falta > 0 and math.floor((servidor + falta) / 10 + 0.5) * 10 or 0
        end
    end
    return table.concat({P.Escape(P.Recortar(posada, 120)), lista, tiene}, ','), {}
end
-- Habilidades (profesiones, armas, idiomas) como las lista la ventana del juego: C_SkillInfo y el filtro de
-- Camelot/SkillsFrame.lua de la rama forever (sólo líneas principales, sin la categoría 7, habilidades de clase).
-- Las de una categoría plegada no se listan; el encabezado dice cuántas categorías están plegadas, como en «log».
local MAX_HABILIDADES = 80
local function Habilidades()
    if not (C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo) then return '0', {} end
    local total = Numero(C_SkillInfo.GetNumSkillLines()) or 0
    local registros, plegadas, categoria = {}, 0, ''
    for i = 1, total do
        local info = Limpiar(C_SkillInfo.GetSkillLineInfo(i))
        if type(info) == 'table' then
            local cabecera = Limpiar(info.isHeader) == true
            local categoriaID = Numero(info.skillLineCategoryID)
            if cabecera then
                categoria = Texto(info.name) or ''
                if Limpiar(info.isCollapsed) == true then plegadas = plegadas + 1 end
            elseif Numero(info.parentSkillLineID) == 0 and categoriaID ~= 7 and #registros < MAX_HABILIDADES then
                registros[#registros + 1] = table.concat({Numero(info.skillID) or '', categoriaID or '',
                    P.Escape(P.Recortar(categoria, 60)), P.Escape(P.Recortar(Texto(info.name) or '', 80)),
                    Numero(info.rank) or '', Numero(info.maxRank) or '', Numero(info.modifier) or ''}, ',')
            end
        end
    end
    return tostring(plegadas), registros
end
-- Reputaciones como las lista la ventana del juego (Camelot/ReputationFrame.lua, rama forever): C_Reputation.GetNumFactions
-- y GetFactionDataByIndex. Las de un grupo plegado no se listan; el encabezado dice cuántos grupos están plegados.
-- Un encabezado con reputación propia (isHeaderWithRep) también va como registro.
local MAX_REPUTACIONES = 100
local function Reputaciones()
    if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then return '0', {} end
    local total = Numero(C_Reputation.GetNumFactions()) or 0
    local registros, plegados, grupo = {}, 0, ''
    for i = 1, total do
        local info = Limpiar(C_Reputation.GetFactionDataByIndex(i))
        if type(info) == 'table' then
            local cabecera = Limpiar(info.isHeader) == true
            local nombre = Texto(info.name) or ''
            if cabecera and Limpiar(info.isCollapsed) == true then plegados = plegados + 1 end
            if (not cabecera or Limpiar(info.isHeaderWithRep) == true) and #registros < MAX_REPUTACIONES then
                registros[#registros + 1] = table.concat({Numero(info.factionID) or '',
                    P.Escape(P.Recortar(cabecera and '' or grupo, 60)), P.Escape(P.Recortar(nombre, 80)),
                    Numero(info.reaction) or '', Real(info.currentStanding) and math.floor(Real(info.currentStanding)) or '',
                    Real(info.currentReactionThreshold) and math.floor(Real(info.currentReactionThreshold)) or '',
                    Real(info.nextReactionThreshold) and math.floor(Real(info.nextReactionThreshold)) or '',
                    Limpiar(info.atWarWith) == true and '1' or '0', Limpiar(info.isWatched) == true and '1' or '0'}, ',')
            end
            if cabecera and not (Limpiar(info.isChild) == true) then grupo = nombre end
        end
    end
    return tostring(plegados), registros
end
-- Integrantes del grupo o la banda. En banda, GetRaidRosterInfo (mismo orden de retornos que lee
-- Blizzard_CompactRaidFrameContainer.lua de la rama forever: nombre, rango, subgrupo, nivel, clase, claseArchivo, zona,
-- conectado, muerto); en grupo, las unidades party1..4 (el jugador no va). Solo: «,» sin registros.
local function Integrante(nombre, claseArchivo, nivel, subgrupo, zona, conectado, muerto, rango)
    return table.concat({P.Escape(P.Recortar(Texto(nombre) or '', 60)), P.Escape(Texto(claseArchivo) or ''),
        Numero(nivel) or '', Numero(subgrupo) or '', P.Escape(P.Recortar(Texto(zona) or '', 80)),
        Limpiar(conectado) == false and '0' or (Limpiar(conectado) and '1' or ''),
        Limpiar(muerto) and '1' or '0', Numero(rango) or ''}, ',')
end
local function Grupo()
    local registros = {}
    local enBanda = IsInRaid and Limpiar(IsInRaid()) == true
    local total = GetNumGroupMembers and Numero(GetNumGroupMembers()) or 0
    if enBanda and GetRaidRosterInfo then
        for i = 1, math.min(total, 40) do
            local nombre, rango, subgrupo, nivel, _, claseArchivo, zona, conectado, muerto = GetRaidRosterInfo(i)
            if Texto(nombre) then registros[#registros + 1] = Integrante(nombre, claseArchivo, nivel, subgrupo, zona, conectado, muerto, rango) end
        end
        return 'raid', registros
    end
    if total > 1 then
        for i = 1, math.min(total - 1, 4) do
            local unidad = 'party' .. i
            local nombre = UnitName and UnitName(unidad)
            if Texto(nombre) then
                local _, claseArchivo = UnitClass(unidad)
                registros[#registros + 1] = Integrante(nombre, claseArchivo, UnitLevel(unidad), 1, nil,
                    UnitIsConnected and UnitIsConnected(unidad), UnitIsDeadOrGhost and UnitIsDeadOrGhost(unidad), nil)
            end
        end
        return 'party', registros
    end
    return '', registros
end
-- Personajes de la cuenta: cada uno guarda en WOWCompanionDB.alts (SavedVariables de cuenta) su clase, nivel y oro al
-- conectarse y cuando cambian, y la app recibe la lista completa para sumar el oro de todos. «visto» es GetServerTime de la
-- última vez que cambió algo, para no reenviar la lista en cada envío.
local MAX_ALTS = 50
local function Alts()
    if type(WOWCompanionDB) ~= 'table' then return nil end
    WOWCompanionDB.alts = type(WOWCompanionDB.alts) == 'table' and WOWCompanionDB.alts or {}
    local nombre, reino = Texto(UnitName('player')), Texto(GetRealmName())
    if nombre and reino then
        local _, claseArchivo = UnitClass('player')
        local clave = nombre .. '-' .. reino
        local actual = WOWCompanionDB.alts[clave]
        if type(actual) ~= 'table' then actual = {} end
        local clase, nivel, oro = Texto(claseArchivo), Numero(UnitLevel('player')), Numero(GetMoney())
        if actual.clase ~= clase or actual.nivel ~= nivel or actual.oro ~= oro or not actual.visto then
            WOWCompanionDB.alts[clave] = {nombre=nombre, reino=reino, clase=clase, nivel=nivel, oro=oro,
                visto=Numero(GetServerTime()) or actual.visto}
        end
    end
    local claves = {}
    for clave, alt in pairs(WOWCompanionDB.alts) do
        if type(clave) == 'string' and type(alt) == 'table' then claves[#claves + 1] = clave end
    end
    table.sort(claves)
    local registros = {}
    for i = 1, math.min(#claves, MAX_ALTS) do
        local alt = WOWCompanionDB.alts[claves[i]]
        registros[#registros + 1] = table.concat({P.Escape(P.Recortar(tostring(alt.nombre or ''), 60)),
            P.Escape(P.Recortar(tostring(alt.reino or ''), 60)), P.Escape(tostring(alt.clase or '')),
            tonumber(alt.nivel) or '', tonumber(alt.oro) or '', tonumber(alt.visto) or ''}, ',')
    end
    return tostring(#claves), registros
end
local fotos = {mail=Correo, hello=Hello, bags=Bolsas, bank=Banco, equip=Equipo, char=Personaje, look=ns.Look, pos=Posicion, quest=Misiones, dest=Destino, log=Registro, chat=Chat, inst=Instancia, taxi=Taxi, dur=Durabilidad, ruta=Ruta, hogar=Hogar, skill=Habilidades, rep=Reputaciones, grupo=Grupo, alts=Alts}
-- Tipos que el jugador apagó con /wowc tipo <nombre> off (WOWCompanionDB.apagados). hello no se apaga: la app lo usa para
-- saber que el addon está vivo y qué versión tiene.
local function Apagado(tipo)
    return tipo ~= 'hello' and type(WOWCompanionDB) == 'table' and type(WOWCompanionDB.apagados) == 'table'
        and WOWCompanionDB.apagados[tipo] == true
end
local function Enviar()
    local inicio, enviados = debugprofilestop(), {}
    sucio.tip = nil
    for _, tipo in ipairs(tipos) do
        if tipo == 'chat' and #bufferChat == 0 then sucio.chat = nil end
        if sucio[tipo] and Apagado(tipo) then sucio[tipo], forzar[tipo] = nil, nil end
        if sucio[tipo] then
            sucio[tipo] = nil
            local cab, registros, faltan, posicion
            cab, registros, faltan, posicion = fotos[tipo]()
            if not cab then
                -- Syndicator todavía sin personaje: se reintenta a los 2 s, hasta 3 veces por pedido.
                intentos[tipo] = (intentos[tipo] or 0) + 1
                if intentos[tipo] < 3 then Pedir('retry', tipo) end
            else
                local foto = cab .. '#' .. table.concat(registros, ';')
                local fuerza = forzar[tipo]
                forzar[tipo] = nil
                local cambio = foto ~= ultima[tipo]
                if posicion then cambio = CambioLugar(posicion, ultimaPos, 0.002) or not ultimaPos or posicion.facing ~= ultimaPos.facing end
                if fuerza or cambio then
                    seq, intentos[tipo] = seq + 1, (intentos[tipo] or 0) + 1
                    local ok, partes = pcall(P.Partes, sid, seq, tipo, cab, registros)
                    if ok then
                        for _, linea in ipairs(partes) do
                            if not pcall(C_Log.LogMessage, linea) then ok = false end
                        end
                        enviados[#enviados + 1] = {tipo=tipo, foto=foto, ok=ok, faltan=faltan, posicion=posicion}
                    else
                        fallo = tostring(partes) -- El encabezado inválido no se manda.
                    end
                end
            end
        end
    end
    local enviadosTips, usados, restantes = {}, 0, {}
    for _, clave in ipairs(ordenTips) do
        local tip = colaTips[clave]
        if tip and tip.despues > GetTime() then
            restantes[#restantes + 1] = clave
        elseif tip and tip.intentos < 3 then
            -- Se lee igual (foto del contenido de ese momento) aunque la tanda esté llena.
            local registros = tip.registros or LeerTip(tip)
            local ok, partes
            if registros then ok, partes = pcall(P.Partes, sid, seq + 1, 'tip', '', registros) end
            if ok and #partes > 12 then ok = false end
            if ok then tip.registros = registros end
            -- Tanda llena: espera al próximo volcado sin gastar intento, haya o no datos.
            if (ok and usados + #partes > 12) or (not registros and usados >= 12) then
                restantes[#restantes + 1] = clave
            else
                tip.intentos = tip.intentos + 1
                tip.despues = GetTime() + 2
                if ok then
                    seq, usados = seq + 1, usados + #partes
                    for _, linea in ipairs(partes) do
                        if not pcall(C_Log.LogMessage, linea) then ok = false end
                    end
                    enviadosTips[#enviadosTips + 1] = {tip=tip, ok=ok}
                elseif tip.intentos < 3 then restantes[#restantes + 1] = clave
                else colaTips[clave], tipsAgotados[clave] = nil, true end
            end
        end
    end
    ordenTips = restantes
    if #enviados > 0 or #enviadosTips > 0 then
        local necesitaRelleno = #enviadosTips > 0
        for _, envio in ipairs(enviados) do
            if not sinRelleno[envio.tipo] or (envio.posicion and PosDistinta(envio.posicion, posVolcada)
                and GetTime() - (ultimoVolcado or 0) >= VOLCADO_GPS) then necesitaRelleno = true end
        end
        local rellenoOk = true
        if necesitaRelleno then
            for _ = 1, 12 do
                if pcall(C_Log.LogMessage, P.Relleno()) then relleno = relleno + 4089 else rellenoOk = false end
            end
            if rellenoOk then ultimoVolcado = GetTime() end
        end
        for _, envio in ipairs(enviados) do
            local tipo = envio.tipo
            if envio.ok and rellenoOk then
                ultima[tipo], ultimoEnvio = envio.foto, GetTime()
                if tipo == 'chat' then ConfirmarChat() end
                if envio.posicion then
                    ultimaPos = envio.posicion
                end
            else fallo = L['Log write failed'] end
            if (not envio.ok or not rellenoOk or envio.faltan) and intentos[tipo] < 3 then Pedir('retry', tipo) end
        end
        for _, envio in ipairs(enviadosTips) do
            local tip = envio.tip
            if envio.ok and rellenoOk then
                ConfirmarTip(tip.clave)
                colaTips[tip.clave] = nil
                ultimoEnvio = GetTime()
            elseif tip.intentos < 3 then
                ordenTips[#ordenTips + 1] = tip.clave
            else colaTips[tip.clave], tipsAgotados[tip.clave] = nil, true end
        end
        -- Otro tipo también vuelca las posiciones que ya estaban en el búfer.
        if necesitaRelleno and rellenoOk then posVolcada = ultimaPos end
        -- Al frenar antes del plazo la última posición quedaría en el búfer: un único volcado forzado al cumplirse.
        if ultimaPos and not volcadoDiferido and PosDistinta(ultimaPos, posVolcada) then
            volcadoDiferido = true
            C_Timer.After(math.max(0, (ultimoVolcado or 0) + VOLCADO_GPS - GetTime()), function()
                volcadoDiferido = false
                if posVolcada ~= ultimaPos then Pedir('position', 'pos') end
            end)
        end
        local todosOk = rellenoOk
        for _, envio in ipairs(enviados) do todosOk = todosOk and envio.ok end
        for _, envio in ipairs(enviadosTips) do todosOk = todosOk and envio.ok end
        if todosOk then fallo = nil else fallo = L['Log write failed'] end
    end
    if #ordenTips > 0 then Pedir('retry', 'tip') end
    duracion = debugprofilestop() - inicio
    maxima = math.max(maxima, duracion)
end

-- Un único timer agrupa eventos; cada tipo conserva su estado y su plazo de reintento.
Pedir = function(motivo, tipo)
    if not enabled then return end
    -- chat no entra en los pedidos generales: sólo sale cuando hay mensajes nuevos.
    if not tipo then for _, t in ipairs(tipos) do if t ~= 'chat' then Pedir(motivo, t) end end; return end
    local plazoAnterior = sucio[tipo] and despues[tipo]
    sucio[tipo] = true
    if motivo == 'send' or motivo == 'retry' or motivo == 'position' or (motivo == 'world' and (tipo == 'look' or tipo == 'hello' or tipo == 'pos')) then forzar[tipo] = true end
    if motivo ~= 'retry' then intentos[tipo], despues[tipo] = 0, GetTime() + 1
    else despues[tipo] = GetTime() + 2 end
    if plazoAnterior then despues[tipo] = math.min(plazoAnterior, despues[tipo]) end
    if pending then return end
    local function Agendar()
        local ahora, vence = GetTime(), nil
        for t in pairs(sucio) do vence = math.min(vence or math.huge, despues[t] or ahora + 1) end
        if not vence then return end
        pending = true
        C_Timer.After(math.max(0, vence - ahora, ultimoVolcado and ultimoVolcado + 1 - ahora or 0), function()
            pending = false
            if not enabled then return end
            local futuros = {}
            for t in pairs(sucio) do
                if despues[t] and despues[t] > GetTime() then futuros[t], sucio[t] = true, nil end
            end
            Enviar()
            for t in pairs(futuros) do sucio[t] = true end
            if not pending then Agendar() end
        end)
    end
    Agendar()
end
ns.Pedir = Pedir

local function GPSActivo()
    return enabled and WOWCompanionDB and WOWCompanionDB.gps ~= false
end
local function EnMarcha()
    return Limpiar(IsPlayerMoving()) == true or Limpiar(UnitOnTaxi('player')) == true
        or Limpiar(UnitInVehicle('player')) == true or (ultimoGiro and GetTime() - ultimoGiro < 5)
end
local function AgendarGPS(iniciarGiro)
    -- El evento de inicio despierta una lectura; sólo un cambio real permite reagendarla.
    if gpsPendiente or not GPSActivo() or (not iniciarGiro and not EnMarcha()) then return end
    gpsPendiente = true
    C_Timer.After(1, function()
        gpsPendiente = false
        if not GPSActivo() then return end
        Direccion()
        Pedir('gps', 'pos')
        AgendarGPS()
    end)
end
local function EventoPosicion()
    Direccion()
    Pedir('position', 'pos')
    AgendarGPS()
end
-- El canal es de una sola vía: el addon no puede saber si la app está abierta, así que avisa una vez por cuenta.
-- Repo público sólo con los releases de la app (decisión del user, 2026-11-23).
local DESCARGA_APP = 'https://github.com/knupson/KnuCompanion/releases/latest'
-- El repo del addon es privado: los errores van a los issues del repo público de la app, que se publica junto con el addon.
local PAGINA_CF, ISSUES = 'https://www.curseforge.com/wow/addons/knucompanion', 'https://github.com/knupson/KnuCompanion/issues'
local function AvisoApp()
    Print(string.format(L['This addon shows nothing in game: it sends your data to the desktop app. Get it at %s. Repeat this with /wowc app.'], DESCARGA_APP))
end
local function AvisoOpinar()
    Print(string.format(L['Like it? Favorite it or comment at %s. Errors: %s, with the BugSack text.'], PAGINA_CF, ISSUES))
end
local function Comando(msg)
    msg = (msg or ''):match('^%s*(.-)%s*$'):lower()
    if msg == 'off' then enabled = false; sucio, forzar = {}, {}; Print(L['Disabled'])
    elseif msg == 'on' then enabled = true; Print(L['Enabled']); Pedir('send'); AgendarGPS()
    elseif msg == 'gps off' then
        WOWCompanionDB.gps = false
        -- Descartar también un envío del GPS ya agrupado, sin afectar otros tipos.
        sucio.pos, forzar.pos = nil, nil
        Print(L['GPS disabled'])
    elseif msg == 'gps on' then
        WOWCompanionDB.gps = true
        Print(L['GPS enabled'])
        EventoPosicion()
    elseif msg == 'send' then
        IniciarTips(true)
        colaTips, ordenTips, tipsAgotados = {}, {}, {}
        Pedir('send')
    elseif msg == 'status' then
        Print(string.format(L['sid=%s seq=%d enabled=%s last=%s padding=%d bytes failure=%s duration=%.2f ms max=%.2f ms'],
            sid, seq, L[enabled and 'yes' or 'no'], ultimoEnvio and tostring(ultimoEnvio) or L['none'],
            relleno, fallo or L['none'], duracion, maxima))
        if rutaInfo then
            Print(string.format(L['Route: source=%s found=%s duration=%.2f ms records=%d'], rutaInfo.fuente,
                L[rutaInfo.ok and 'yes' or 'no'], rutaInfo.ms, rutaInfo.registros))
        end
    elseif msg == 'app' then AvisoApp()
    elseif msg == 'tipos' then
        local lista = {}
        for _, tipo in ipairs(tipos) do lista[#lista + 1] = Apagado(tipo) and ('(' .. tipo .. ')') or tipo end
        Print(string.format(L['Types (off in parentheses): %s'], table.concat(lista, ' ')))
    elseif msg:match('^tipo %S+ o[nf]f?$') then
        local tipo, estado = msg:match('^tipo (%S+) (o[nf]f?)$')
        local valido = false
        for _, t in ipairs(tipos) do if t == tipo and t ~= 'hello' then valido = true end end
        if not valido or (estado ~= 'on' and estado ~= 'off') then
            Print(string.format(L['Unknown type: %s. List them with /wowc tipos'], tipo))
        else
            WOWCompanionDB.apagados = type(WOWCompanionDB.apagados) == 'table' and WOWCompanionDB.apagados or {}
            WOWCompanionDB.apagados[tipo] = estado == 'off' or nil
            Print(string.format(L[estado == 'off' and 'Type %s off' or 'Type %s on'], tipo))
            if estado == 'on' then Pedir('send', tipo) end
        end
    elseif msg == 'chat on' or msg == 'chat off' then
        WOWCompanionDB.chat = msg == 'chat on'
        if not WOWCompanionDB.chat then bufferChat, chatEnviados, sucio.chat = {}, 0, nil end
        Print(L[WOWCompanionDB.chat and 'Chat enabled' or 'Chat disabled'])
    elseif msg == 'chat canales on' or msg == 'chat canales off' then
        WOWCompanionDB.chatCanales = msg == 'chat canales on'
        Print(L[WOWCompanionDB.chatCanales and 'Public channels enabled' or 'Public channels disabled'])
    else Print(L['Usage: /wowc on | off | send | status']); AvisoOpinar() end
end
events:On('PLAYER_ENTERING_WORLD', function() ns.LookEvent('PLAYER_ENTERING_WORLD'); Pedir('world'); Direccion(); AgendarGPS() end)
for _, event in ipairs({'BARBER_SHOP_OPEN', 'BARBER_SHOP_APPEARANCE_APPLIED', 'BARBER_SHOP_CLOSE'}) do
    events:On(event, function() ns.LookEvent(event); Pedir('event', 'look') end)
end
for evento in pairs(canalesChat) do
    events:On(evento, function(...) MensajeChat(evento, ...) end)
end
events:On('BAG_UPDATE_DELAYED', function() Pedir('event', 'bags') end)
for _, evento in ipairs({'UPDATE_PENDING_MAIL', 'MAIL_INBOX_UPDATE', 'MAIL_CLOSED'}) do
    events:On(evento, function() Pedir('event', 'mail') end)
end
for _, evento in ipairs({'QUEST_LOG_UPDATE', 'QUEST_WATCH_LIST_CHANGED', 'SUPER_TRACKING_CHANGED'}) do
    events:On(evento, function() Pedir('event', 'quest'); Pedir('event', 'log') end)
end
-- ShortestPathForever (OptionalDeps) ya publicó su API. Sólo los cambios de meta o de tramo, nunca 'guidance' (cada curva).
do
    local spf = type(ShortestPathForever) == 'table' and ShortestPathForever.API
    if type(spf) == 'table' and type(spf.Subscribe) == 'function' and (spf.version == 1 or spf.version == 2) then
        pcall(spf.Subscribe, function(cambios)
            if type(cambios) == 'table' and (cambios.started or cambios.changed or cambios.ended or cambios.leg or cambios.replan) then
                Pedir('event', 'ruta')
            end
        end)
    end
end
-- FarstriderLib (OptionalDeps) recalcula el grafo al aprender vuelos: la ruta se vuelve a pedir.
if type(FarstriderLib_API) == 'table' and type(FarstriderLib_API.RegisterRebuildCallback) == 'function' then
    pcall(FarstriderLib_API.RegisterRebuildCallback, function() Pedir('event', 'ruta') end)
end
events:On('USER_WAYPOINT_UPDATED', function() Pedir('event', 'ruta') end)
events:On('SKILL_LINES_CHANGED', function() Pedir('event', 'skill') end)
events:On('UPDATE_FACTION', function() Pedir('event', 'rep') end)
events:On('GROUP_ROSTER_UPDATE', function() Pedir('event', 'grupo') end)
for _, evento in ipairs({'UNIT_LEVEL', 'UNIT_CONNECTION'}) do
    events:On(evento, function(unidad)
        unidad = Texto(unidad)
        if unidad and (unidad:match('^party') or unidad:match('^raid')) then Pedir('event', 'grupo') end
    end)
end
for _, evento in ipairs({'HEARTHSTONE_BOUND', 'BAG_UPDATE_COOLDOWN'}) do
    events:On(evento, function() Pedir('event', 'hogar') end)
end
-- Se registra al cargar (OptionalDeps: TomTom carga antes) para no perder el destino que restaura al entrar.
if type(TomTom) == 'table' and type(TomTom.RegisterCallback) == 'function' then
    pcall(TomTom.RegisterCallback, ns, 'ArrowTargetChanged', function(_, uid)
        destinoFlecha = uid
        Pedir('event', 'dest'); Pedir('event', 'ruta')
    end)
end
events:On('PLAYER_EQUIPMENT_CHANGED', function() Pedir('event', 'equip'); Pedir('event', 'char'); Pedir('event', 'dur') end)
for _, evento in ipairs({'UPDATE_EXHAUSTION', 'PLAYER_UPDATE_RESTING'}) do
    events:On(evento, function() Pedir('event', 'char') end)
end
events:On('UPDATE_INVENTORY_DURABILITY', function() Pedir('event', 'dur') end)
events:On('UNIT_INVENTORY_CHANGED', function(unit)
    if Texto(unit) == 'player' then Pedir('event', 'equip') end
end)
for _, evento in ipairs({'PLAYER_MONEY', 'PLAYER_LEVEL_UP', 'PLAYER_XP_UPDATE', 'ZONE_CHANGED', 'ZONE_CHANGED_NEW_AREA', 'ZONE_CHANGED_INDOORS'}) do
    events:On(evento, function()
        Pedir('event', 'char')
        if evento == 'PLAYER_MONEY' or evento == 'PLAYER_LEVEL_UP' then Pedir('event', 'alts') end
        if evento:match('^ZONE_CHANGED') then EventoPosicion(); Pedir('event', 'quest'); Pedir('event', 'inst') end
        if evento == 'ZONE_CHANGED_NEW_AREA' then Pedir('event', 'ruta') end
    end)
end
for _, evento in ipairs({'PLAYER_STARTED_MOVING', 'PLAYER_STOPPED_MOVING', 'PLAYER_STOPPED_TURNING'}) do
    events:On(evento, EventoPosicion)
end
events:On('PLAYER_STARTED_TURNING', function() EventoPosicion(); AgendarGPS(true) end)
for _, evento in ipairs({'UNIT_ENTERED_VEHICLE', 'UNIT_EXITED_VEHICLE'}) do
    events:On(evento, function(unit) if Texto(unit) == 'player' then EventoPosicion() end end)
end
-- El taxi puede arrancar sin PLAYER_STARTED_MOVING. Las demás banderas no despiertan el GPS.
events:On('UNIT_FLAGS', function(unit)
    if Texto(unit) == 'player' and Limpiar(UnitOnTaxi('player')) == true then AgendarGPS() end
    if Texto(unit) == 'player' then RevisarVuelo() end
end)
events:On('PLAYER_CONTROL_GAINED', RevisarVuelo)
if type(hooksecurefunc) == 'function' and type(TakeTaxiNode) == 'function' then
    hooksecurefunc('TakeTaxiNode', function(slot)
        local ok, armado = pcall(ArmarVuelo, slot)
        if not ok or not armado then return end
        vuelo, vueloEnAire, vueloInicio = armado, false, GetTime()
        Pedir('event', 'taxi')
        C_Timer.After(10, RevisarVuelo)
    end)
end
KL:OnLogin(function()
    ns.InitLook()
    IniciarTips()
    if WOWCompanionDB.gps == nil then WOWCompanionDB.gps = true end
    -- La copia que instala la app agrega DesdeApp.lua (tools/publicar.ps1 del repo de la app): quien la tiene no necesita el aviso,
    -- y queda marcado para que tampoco salga si después actualiza desde CurseForge.
    if ns.desdeApp then WOWCompanionDB.avisoApp = true end
    if not WOWCompanionDB.avisoApp then
        WOWCompanionDB.avisoApp = true
        -- Unos segundos después, para que no se pierda entre los mensajes de entrada al mundo.
        C_Timer.After(8, AvisoApp)
    elseif not WOWCompanionDB.avisoOpinar then
        -- Una vez por cuenta (CONVENCION.md 3.1), en un ingreso distinto del aviso de la app para no juntar dos avisos.
        WOWCompanionDB.avisoOpinar = true
        C_Timer.After(8, AvisoOpinar)
    end
    if Syndicator and Syndicator.CallbackRegistry then
        Syndicator.CallbackRegistry:RegisterCallback('Ready', function() Pedir('ready', 'bank') end, ns)
        Syndicator.CallbackRegistry:RegisterCallback('BagCacheUpdate', function(_, personaje, cambios)
            local actual = Texto(Syndicator.API.GetCurrentCharacter())
            personaje, cambios = Texto(personaje), Limpiar(cambios)
            if actual and personaje == actual and type(cambios) == 'table' and
                ((type(cambios.bank) == 'table' and next(cambios.bank)) or
                (cambios.containerBags and cambios.containerBags.bank)) then Pedir('bank', 'bank') end
        end, ns)
    end
    Pedir('login', 'bank')
    LibStub('KnuLib-1.0'):RegisterCommand('companion', Comando, L['Bag companion: on | off | send | status'])
    SLASH_WOWC1 = '/wowc'
    SlashCmdList.WOWC = Comando
end)
