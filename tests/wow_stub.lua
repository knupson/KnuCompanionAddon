-- Forever no tiene math.randomseed (medido en el juego 2026-11-22): el stub la saca para que los tests fallen si se usa.
math.randomseed = nil
-- Reloj determinista: avanzar dispara únicamente los callbacks ya vencidos.
FAKE = {}
function FAKE.Reset()
    Syndicator, SYNDICATOR_DATA, C_TooltipInfo = nil, nil, nil
    FAKE.name, FAKE.class, FAKE.race, FAKE.ilvl, FAKE.locale = "Yaestoy Muerto", "PALADIN", "Humano", 32.16, "esMX"
    FAKE.raceID, FAKE.sex = 1, 2
    FAKE.equip, FAKE.money, FAKE.level, FAKE.zone, FAKE.subzone = {}, 123456, 31, "Ventormenta", "Distrito"
    FAKE.xp, FAKE.xpMax = 120, 1000
    FAKE.now, FAKE.timers, FAKE.lines, FAKE.chat, FAKE.handlers = 0, {}, {}, {}, {}
    FAKE.items, FAKE.sizes, FAKE.names, FAKE.calls = {}, {[0]=4, [1]=0, [2]=0, [3]=0, [4]=0, [5]=0}, {}, 0
    FAKE.fail, FAKE.maxTimers, FAKE.failAt = false, 0, nil
    FAKE.map, FAKE.x, FAKE.y, FAKE.facing = nil, nil, nil, nil
    FAKE.moving, FAKE.taxi, FAKE.vehicle, FAKE.pointSecret = false, false, false, false
    FAKE.log = ''
    canaccessvalue = function(v) return not rawequal(v, FAKE.secret) end
    issecretvalue = function(v) return rawequal(v, FAKE.secret) end
    SlashCmdList, NUM_BAG_SLOTS = {}, 4
    FAKE.ns = {}
    WOWCompanionDB, C_BarberShop = nil, nil
    assert(loadfile('Locales/Locales.lua'))('WOWCompanion', FAKE.ns)
    assert(loadfile('Proto.lua'))('WOWCompanion', FAKE.ns)
    assert(loadfile('Look.lua'))('WOWCompanion', FAKE.ns)
    assert(loadfile('Core.lua'))('WOWCompanion', FAKE.ns)
