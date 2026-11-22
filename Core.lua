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
local enabled, pending, force = true, false, false
local seq, intentos, relleno = 0, 0, 0
local ultimaFoto, ultimoEnvio, ultimoVolcado, fallo
local duracion, maxima = 0, 0

local function Foto()
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

local Pedir
local function Enviar()
    local inicio = debugprofilestop()
    local bolsas, registros, faltaNombre = Foto()
    local foto = bolsas .. '#' .. table.concat(registros, ';')
    local forzado = force
    force = false
    if forzado or foto ~= ultimaFoto then
        seq, intentos = seq + 1, intentos + 1
        local ok = true
        for _, linea in ipairs(P.Partes(sid, seq, bolsas, registros)) do
            if not pcall(C_Log.LogMessage, linea) then ok = false end
        end
        for _ = 1, 12 do
            if pcall(C_Log.LogMessage, P.Relleno()) then relleno = relleno + 4089 else ok = false end
        end
        ultimoVolcado = GetTime()
        if ok then ultimaFoto, ultimoEnvio, fallo = foto, GetTime(), nil else fallo = L['Log write failed'] end
        if (not ok or faltaNombre) and intentos < 3 then Pedir('retry') end
    end
    duracion = debugprofilestop() - inicio
    maxima = math.max(maxima, duracion)
end

-- Única entrada: los eventos y reintentos comparten un solo timer pendiente.
Pedir = function(motivo)
    if not enabled then return end
    if motivo == 'send' or motivo == 'retry' then force = true end
    if pending then return end
    if motivo ~= 'retry' then intentos = 0 end
    pending = true
    local espera = motivo == 'retry' and 2 or 1
    if ultimoVolcado then espera = math.max(espera, 1 - (GetTime() - ultimoVolcado)) end
    C_Timer.After(espera, function()
        pending = false
        if not enabled then return end
        if ultimoVolcado and GetTime() - ultimoVolcado < 1 then Pedir('retry'); return end
        Enviar()
    end)
end
ns.Pedir = Pedir

local function Comando(msg)
    msg = (msg or ''):match('^%s*(.-)%s*$'):lower()
    if msg == 'off' then enabled, force = false, false; Print(L['Disabled'])
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
events:On('BAG_UPDATE_DELAYED', function() Pedir('bags') end)
KL:OnLogin(function()
    LibStub('KnuLib-1.0'):RegisterCommand('companion', Comando, L['Bag companion: on | off | send | status'])
    SLASH_WOWC1 = '/wowc'
    SlashCmdList.WOWC = Comando
end)
