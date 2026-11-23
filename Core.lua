local _, ns = ...
local KL = LibStub('KnuLib-1.0')
local P, L = ns.Proto, ns.L
local Print = KL:NewPrinter('Compañon')
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
local tipos = {"bags", "bank", "equip", "char", "look", "hello", "pos"}
local sinRelleno = {pos=true}
local sucio, ultima, intentos, forzar, despues = {}, {}, {}, {}, {}
local seq, relleno = 0, 0
local ultimoEnvio, ultimoVolcado, fallo
local duracion, maxima = 0, 0
local ultimaPos, posVolcada
local gpsPendiente, ultimoGiro, facingAnterior, volcadoDiferido
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
        P.Escape(Texto(GetRealmName()) or '')}, ','), {}
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
local fotos = {hello=Hello, bags=Bolsas, bank=Banco, equip=Equipo, char=Personaje, look=ns.Look, pos=Posicion}
local function Enviar()
    local inicio, enviados = debugprofilestop(), {}
    sucio.tip = nil
    for _, tipo in ipairs(tipos) do
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
                and GetTime() - (ultimoVolcado or 0) >= 10) then necesitaRelleno = true end
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
        -- Al frenar antes de los 10 s, la última posición quedaría en el búfer sin volcar: se agenda un
        -- único volcado forzado para cuando se cumplan (auditoría de Gemini, 2026-11-23).
        if ultimaPos and not volcadoDiferido and PosDistinta(ultimaPos, posVolcada) then
            volcadoDiferido = true
            C_Timer.After(math.max(0, (ultimoVolcado or 0) + 10 - GetTime()), function()
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
    if not tipo then for _, t in ipairs(tipos) do Pedir(motivo, t) end; return end
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
    else Print(L['Usage: /wowc on | off | send | status']) end
end
events:On('PLAYER_ENTERING_WORLD', function() ns.LookEvent('PLAYER_ENTERING_WORLD'); Pedir('world'); Direccion(); AgendarGPS() end)
for _, event in ipairs({'BARBER_SHOP_OPEN', 'BARBER_SHOP_APPEARANCE_APPLIED', 'BARBER_SHOP_CLOSE'}) do
    events:On(event, function() ns.LookEvent(event); Pedir('event', 'look') end)
end
events:On('BAG_UPDATE_DELAYED', function() Pedir('event', 'bags') end)
events:On('PLAYER_EQUIPMENT_CHANGED', function() Pedir('event', 'equip'); Pedir('event', 'char') end)
events:On('UNIT_INVENTORY_CHANGED', function(unit)
    if Texto(unit) == 'player' then Pedir('event', 'equip') end
end)
for _, evento in ipairs({'PLAYER_MONEY', 'PLAYER_LEVEL_UP', 'PLAYER_XP_UPDATE', 'ZONE_CHANGED', 'ZONE_CHANGED_NEW_AREA', 'ZONE_CHANGED_INDOORS'}) do
    events:On(evento, function()
        Pedir('event', 'char')
        if evento:match('^ZONE_CHANGED') then EventoPosicion() end
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
end)
KL:OnLogin(function()
    ns.InitLook()
    IniciarTips()
    if WOWCompanionDB.gps == nil then WOWCompanionDB.gps = true end
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