end
FAKE.secret = setmetatable({}, {
    __tostring=function() error('Se convirtió un secreto') end,
    __concat=function() error('Se concatenó un secreto') end,
    __lt=function() error('Se comparó un secreto') end,
    __le=function() error('Se comparó un secreto') end,
    __eq=function() error('Se comparó un secreto') end,
    __index=function() error('Se leyó un secreto') end,
})
function GetTime() return FAKE.now end
function GetServerTime() return 1795366800 end
function debugprofilestop() return FAKE.now * 1000 end
C_Timer = { After = function(delay, fn)
    FAKE.timers[#FAKE.timers + 1] = {at=FAKE.now + delay, fn=fn}
    FAKE.maxTimers = math.max(FAKE.maxTimers, #FAKE.timers)
end }
C_Container = {
    GetContainerNumSlots=function(bag) return FAKE.sizes[bag] end,
    GetContainerItemInfo=function(bag, slot) return FAKE.items[bag .. ':' .. slot] end,
}
C_Item = {GetItemInfo=function(id) return FAKE.names[id] end}
C_Log = {LogMessage=function(line)
    FAKE.calls = FAKE.calls + 1
    if FAKE.fail or FAKE.failAt == FAKE.calls then error('Fallo simulado') end
    FAKE.lines[#FAKE.lines + 1] = {text=line, time=FAKE.now}
    -- General.log agrega CRLF; no simular saltos LF sueltos al medir el canal.
    FAKE.log = FAKE.log .. line .. '\r\n'
end}
C_Map = {
    GetBestMapForUnit=function(unit) assert(unit == 'player'); return FAKE.map end,
    GetPlayerMapPosition=function(map, unit)
        assert(map == FAKE.map and unit == 'player')
        if FAKE.pointSecret then return FAKE.secret end
        return {GetXY=function() return FAKE.x, FAKE.y end}
    end,
}
function GetPlayerFacing() return FAKE.facing end
function IsPlayerMoving() return FAKE.moving end
function UnitOnTaxi(unit) assert(unit == 'player'); return FAKE.taxi end
function UnitInVehicle(unit) assert(unit == 'player'); return FAKE.vehicle end
local KL = {}
function KL:NewLocale(es, en)
    -- Simula un cliente en inglés: también tiene que recibir los textos castellanos.
    return setmetatable(en or {}, {__index=function(_, k) return k end})
end
function KL:NewPrinter() return function(s) FAKE.chat[#FAKE.chat + 1] = s end end
function KL:NewEvents()
    return {On=function(_, event, fn) FAKE.handlers[event] = fn end}
end
function KL:OnLogin(fn) fn() end
function KL:RegisterCommand(name, handler, help) FAKE.command, FAKE.commandName = handler, name end
function LibStub(name) assert(name == 'KnuLib-1.0'); return KL end
function FAKE.Event(event, ...) assert(FAKE.handlers[event])(...) end
function FAKE.Advance(delta)
    local target = FAKE.now + delta
    while true do
        local index, at
        for i, timer in ipairs(FAKE.timers) do
            if timer.at <= target and (not at or timer.at < at) then index, at = i, timer.at end
        end
        if not index then break end
        local timer = table.remove(FAKE.timers, index)
        FAKE.now = at; timer.fn()
    end
    FAKE.now = target
end
function FAKE.Item(fields) FAKE.items['0:1'] = fields or {itemID=248689, stackCount=2, quality=3, iconFileID=134400,
    hyperlink='|cnIQ1:|Hitem:248689::::::::31:1486:::::::::|h[Cajón arrebatado: Curiosidades de oficial]|h|r'} end
function FAKE.Photos(tipo)
    tipo = tipo or "bags"
    local result = {}
    for _, line in ipairs(FAKE.lines) do if line.text:match('^KC1|') and (tipo == '*' or line.text:find('|' .. tipo .. '|',1,true)) then result[#result+1] = line end end
    return result
end

function GetInventoryItemID(_, slot) return FAKE.equip[slot] and FAKE.equip[slot].id end
function GetInventoryItemQuality(_, slot) return FAKE.equip[slot] and FAKE.equip[slot].quality end
function GetInventoryItemTexture(_, slot) return FAKE.equip[slot] and FAKE.equip[slot].icon end
function GetInventoryItemLink(_, slot) return FAKE.equip[slot] and FAKE.equip[slot].link end
function GetMoney() return FAKE.money end
function UnitLevel() return FAKE.level end
function UnitXP() return FAKE.xp end
function UnitXPMax() return FAKE.xpMax end
function GetZoneText() return FAKE.zone end
function GetSubZoneText() return FAKE.subzone end
function FAKE.Syndicator(ready, character)
    FAKE.ready, FAKE.character, FAKE.callbacks = ready, character, {}
    SYNDICATOR_DATA = {Characters={}}
    Syndicator = {API={IsReady=function() return FAKE.ready end,
        GetCurrentCharacter=function() return FAKE.character end,
        GetByCharacterFullName=function(name) return SYNDICATOR_DATA.Characters[name] end},
        CallbackRegistry={RegisterCallback=function(_, event, fn, owner)
            assert(owner == FAKE.ns); FAKE.callbacks[event] = fn
        end}}
    -- Se vuelve a cargar Core para ejecutar el login con Syndicator presente.
    FAKE.timers, FAKE.handlers = {}, {}
    assert(loadfile('Core.lua'))('WOWCompanion', FAKE.ns)
end
function FAKE.Callback(event, ...) FAKE.callbacks[event](FAKE.ns, ...) end

function UnitName() return FAKE.name end
function UnitClass() return 'Paladín', FAKE.class end
function UnitRace() return FAKE.race, 'Human', FAKE.raceID end
function UnitSex() return FAKE.sex end
function GetAverageItemLevel() return 999, FAKE.ilvl end
function GetLocale() return FAKE.locale end

function UnitGUID() return "Player-TEST-" .. (type(FAKE.name) == "string" and FAKE.name or "secreto") end
function GetRealmName() return "Prueba" end

C_AddOns = {GetAddOnMetadata=function() return "0.9.0" end}
function GetBuildInfo() return "16.0.1", "1", "", 16001 end
