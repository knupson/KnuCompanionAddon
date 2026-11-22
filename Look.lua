local _, ns = ...
local P = ns.Proto
local function Safe(v)
    if not P.EsSecreto(v, canaccessvalue, issecretvalue) then return v end
end
local function Number(v)
    v = Safe(v)
    if type(v) == 'number' and v == v and v >= 0 and v < math.huge and v == math.floor(v) then return v end
end
local function Text(v) v = Safe(v); if type(v) == 'string' then return v end end
local function API(name)
    local api = Safe(C_BarberShop)
    local fn = type(api) == 'table' and Safe(api[name])
    if type(fn) ~= 'function' then return end
    local ok, value = pcall(fn)
    if ok then return Safe(value) end
end
local function Identity()
    local _, _, race = UnitRace('player')
    local sex = Number(UnitSex('player'))
    sex = sex == 2 and 0 or sex == 3 and 1 or nil
    local guid = UnitGUID and Text(UnitGUID('player'))
    local name = Text(UnitName('player'))
    local realm = GetRealmName and Text(GetRealmName())
    return guid or (name and realm and name .. '-' .. realm), Number(race), sex
end
local function Store()
    local db = Safe(WOWCompanionDB)
    if type(db) ~= 'table' then db = {}; WOWCompanionDB = db end
    if type(Safe(db.look)) ~= 'table' then db.look = {} end
    return db.look
end
local current, inBarber, attempted
local function Read()
    local categories, model = API('GetAvailableCustomizations'), Number(API('GetViewingChrModel'))
    if type(categories) ~= 'table' then return end
    local records, seen, complete, total = {}, {}, true, 0
    for _, raw in ipairs(categories) do
        local category = Safe(raw)
        local options = type(category) == 'table' and Safe(category.options)
        if type(options) ~= 'table' then complete = false else
            for _, rawOption in ipairs(options) do
                total = total + 1
                local option = Safe(rawOption)
                local id = type(option) == 'table' and Number(option.id)
                local index = type(option) == 'table' and Number(option.currentChoiceIndex)
                local choices = type(option) == 'table' and Safe(option.choices)
                local choice = type(choices) == 'table' and index and index > 0 and Safe(choices[index])
                local choiceID = type(choice) == 'table' and Number(choice.id)
                if id and id > 0 and choiceID and choiceID > 0 and not seen[id] then
                    records[#records + 1], seen[id] = id .. ',' .. choiceID, true
                else complete = false end
            end
        end
    end
    if #records == 0 then return end
    table.sort(records)
    return {model=model or 0, status=complete and total == #records and model and model > 0 and 'complete' or 'partial', records=records}
end
local function Capture(invalidate)
    local key, race, sex = Identity()
    local value = Read()
    if value and race and sex then
        value.race, value.sex = race, sex
        if key then Store()[key .. ':' .. race .. ':' .. sex .. ':' .. value.model] = value end
        current = {source='live', value=value, key=key}
    elseif invalidate then
        current = nil
        if key and race and sex then
            local prefix = key .. ':' .. race .. ':' .. sex .. ':'
            for savedKey in pairs(Store()) do
                if type(savedKey) == 'string' and savedKey:sub(1,#prefix) == prefix then Store()[savedKey] = nil end
            end
        end
    end
end
ns.InitLook = Store
function ns.LookEvent(event)
    if event == 'PLAYER_ENTERING_WORLD' then
        attempted = true; if not inBarber then Capture() end
    elseif event == 'BARBER_SHOP_OPEN' then
        -- Foto al entrar: antes de previsualizar. Cerrar/cancelar nunca guarda el preview.
        inBarber = true; Capture()
    elseif event == 'BARBER_SHOP_APPEARANCE_APPLIED' then Capture(true)
    elseif event == 'BARBER_SHOP_CLOSE' then inBarber = false end
end
function ns.Look()
    local key, race, sex = Identity()
    if not race or sex == nil then return 'none,absent,0,0,0', {} end
    if current and (current.key ~= key or current.value.race ~= race or current.value.sex ~= sex) then current = nil end
    if not attempted and not inBarber then attempted = true; Capture() end
    local value, source = current and current.value, current and current.source
    if not value and key then
        -- Sólo el modelo del mismo personaje/raza/sexo; si hay ambigüedad no inventar.
        local prefix, found = key .. ':' .. race .. ':' .. sex .. ':', nil
        for savedKey, savedValue in pairs(Store()) do
            if type(savedKey) == 'string' and savedKey:sub(1, #prefix) == prefix then
                if found then found = nil; break end
                found = Safe(savedValue)
            end
        end
        if type(found) == 'table' and type(Safe(found.records)) == 'table' then value, source = found, 'saved' end
    end
    if not value then return 'none,absent,' .. race .. ',' .. sex .. ',0', {} end
    -- SavedVariables también se filtran antes de serializar.
    local records = {}
    for _, raw in ipairs(Safe(value.records) or {}) do
        local record = Text(raw)
        if record and record:match('^%d+,%d+$') then records[#records + 1] = record end
    end
    if #records == 0 then return 'none,absent,' .. race .. ',' .. sex .. ',0', {} end
    local status = Text(value.status) == 'complete' and #records == #value.records and 'complete' or 'partial'
    return source .. ',' .. status .. ',' .. race .. ',' .. sex .. ',' .. (Number(value.model) or 0), records
end
