-- Mide cuánto tarda una tanda completa de Enviar con datos pesados, sobre el stub de las pruebas.
-- Uso: luajit tools/medir_envio.lua   (desde la raíz del repo)
-- Es una cota de LuaJIT en la PC: el cliente del juego corre Lua sin JIT y además paga las llamadas reales a la API.
dofile('tests/wow_stub.lua')
FAKE.Reset()

-- Bolsas llenas: 5 bolsas de 36 casillas con objetos distintos.
FAKE.sizes = {[0]=36, [1]=36, [2]=36, [3]=36, [4]=36, [5]=0}
for bag = 0, 4 do
    for slot = 1, 36 do
        local id = 1000 + bag * 100 + slot
        FAKE.items[bag .. ':' .. slot] = {itemID=id, stackCount=slot, quality=slot % 5, iconFileID=id,
            hyperlink='|Hitem:' .. id .. '::::::::60:::::|h[Objeto ' .. id .. ', con coma; y punto y coma]|h'}
    end
end
-- Equipo completo.
for slot = 1, 19 do FAKE.equip[slot] = {id=2000 + slot, quality=4, icon=1, link='|Hitem:' .. (2000 + slot) .. '|h[Pieza]|h', dur=50, durMax=100} end
-- Listas largas de los tipos nuevos.
local lineas, facciones, monedas = {}, {}, {}
for i = 1, 80 do lineas[i] = {isHeader=(i % 10 == 1), name='Habilidad ' .. i, skillID=i, skillLineCategoryID=6, parentSkillLineID=0, rank=i, maxRank=300, modifier=0} end
for i = 1, 100 do facciones[i] = {isHeader=(i % 10 == 1), name='Facción ' .. i, factionID=i, reaction=5, currentStanding=i * 10, currentReactionThreshold=0, nextReactionThreshold=3000, atWarWith=false, isWatched=false} end
for i = 1, 80 do monedas[i] = {isHeader=(i % 10 == 1), name='Moneda ' .. i, currencyID=i, quantity=i, maxQuantity=0, iconFileID=i, isHeaderExpanded=true} end
C_SkillInfo = {GetNumSkillLines=function() return #lineas end, GetSkillLineInfo=function(i) return lineas[i] end}
C_Reputation = {GetNumFactions=function() return #facciones end, GetFactionDataByIndex=function(i) return facciones[i] end}
C_CurrencyInfo = {GetCurrencyListSize=function() return #monedas end, GetCurrencyListInfo=function(i) return monedas[i] end}
local auras = {}
for i = 1, 40 do auras[i] = {spellId=i, name='Aura ' .. i, icon=i, applications=0, duration=600, expirationTime=FAKE.now + 300} end
C_UnitAuras = {GetAuraDataByIndex=function(_, i) return auras[i] end}

-- El stub devuelve un debugprofilestop fijo: para medir de verdad se usa el reloj del proceso, en milisegundos.
debugprofilestop = function() return os.clock() * 1000 end
-- Recarga Core con las APIs de arriba presentes y mide la primera tanda (todos los tipos) y una segunda forzada.
FAKE.timers, FAKE.handlers = {}, {}
assert(loadfile('Core.lua'))('WOWCompanion', FAKE.ns)
FAKE.Event('PLAYER_ENTERING_WORLD'); FAKE.Advance(1)
SlashCmdList.WOWC('status'); print('primera tanda: ' .. FAKE.chat[#FAKE.chat])
SlashCmdList.WOWC('send'); FAKE.Advance(1)
SlashCmdList.WOWC('status'); print('tanda forzada: ' .. FAKE.chat[#FAKE.chat])
local bytes = 0
for _, l in ipairs(FAKE.lines) do bytes = bytes + #l.text end
print(string.format('líneas escritas: %d, bytes: %d', #FAKE.lines, bytes))
