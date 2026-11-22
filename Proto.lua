local _, ns = ...
local P = {}
ns.Proto = P

-- Puro: los predicados se inyectan, para probar valores opacos sin WoW.
function P.EsSecreto(v, access, secret)
    if type(access) == 'function' then
        local ok, r = pcall(access, v)
        if ok then return r ~= true end
    end
    if type(secret) == 'function' then
        local ok, r = pcall(secret, v)
        if ok then return r == true end
    end
    return false
end

local escapes = { ['\\']='\\\\', ['|']='\\p', [';']='\\s', [',']='\\c', ['#']='\\h', ['\r']='\\r', ['\n']='\\n' }
function P.Escape(s) return (s:gsub('[\\|;,#\r\n]', escapes)) end

function P.Recortar(s, limite)
    if #s <= limite then return s end
    local fin = limite + 1
    while fin > 1 and s:byte(fin) >= 128 and s:byte(fin) < 192 do fin = fin - 1 end
    return s:sub(1, fin - 1)
end

-- Cada parte conserva los separadores: al concatenarlas se recupera la foto exacta.
function P.Partes(sid, seq, bolsas, registros)
    local cab = 'KC1|' .. sid .. '|' .. seq .. '|'
    local presupuesto = 3900 - #(cab .. '64|64|bags|')
    local partes, actual = {}, bolsas .. '#'
    assert(#actual <= presupuesto, 'Tamaños de bolsa demasiado largos')
    for i, registro in ipairs(registros) do
        local pieza = (i > 1 and ';' or '') .. registro
        assert(#pieza <= presupuesto, 'Registro demasiado largo')
        if #actual + #pieza > presupuesto then partes[#partes + 1], actual = actual, '' end
        actual = actual .. pieza
    end
    partes[#partes + 1] = actual
    assert(#partes <= 64, 'Demasiadas partes')
    for i, datos in ipairs(partes) do partes[i] = cab .. i .. '|' .. #partes .. '|bags|' .. datos end
    return partes
end

-- Relleno con 'x' como en la medición del 2026-11-22 (no se probó si el cliente recorta espacios finales).
function P.Relleno() return 'KCP' .. string.rep('x', 4086) end
