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
local server, perfil = Numero(GetServerTime()) or 0, Numero(debugprofilestop()) or 0
math.randomseed((server + math.floor(perfil)) % 2147483647)
local sid = string.format('%08x', (server + math.random(0, 2147483646)) % 4294967296)
local enabled, pending = true, false
local tipos = {"bags", "bank", "equip", "char"}
local sucio, ultima, intentos, forzar, despues = {}, {}, {}, {}, {}
local seq, relleno = 0, 0
local ultimoEnvio, ultimoVolcado, fallo
local duracion, maxima = 0, 0

local function Bolsas()
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
                    registros[#registros + 1] = table.concat({bag, slot, id or '', count or '', quality or '', icon or '',
                        P.Escape(P.Recortar(name, 200))}, ',')
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
                        local nombre = Nombre(id, Texto(info.itemLink))
                        registros[#registros + 1] = table.concat({tab, slot, id, Numero(info.itemCount) or '',
                            Numero(info.quality) or '', Numero(info.iconTexture) or '', nombre}, ',')
                    end
                end
            end
        end
    end
    if #cab == 1 then return 'nodata', {} end
    return table.concat(cab, ';'), registros
end

local function Equipo()
    local registros, faltan = {}, false
    for slot = 1, 19 do
        local id = Numero(GetInventoryItemID('player', slot))
        if id then
            local calidad = Numero(GetInventoryItemQuality('player', slot))
            local icono = Numero(GetInventoryItemTexture('player', slot))
            local nombre, falta = Nombre(id, Texto(GetInventoryItemLink('player', slot)))
            faltan = faltan or falta or calidad == nil
            registros[#registros + 1] = table.concat({slot, id, calidad or '', icono or '', nombre}, ',')
        end
    end
    return '', registros, faltan
end

local function Personaje()
    return table.concat({Numero(UnitLevel('player')) or '', Numero(GetMoney()) or '',
        P.Escape(P.Recortar(Texto(GetZoneText()) or '', 200)),
        P.Escape(P.Recortar(Texto(GetSubZoneText()) or '', 200))}, ','), {}
end
local fotos = {bags=Bolsas, bank=Banco, equip=Equipo, char=Personaje}
local Pedir
local function Enviar()
    local inicio, enviados = debugprofilestop(), {}
    for _, tipo in ipairs(tipos) do
        if sucio[tipo] then
            sucio[tipo] = nil
            local cab, registros, faltan = fotos[tipo]()
            if not cab then
                -- Syndicator todavía sin personaje: se reintenta a los 2 s, hasta 3 veces por pedido.
                intentos[tipo] = (intentos[tipo] or 0) + 1
                if intentos[tipo] < 3 then Pedir('retry', tipo) end
            else
                local foto = cab .. '#' .. table.concat(registros, ';')
                local fuerza = forzar[tipo]
                forzar[tipo] = nil
                if fuerza or foto ~= ultima[tipo] then
                    seq, intentos[tipo] = seq + 1, (intentos[tipo] or 0) + 1
                    local ok, partes = pcall(P.Partes, sid, seq, tipo, cab, registros)
                    if ok then
                        for _, linea in ipairs(partes) do
                            if not pcall(C_Log.LogMessage, linea) then ok = false end
                        end
                        enviados[#enviados + 1] = {tipo=tipo, foto=foto, ok=ok, faltan=faltan}
                    else
                        fallo = tostring(partes) -- El encabezado inválido no se manda.
                    end
                end
            end
        end
    end
    if #enviados > 0 then
        local rellenoOk = true
        for _ = 1, 12 do
            if pcall(C_Log.LogMessage, P.Relleno()) then relleno = relleno + 4089 else rellenoOk = false end
        end
        ultimoVolcado = GetTime()
        for _, envio in ipairs(enviados) do
            local tipo = envio.tipo
            if envio.ok and rellenoOk then
                ultima[tipo], ultimoEnvio = envio.foto, GetTime()
            else fallo = L['Log write failed'] end
            if (not envio.ok or not rellenoOk or envio.faltan) and intentos[tipo] < 3 then Pedir('retry', tipo) end
        end
        local todosOk = rellenoOk
        for _, envio in ipairs(enviados) do todosOk = todosOk and envio.ok end
        if todosOk then fallo = nil end
    end
    duracion = debugprofilestop() - inicio
    maxima = math.max(maxima, duracion)
end

-- Un único timer agrupa eventos; cada tipo conserva su estado y su plazo de reintento.
Pedir = function(motivo, tipo)
    if not enabled then return end
    if not tipo then for _, t in ipairs(tipos) do Pedir(motivo, t) end; return end
    local plazoAnterior = sucio[tipo] and despues[tipo]
    sucio[tipo] = true
    if motivo == 'send' or motivo == 'retry' then forzar[tipo] = true end
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

local function Comando(msg)
    msg = (msg or ''):match('^%s*(.-)%s*$'):lower()
    if msg == 'off' then enabled = false; sucio, forzar = {}, {}; Print(L['Disabled'])
    elseif msg == 'on' then enabled = true; Print(L['Enabled']); Pedir('send')
    elseif msg == 'send' then Pedir('send')
    elseif msg == 'status' then
        Print(string.format(L['sid=%s seq=%d enabled=%s last=%s padding=%d bytes failure=%s duration=%.2f ms max=%.2f ms'],
            sid, seq, L[enabled and 'yes' or 'no'], ultimoEnvio and tostring(ultimoEnvio) or L['none'],
            relleno, fallo or L['none'], duracion, maxima))
    else Print(L['Usage: /wowc on | off | send | status']) end
end
local events = KL:NewEvents()
events:On('PLAYER_ENTERING_WORLD', function() Pedir('world') end)
events:On('BAG_UPDATE_DELAYED', function() Pedir('event', 'bags') end)
events:On('PLAYER_EQUIPMENT_CHANGED', function() Pedir('event', 'equip') end)
events:On('UNIT_INVENTORY_CHANGED', function(unit)
    if Texto(unit) == 'player' then Pedir('event', 'equip') end
end)
for _, evento in ipairs({'PLAYER_MONEY', 'PLAYER_LEVEL_UP', 'ZONE_CHANGED', 'ZONE_CHANGED_NEW_AREA', 'ZONE_CHANGED_INDOORS'}) do
    events:On(evento, function() Pedir('event', 'char') end)
end
KL:OnLogin(function()
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
