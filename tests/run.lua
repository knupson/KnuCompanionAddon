dofile('tests/wow_stub.lua')
local total, fallas = 0, 0
local function test(nombre, fn)
    total = total + 1
    FAKE.Reset()
    local ok, err = pcall(fn, FAKE.ns.Proto)
    if not ok then fallas = fallas + 1; print('FALLÓ: ' .. nombre .. ': ' .. tostring(err)) end
end
local function igual(a,b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
local function datos() return FAKE.Photos()[1].text:match('|bags|(.*)$') end
local function iniciar() FAKE.Event('PLAYER_ENTERING_WORLD'); FAKE.Advance(1) end

test('escape en una pasada e ida y vuelta', function(P)
    local original = '\\|;,#\r\n ñ'
    local escaped = P.Escape(original)
    igual(escaped, '\\\\\\p\\s\\c\\h\\r\\n ñ')
    local tabla = {['\\']='\\',p='|',s=';',c=',',h='#',r='\r',n='\n'}
    igual(escaped:gsub('\\(.)', tabla), original)
end)
test('recorte UTF-8 en todos los límites', function(P)
    local texto = 'aé中😀z'
    local validos = {[0]='',[1]='a',[2]='a',[3]='aé',[4]='aé',[5]='aé',[6]='aé中',
        [7]='aé中',[8]='aé中',[9]='aé中',[10]='aé中😀',[11]=texto}
    for n=0,11 do igual(P.Recortar(texto,n), validos[n]) end
end)
test('fragmentación por bytes sin cortar registros', function(P)
    local registros = {}
    for i=1,140 do registros[i] = '0,' .. i .. ',1,1,2,3,' .. P.Escape(string.rep('ñ|', 60)) end
    local partes = P.Partes('0123abcd',999999999,'bags','0,140',registros)
    assert(#partes >= 3)
    local reconstruido = {}
    for i, linea in ipairs(partes) do
        assert(#linea <= 3900)
        igual(linea:match('^KC1|0123abcd|999999999|(%d+)|'), tostring(i))
        reconstruido[i] = linea:match('|bags|(.*)$')
        if i > 1 then assert(reconstruido[i]:sub(1,1) == ';') end
    end
    igual(table.concat(reconstruido), '0,140#' .. table.concat(registros,';'))
end)
test('nombre largo recortado antes de escapar', function()
    FAKE.Item({itemID=1,hyperlink='|h[' .. string.rep('ñ|',200) .. ']|h'})
    iniciar()
    local nombre = datos():match('#0,1,1,,,,(.*)')
    assert(nombre and #nombre < 401)
end)
test('secretos en todos los campos sin compararlos ni convertirlos', function()
    local S = FAKE.secret
    FAKE.Item({itemID=S,stackCount=S,quality=S,iconFileID=S,hyperlink=S})
    iniciar(); igual(datos():match('#(.*)'), '0,1,,,,,,,')
end)
test('tabla de objeto y tamaño secretos', function()
    FAKE.items['0:1'], FAKE.sizes[1], FAKE.sizes[5] = FAKE.secret, FAKE.secret, FAKE.secret
    iniciar(); igual(datos(), '0,4;1,;2,0;3,0;4,0#')
end)
test('predicados de secretos y fallback', function(P)
    assert(P.EsSecreto(1, function() error('no disponible') end, function() return true end))
    assert(P.EsSecreto(1, function() return false end, function() return false end))
    assert(not P.EsSecreto(1,nil,nil))
end)
test('foto inicial y doce líneas de relleno', function()
    FAKE.Item(); iniciar(); igual(#FAKE.lines,23)
    assert(datos():find('Cajón arrebatado',1,true))
    assert(FAKE.lines[1].text:match('^KC1|%x%x%x%x%x%x%x%x|1|1|1|bags|'))
    for i=12,23 do igual(#FAKE.lines[i].text,4089); igual(FAKE.lines[i].text:sub(1,3),'KCP') end
end)
test('sin cambios no hay datos ni relleno', function()
    FAKE.Item(); iniciar(); FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(1); igual(#FAKE.lines,23)
end)
test('ráfaga agrupa eventos en un timer', function()
    for _=1,100 do FAKE.Event('BAG_UPDATE_DELAYED') end
    igual(#FAKE.timers,1); FAKE.Advance(1); igual(#FAKE.Photos(),1); igual(FAKE.maxTimers,1)
end)
test('send fuerza sin cambios y respeta el segundo', function()
    iniciar(); SlashCmdList.WOWC('send'); FAKE.Advance(0.99); igual(#FAKE.Photos(),1)
    FAKE.Advance(0.01); igual(#FAKE.Photos(),2)
end)
test('off invalida el callback pendiente', function()
    FAKE.Event('PLAYER_ENTERING_WORLD'); SlashCmdList.WOWC('off'); FAKE.Advance(10)
    igual(#FAKE.lines,0); SlashCmdList.WOWC('send'); igual(#FAKE.timers,0)
end)
test('off y on mantienen un único timer', function()
    FAKE.Event('BAG_UPDATE_DELAYED'); SlashCmdList.WOWC('off'); SlashCmdList.WOWC('on')
    igual(#FAKE.timers,1); FAKE.Advance(1); igual(#FAKE.Photos(),1)
end)
test('fallo reintenta dos veces y status informa', function()
    FAKE.fail=true; iniciar(); SlashCmdList.WOWC('status')
    assert(FAKE.chat[#FAKE.chat]:find('Falló',1,true))
    FAKE.Advance(1.99); igual(FAKE.calls,23)
    FAKE.Advance(20); igual(FAKE.calls,69); igual(#FAKE.timers,0); igual(FAKE.maxTimers,1)
end)
test('foto fallida no queda marcada como enviada', function()
    FAKE.fail=true; iniciar(); FAKE.fail=false; FAKE.Advance(2)
    igual(#FAKE.Photos(),1); assert(FAKE.Photos()[1].text:find('|12|1|1|bags|',1,true))
    FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(1); igual(#FAKE.Photos(),1)
end)
test('fallo en una parte conserva el reintento', function()
    FAKE.failAt=1; iniciar(); FAKE.Advance(2); igual(#FAKE.Photos(),1)
end)
test('fallo de relleno tampoco confirma la foto', function()
    FAKE.failAt=12; iniciar(); FAKE.Advance(2); igual(#FAKE.Photos(),2)
end)
test('Hello funciona sin C_AddOns o si no devuelve nada', function()
    local old = C_AddOns
    C_AddOns = nil
    GetAddOnMetadata = function() return nil end
    iniciar()
    C_AddOns = old
    GetAddOnMetadata = nil
    assert(#FAKE.lines > 0)
    assert(FAKE.lines[6].text:match('|hello|0%.0%.0,16'))
end)
test('off durante reintento impide el envío', function()
    FAKE.fail=true; iniciar(); SlashCmdList.WOWC('off'); FAKE.Advance(10); igual(FAKE.calls,23)
end)
test('nombre por hipervínculo real', function()
    FAKE.Item(); iniciar(); assert(datos():find('Cajón arrebatado: Curiosidades de oficial',1,true))
    igual(#FAKE.timers,0)
end)
test('nombre por GetItemInfo', function()
    FAKE.Item({itemID=123}); FAKE.names[123]='Nombre de caché'; iniciar()
    assert(datos():find('Nombre de caché',1,true)); igual(#FAKE.timers,0)
end)
test('hipervínculo sin nombre usa GetItemInfo', function()
    FAKE.Item({itemID=123,hyperlink='|h[]|h'}); FAKE.names[123]='Nombre de caché'; iniciar()
    assert(datos():find('Nombre de caché',1,true)); igual(#FAKE.timers,0)
end)
test('nombre pendiente se resuelve a los dos segundos', function()
    FAKE.Item({itemID=123}); iniciar(); FAKE.names[123]='Resuelto'; FAKE.Advance(2)
    igual(#FAKE.Photos(),2); assert(FAKE.Photos()[2].text:find('Resuelto',1,true)); igual(#FAKE.timers,0)
end)
test('nombre ausente y nombre secreto agotan tres intentos', function()
    FAKE.Item({itemID=123}); FAKE.names[123]=FAKE.secret; iniciar(); FAKE.Advance(20)
    igual(#FAKE.Photos(),3); igual(#FAKE.timers,0)
end)
test('bolsa 5 sólo cuando tiene casillas', function()
    iniciar(); assert(not datos():find(';5,',1,true))
    FAKE.sizes[5]=2; FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(1)
    assert(FAKE.Photos()[2].text:find(';5,2#',1,true))
end)
test('comandos registrados y métricas de status', function()
    igual(SLASH_WOWC1,'/wowc'); igual(FAKE.commandName,'companion')
    iniciar(); FAKE.command('status')
    local status = FAKE.chat[#FAKE.chat]
    assert(status:find('relleno=49068',1,true)); assert(status:find('duración=',1,true)); assert(status:find('máxima=',1,true))
end)
test('encabezado genérico grande queda entero y el excesivo falla', function(P)
    local cab = string.rep('a', 3800)
    local partes = P.Partes('0123abcd',1,'bank',cab,{string.rep('b',100)})
    igual(#partes,2); assert(partes[1]:find(cab .. '#',1,true))
    assert(not pcall(P.Partes,'0123abcd',1,'bank',string.rep('a',3900),{}))
end)
test('todos los tipos comparten doce rellenos y sin cambios no mandan', function()
    iniciar(); igual(#FAKE.Photos('*'),11); igual(#FAKE.lines,23)
    FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Event('PLAYER_EQUIPMENT_CHANGED')
    FAKE.Event('BARBER_SHOP_CLOSE'); FAKE.Advance(1); igual(#FAKE.lines,23)
    SlashCmdList.WOWC('send'); FAKE.Advance(1); igual(#FAKE.Photos('*'),22); igual(#FAKE.lines,46)
end)
test('sin Syndicator manda nosyn una vez', function()
    iniciar(); igual(FAKE.Photos('bank')[1].text:match('|bank|(.*)'), 'nosyn#')
    FAKE.Event('PLAYER_ENTERING_WORLD'); FAKE.Advance(1); igual(#FAKE.Photos('bank'),1)
end)
test('Syndicator espera Ready y personaje disponible', function()
    FAKE.Syndicator(false,nil); iniciar(); igual(#FAKE.Photos('bank'),0)
    FAKE.ready = true; FAKE.Callback('Ready'); FAKE.Advance(1); igual(#FAKE.Photos('bank'),0)
    FAKE.character = 'Actual'; FAKE.Callback('Ready'); FAKE.Advance(1)
    assert(FAKE.Photos('bank')[1].text:find('nodata#',1,true))
end)
test('banco realista con huecos vacíos y callback filtrado', function()
    FAKE.Syndicator(true,'Yaestoy Muerto-PvE')
    SYNDICATOR_DATA.Characters[FAKE.character] = {bank={},bankTabs={{slots={
        {itemID=2835,itemCount=3,quality=1,iconTexture=135232,itemLink='|h[Piedra férrea]|h'}, {}, {}}},
        {slots={{},{}}}, {slots={{}}}}}
    iniciar()
    local foto = FAKE.Photos('bank')[1].text
    assert(foto:find('ok;1,3;2,2;3,1#1,1,2835,3,1,135232,Piedra férrea',1,true))
    assert(not foto:find(FAKE.character,1,true))
    FAKE.Callback('BagCacheUpdate','Otro',{bank={[1]=true}}); igual(#FAKE.timers,0)
    FAKE.Callback('BagCacheUpdate',FAKE.character,{bank={},containerBags={bags=true}}); igual(#FAKE.timers,0)
    SYNDICATOR_DATA.Characters[FAKE.character].bankTabs[1].slots[1].itemCount=20
    FAKE.Callback('BagCacheUpdate',FAKE.character,{bank={[1]=true}}); FAKE.Advance(1)
    igual(#FAKE.Photos('bank'),2)
    FAKE.Callback('BagCacheUpdate',FAKE.character,{bank={},containerBags={bank=true}})
    igual(#FAKE.timers,1)
end)
test('equipo vacío y reintento de nombre y calidad tardíos', function()
    FAKE.equip[16]={id=123,icon=456}; iniciar()
    assert(FAKE.Photos('equip')[1].text:find('#16,123,,456,',1,true))
    FAKE.equip[16].link='|h[Espada]|h'; FAKE.equip[16].quality=2
    FAKE.Advance(1.99); igual(#FAKE.Photos('equip'),1)
    FAKE.Advance(0.01); igual(#FAKE.Photos('equip'),2); igual(#FAKE.timers,0)
    FAKE.Event('UNIT_INVENTORY_CHANGED','target'); igual(#FAKE.timers,0)
    FAKE.equip={}; FAKE.Event('UNIT_INVENTORY_CHANGED','player'); FAKE.Advance(1)
    assert(FAKE.Photos('equip')[3].text:match('|equip|#$'))
end)
test('equipo agota tres intentos sin calidad', function()
    FAKE.equip[1]={id=1,link='|h[Casco]|h'}; iniciar(); FAKE.Advance(20)
    igual(#FAKE.Photos('equip'),3); igual(#FAKE.timers,0)
end)
test('personaje escapa zona y sanitiza oro secreto', function()
    FAKE.money=FAKE.secret; FAKE.zone='Zona|con,coma'; iniciar()
    assert(FAKE.Photos('char')[1].text:find('31,,Zona\\pcon\\ccoma,Distrito,Yaestoy Muerto,PALADIN,Humano,32.2,1,0,120,1000,Prueba#',1,true))
    FAKE.money=42; FAKE.Event('PLAYER_MONEY'); FAKE.Advance(1)
    igual(#FAKE.Photos('char'),2); igual(#FAKE.Photos('bags'),1)
end)
test('eventos continuos no postergan indefinidamente el envío', function()
    iniciar(); FAKE.Item(); FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(0.5)
    FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(0.5)
    igual(#FAKE.Photos(),2)
end)
test('reintento de equipo y evento de bolsas comparten un timer', function()
    FAKE.equip[1]={id=1}; iniciar(); FAKE.Advance(0.5)
    FAKE.Item(); FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(1.5)
    igual(#FAKE.Photos(),2); igual(#FAKE.Photos('equip'),2); igual(FAKE.maxTimers,1)
end)
test('mensajes castellanos aun con cliente en inglés', function()
    igual(FAKE.ns.L['Enabled'],'Activado')
    igual(FAKE.ns.L['Log write failed'],'Falló la escritura al log')
end)

local function ActivarTips(fn)
    C_TooltipInfo = {GetBagItem=fn, GetInventoryItem=fn, GetHyperlink=fn}
end
local function UnTip(texto)
    return {lines={{leftText=texto or 'Nombre', rightText='Derecha',
        leftColor={GenerateHexColor=function() return 'ffa335ee' end}}}}
end
local function Link(id) return '|Hitem:' .. id .. ':0:0:31|h[Objeto]|h' end

test('itemString completo en bolsas equipo y banco', function()
    FAKE.Syndicator(true,'Actual')
    local link = Link(100)
    FAKE.Item({itemID=100,hyperlink=link})
    FAKE.equip[1]={id=100,quality=4,link=link}
    SYNDICATOR_DATA.Characters.Actual = {bankTabs={{slots={{itemID=100,itemLink=link}}}}}
    local llamadas = {}
    ActivarTips(function(a,b) llamadas[#llamadas+1]={a,b}; return UnTip() end)
    iniciar()
    for _, tipo in ipairs({'bags','bank','equip'}) do assert(FAKE.Photos(tipo)[1].text:find(',item:100:0:0:31',1,true)) end
    igual(#FAKE.Photos('tip'),1); igual(#llamadas,1)
    assert(FAKE.Photos('tip')[1].text:find('#esMX\\pitem:100:0:0:31,1,1,Nombre,Derecha,a335ee,',1,true))
    FAKE.Event('PLAYER_ENTERING_WORLD'); FAKE.Advance(1); igual(#FAKE.Photos('tip'),1)
    SlashCmdList.WOWC('send'); FAKE.Advance(1); igual(#FAKE.Photos('tip'),2)
end)

test('API exacta de tooltip para cada origen', function()
    FAKE.Syndicator(true,'Actual')
    FAKE.Item({itemID=1,hyperlink=Link(1)})
    FAKE.equip[16]={id=2,quality=2,link=Link(2)}
    SYNDICATOR_DATA.Characters.Actual={bankTabs={{slots={{itemID=3,itemLink=Link(3)}}}}}
    local llamadas = 0
    C_TooltipInfo={
        GetBagItem=function(a,b) igual(a,0); igual(b,1); llamadas=llamadas+1; return UnTip() end,
        GetInventoryItem=function(a,b) igual(a,'player'); igual(b,16); llamadas=llamadas+1; return UnTip() end,
        GetHyperlink=function(a) igual(a,Link(3)); llamadas=llamadas+1; return UnTip() end}
    iniciar(); igual(llamadas,3)
end)

test('tooltip vacío reintenta hasta cargar y agota tres intentos', function()
    FAKE.Item({itemID=1,hyperlink=Link(1)})
    local llamadas=0
    ActivarTips(function() llamadas=llamadas+1; return {lines={}} end)
    iniciar(); igual(#FAKE.Photos('tip'),0)
    FAKE.Advance(2); igual(llamadas,2)
    ActivarTips(function() llamadas=llamadas+1; return UnTip() end)
    FAKE.Advance(2); igual(#FAKE.Photos('tip'),1); igual(llamadas,3); igual(#FAKE.timers,0)
    SlashCmdList.WOWC('send'); ActivarTips(function() return nil end); FAKE.Advance(20)
    igual(#FAKE.timers,0)
end)

test('tooltip sanitiza campos secretos y recorta 30 líneas UTF-8 antes de escapar', function(P)
    FAKE.Item({itemID=1,hyperlink=Link(1)})
    ActivarTips(function()
        local lines={}
        for i=1,40 do lines[i]={leftText=string.rep('ñ|,;#',100),rightText=string.rep('中\\',100)} end
        lines[2]={leftText=FAKE.secret,rightText=FAKE.secret,leftColor=FAKE.secret,
            rightColor={GenerateHexColor=function() return FAKE.secret end}}
        return {lines=lines}
    end)
    iniciar()
    local partes=FAKE.Photos('tip'); assert(#partes<=12)
    local datos={}
    for _,linea in ipairs(partes) do assert(#linea.text<=3900); datos[#datos+1]=linea.text:match('|tip|(.*)') end
    local payload=table.concat(datos)
    assert(payload:find(',30,30,',1,true)); assert(not payload:find(',31,30,',1,true))
    assert(payload:find(',2,30,,,,',1,true))
    assert(payload:find(P.Escape(P.Recortar(string.rep('ñ|,;#',100),200)),1,true))
end)

test('100 tooltips salen en tandas de hasta 12 partes con relleno único y fotos primero', function()
    FAKE.sizes[0]=100
    for i=1,100 do FAKE.items['0:'..i]={itemID=i,hyperlink=Link(i)} end
    ActivarTips(function() return UnTip() end)
    iniciar(); igual(#FAKE.Photos('tip'),12)
    FAKE.Advance(30); igual(#FAKE.Photos('tip'),100); igual(#FAKE.timers,0); igual(FAKE.maxTimers,1)
    local tandas={}
    for _,linea in ipairs(FAKE.lines) do
        local t=tandas[linea.time] or {tips=0,relleno=0,yaTip=false}
        if linea.text:find('|tip|',1,true) then t.tips=t.tips+1; t.yaTip=true
        elseif linea.text:match('^KCP') then t.relleno=t.relleno+1
        else assert(not t.yaTip) end
        if linea.text:match('^KC1|') then
            local total=tonumber(linea.text:match('^KC1|%x+|%d+|%d+|(%d+)|')); assert(total<=64)
        end
        tandas[linea.time]=t
    end
    local anterior
    for tiempo=1,31 do
        local t=tandas[tiempo]
        if t then assert(t.tips<=12); igual(t.relleno,12); if anterior then assert(tiempo-anterior>=1) end; anterior=tiempo end
    end
end)

test('fallo de parte tip y fallo de relleno no confirman el envío', function()
    FAKE.Item({itemID=1,hyperlink=Link(1)})
    ActivarTips(function() return UnTip() end)
    FAKE.failAt=12; iniciar(); igual(#FAKE.Photos('tip'),0)
    FAKE.failAt=27; FAKE.Advance(2); igual(#FAKE.Photos('tip'),1)
    FAKE.failAt=nil; FAKE.Advance(2); igual(#FAKE.Photos('tip'),2)
    FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(1); igual(#FAKE.Photos('tip'),2)
    SlashCmdList.WOWC('send'); FAKE.Advance(1); igual(#FAKE.Photos('tip'),3)
end)

test('char usa raza numérica y sexo normalizado', function()
    FAKE.raceID, FAKE.sex = 5, 3
    iniciar(); assert(FAKE.Photos('char')[1].text:find(',32.2,5,1,120,1000,Prueba#',1,true))
end)

test('char trece campos con equipado decimal y escalares secretos', function()
    FAKE.name, FAKE.class, FAKE.race, FAKE.ilvl = FAKE.secret, FAKE.secret, FAKE.secret, FAKE.secret
    FAKE.raceID, FAKE.sex, FAKE.xp, FAKE.xpMax = FAKE.secret, FAKE.secret, FAKE.secret, FAKE.secret
    iniciar(); assert(FAKE.Photos('char')[1].text:find('31,123456,Ventormenta,Distrito,,,,,,,,,Prueba#',1,true))
    FAKE.ilvl=15.67; FAKE.xp=200; FAKE.xpMax=1000; FAKE.Event('PLAYER_XP_UPDATE'); FAKE.Advance(1)
    assert(FAKE.Photos('char')[2].text:find(',15.7,,,200,1000,Prueba#',1,true))
end)


test('tandas con 100 tooltips de tamaño máximo respetan presupuesto y no cortan registros', function(P)
    FAKE.sizes[0]=100
    for i=1,100 do FAKE.items['0:'..i]={itemID=i,hyperlink=Link(i)} end
    local texto=string.rep('|,;#',50)
    ActivarTips(function()
        local lines={}
        for i=1,30 do lines[i]={leftText=texto,rightText=texto} end
        return {lines=lines}
    end)
    iniciar(); FAKE.Advance(220)
    local tandas, mensajes={},{}
    for _,linea in ipairs(FAKE.Photos('tip')) do
        assert(#linea.text<=3900)
        tandas[linea.time]=(tandas[linea.time] or 0)+1
        assert(tandas[linea.time]<=12)
        local seq,parte,total,payload=linea.text:match('^KC1|%x+|(%d+)|(%d+)|(%d+)|tip|(.*)$')
        assert(tonumber(total)<=64)
        mensajes[seq]=mensajes[seq] or {}
        mensajes[seq][tonumber(parte)]=payload
        -- Cada registro queda entero; una parte posterior conserva el separador inicial.
        if tonumber(parte)>1 then igual(payload:sub(1,1),';') end
    end
    local cantidad=0
    for _,partes in pairs(mensajes) do
        cantidad=cantidad+1
        local payload=table.concat(partes)
        assert(payload:find(',30,30,',1,true))
        assert(payload:find(P.Escape(texto),1,true))
    end
    igual(cantidad,100); igual(#FAKE.timers,0)
end)

test('tooltip vacío de una casilla que cambió no se asigna al objeto anterior', function()
    FAKE.Item({itemID=1,hyperlink=Link(1)})
    ActivarTips(function() return nil end)
    iniciar()
    FAKE.Item({itemID=2,hyperlink=Link(2)})
    ActivarTips(function() return UnTip('Segundo') end)
    FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(10)
    local tips=FAKE.Photos('tip'); igual(#tips,1)
    assert(tips[1].text:find('item:2:',1,true)); assert(not tips[1].text:find('item:1:',1,true))
end)

test('tooltip diferido conserva el contenido de su foto aunque cambie la casilla', function()
    FAKE.sizes[0]=13
    for i=1,13 do FAKE.items['0:'..i]={itemID=i,hyperlink=Link(i)} end
    local texto='Primero'
    ActivarTips(function() return UnTip(texto) end)
    iniciar(); igual(#FAKE.Photos('tip'),12)
    texto='Segundo'
    FAKE.items['0:13']={itemID=100,hyperlink=Link(100)}
    FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(5)
    local viejo,nuevo
    for _,linea in ipairs(FAKE.Photos('tip')) do
        if linea.text:find('item:13:',1,true) then viejo=linea.text end
        if linea.text:find('item:100:',1,true) then nuevo=linea.text end
    end
    assert(viejo:find(',Primero,',1,true)); assert(nuevo:find(',Segundo,',1,true))
end)


test('eventos de fotos no adelantan el plazo de reintento de tooltips', function()
    FAKE.Item({itemID=1,hyperlink=Link(1)})
    local tiempos={}
    ActivarTips(function() tiempos[#tiempos+1]=GetTime(); return nil end)
    iniciar()
    FAKE.money=1; FAKE.Event('PLAYER_MONEY'); FAKE.Advance(1)
    igual(#tiempos,1)
    FAKE.Advance(10); igual(#tiempos,3)
    assert(tiempos[2]-tiempos[1]>=2); assert(tiempos[3]-tiempos[2]>=2)
end)

local function Barber(categories, model)
    C_BarberShop = {GetAvailableCustomizations=function() return categories end,
        GetViewingChrModel=function() return model or 10 end}
end
local function LookPayload()
    local photos=FAKE.Photos('look'); return photos[#photos].text:match('|look|(.*)$')
end
test('look usa el ID de choices[currentChoiceIndex], nunca el índice', function()
    Barber({{options={{id=7,currentChoiceIndex=2,choices={{id=100},{id=900}}},
        {id=8,currentChoiceIndex=1,choices={{id=500}}}}}})
    iniciar(); igual(LookPayload(),'live,complete,1,0,10#7,900;8,500')
    assert(next(WOWCompanionDB.look))
end)
test('look ausente invalida explícitamente y send lo reenvía', function()
    iniciar(); igual(LookPayload(),'none,absent,1,0,0#')
    SlashCmdList.WOWC('send'); FAKE.Advance(1); igual(#FAKE.Photos('look'),2)
end)
test('look parcial filtra secretos de opción, índice, elección y modelo', function()
    local S=FAKE.secret
    Barber({S,{options={S,{id=S,currentChoiceIndex=1,choices={{id=10}}},
        {id=8,currentChoiceIndex=S,choices={{id=10}}}, {id=9,currentChoiceIndex=1,choices={S}},
        {id=7,currentChoiceIndex=1,choices={{id=900}}}}}},S)
    iniciar(); igual(LookPayload(),'live,partial,1,0,0#7,900')
end)
test('peluquería guarda al entrar y aplicar; cancelar no guarda preview', function()
    local option={id=7,currentChoiceIndex=1,choices={{id=100},{id=900}}}
    Barber({{options={option}}}); iniciar()
    FAKE.Event('BARBER_SHOP_OPEN'); FAKE.Advance(1)
    option.currentChoiceIndex=2
    SlashCmdList.WOWC('send'); FAKE.Advance(1); igual(LookPayload(),'live,complete,1,0,10#7,100')
    FAKE.Event('BARBER_SHOP_CLOSE'); FAKE.Advance(1); igual(LookPayload(),'live,complete,1,0,10#7,100')
    -- Al volver a entrar el juego restaura el aspecto anterior.
    option.currentChoiceIndex=1; FAKE.Event('BARBER_SHOP_OPEN'); FAKE.Advance(1)
    option.currentChoiceIndex=2; FAKE.Event('BARBER_SHOP_APPEARANCE_APPLIED'); FAKE.Advance(1)
    igual(LookPayload(),'live,complete,1,0,10#7,900')
    local saved=WOWCompanionDB
    -- Simular relogueo: cargar Look otra vez conserva sólo SavedVariables.
    C_BarberShop=nil; assert(loadfile('Look.lua'))('WOWCompanion',FAKE.ns)
    local header,records=FAKE.ns.Look(); igual(header,'saved,complete,1,0,10'); igual(records[1],'7,900')
    igual(WOWCompanionDB,saved)
end)
test('aplicación sin datos invalida la foto guardada anterior', function()
    Barber({{options={{id=7,currentChoiceIndex=1,choices={{id=100}}}}}}); iniciar()
    FAKE.Event('BARBER_SHOP_OPEN'); FAKE.Advance(1)
    C_BarberShop=nil; FAKE.Event('BARBER_SHOP_APPEARANCE_APPLIED'); FAKE.Advance(1)
    igual(LookPayload(),'none,absent,1,0,0#'); assert(not next(WOWCompanionDB.look))
end)
test('cambiar personaje o modelo no reutiliza el aspecto guardado', function()
    Barber({{options={{id=7,currentChoiceIndex=1,choices={{id=100}}}}}}); iniciar()
    C_BarberShop=nil; FAKE.name='Otro'; FAKE.Event('PLAYER_ENTERING_WORLD'); FAKE.Advance(1)
    igual(LookPayload(),'none,absent,1,0,0#')
end)

test('entrar con otro personaje de igual raza y sexo reenvía look ausente', function()
    iniciar(); igual(LookPayload(),'none,absent,1,0,0#')
    local first = #FAKE.Photos('look')
    FAKE.name='Otro'; FAKE.Event('PLAYER_ENTERING_WORLD'); FAKE.Advance(1)
    igual(#FAKE.Photos('look'),first+1)
    igual(LookPayload(),'none,absent,1,0,0#')
    -- Los eventos ordinarios siguen deduplicando el mismo aspecto.
    FAKE.Event('BARBER_SHOP_CLOSE'); FAKE.Advance(1)
    igual(#FAKE.Photos('look'),first+1)
end)

test('hello en cada entrada al mundo comparte el relleno', function()
    iniciar()
    igual(#FAKE.Photos('hello'),1)
    igual(FAKE.Photos('hello')[1].text:match('|hello|(.*)$'),'0.10.0,16001#')
    local before=#FAKE.lines
    FAKE.Event('PLAYER_ENTERING_WORLD'); FAKE.Advance(1)
    igual(#FAKE.Photos('hello'),2)
    igual(#FAKE.lines-before,15) -- look + hello + pos + doce KCP
    for i=#FAKE.lines-11,#FAKE.lines do igual(FAKE.lines[i].text,'KCP' .. string.rep('x',4086)) end
end)

local function recargarTips()
    FAKE.timers, FAKE.handlers = {}, {}
    assert(loadfile('Core.lua'))('WOWCompanion', FAKE.ns)
end

test('tooltips persisten entre sesiones y se separan por idioma', function()
    FAKE.Item({itemID=100,stackCount=1,hyperlink='|Hitem:100:0|h[X]|h'})
    C_TooltipInfo = {GetBagItem=function() return {lines={{leftText='Nombre'}}} end}
    iniciar(); igual(#FAKE.Photos('tip'),1)
    igual(#WOWCompanionDB.tipsEnviados.claves,1)
    recargarTips(); iniciar(); igual(#FAKE.Photos('tip'),1)
    FAKE.locale='enUS'
    recargarTips(); iniciar(); igual(#FAKE.Photos('tip'),2)
    igual(#WOWCompanionDB.tipsEnviados.claves,2)
    FAKE.locale='esMX'
    recargarTips(); iniciar(); igual(#FAKE.Photos('tip'),2)
end)

test('cambiar la versión del addon vacía tooltips guardados', function()
    WOWCompanionDB.tipsEnviados = {version='anterior',claves={'esMX|item:100:0'}}
    recargarTips()
    igual(WOWCompanionDB.tipsEnviados.version,C_AddOns.GetAddOnMetadata())
    igual(#WOWCompanionDB.tipsEnviados.claves,0)
end)

test('tooltips guardados tienen tope de 2000 al cargar y al confirmar', function()
    local claves={}
    for i=1,2001 do claves[i]='esMX|item:'..i..':0' end
    WOWCompanionDB.tipsEnviados={version=C_AddOns.GetAddOnMetadata(),claves=claves}
    recargarTips()
    igual(#WOWCompanionDB.tipsEnviados.claves,2000)
    igual(WOWCompanionDB.tipsEnviados.claves[1],'esMX|item:2:0')
    FAKE.Item({itemID=3000,stackCount=1,hyperlink='|Hitem:3000:0|h[X]|h'})
    C_TooltipInfo = {GetBagItem=function() return {lines={{leftText='Nuevo'}}} end}
    iniciar()
    igual(#FAKE.Photos('tip'),1)
    igual(#WOWCompanionDB.tipsEnviados.claves,2000)
    igual(WOWCompanionDB.tipsEnviados.claves[1],'esMX|item:3:0')
    igual(WOWCompanionDB.tipsEnviados.claves[2000],'esMX|item:3000:0')
end)

test('fallo de escritura no persiste tooltips', function()
    FAKE.Item({itemID=100,stackCount=1,hyperlink='|Hitem:100:0|h[X]|h'})
    C_TooltipInfo = {GetBagItem=function() return {lines={{leftText='Nombre'}}} end}
    FAKE.fail=true; iniciar()
    igual(#WOWCompanionDB.tipsEnviados.claves,0)
end)

local function Ubicar()
    FAKE.map, FAKE.x, FAKE.y, FAKE.facing = 37, 0.25, 0.75, 0
end
local function PosPayload()
    local fotos=FAKE.Photos('pos')
    return fotos[#fotos].text:match('|pos|(.*)$')
end
local function Rellenos()
    local n=0
    for _, linea in ipairs(FAKE.lines) do if linea.text:match('^KCP') then n=n+1 end end
    return n
end

test('pos usa GetXY, coordenadas normalizadas y facing en radianes', function()
    Ubicar(); FAKE.x, FAKE.y, FAKE.facing=0.123456,0.987654,math.rad(16)
    iniciar(); igual(PosPayload(),'37,0.1235,0.9877,0.349#')
    FAKE.facing=math.rad(359); FAKE.Event('PLAYER_STOPPED_MOVING'); FAKE.Advance(1)
    igual(PosPayload(),'37,0.1235,0.9877,0.000#')
end)

test('pos sanitiza secretos antes de acceder, comparar o formatear', function()
    Ubicar(); FAKE.map, FAKE.facing=FAKE.secret,FAKE.secret
    iniciar(); igual(PosPayload(),',,,#')
    FAKE.map=37; FAKE.pointSecret=true
    FAKE.Event('ZONE_CHANGED'); FAKE.Advance(1); igual(PosPayload(),'37,,,#')
    FAKE.pointSecret=false; FAKE.x,FAKE.y=FAKE.secret,FAKE.secret
    FAKE.Event('ZONE_CHANGED'); FAKE.Advance(1); igual(PosPayload(),'37,,,#')
    FAKE.x,FAKE.y=-0.1,1.1
    FAKE.Event('ZONE_CHANGED'); FAKE.Advance(1); igual(PosPayload(),'37,,,#')
end)

test('pos nil y no finitos quedan vacíos', function()
    Ubicar(); FAKE.x,FAKE.y,FAKE.facing=0/0,math.huge,math.huge
    iniciar(); igual(PosPayload(),'37,,,#')
    FAKE.map,FAKE.facing=nil,nil
    FAKE.Event('ZONE_CHANGED'); FAKE.Advance(1); igual(PosPayload(),',,,#')
end)

test('todos los eventos pedidos envían pos aunque no cambie', function()
    Ubicar(); iniciar()
    for i, evento in ipairs({'PLAYER_ENTERING_WORLD','ZONE_CHANGED','ZONE_CHANGED_NEW_AREA',
        'ZONE_CHANGED_INDOORS','PLAYER_STARTED_MOVING','PLAYER_STOPPED_MOVING'}) do
        FAKE.Event(evento); FAKE.Advance(1); igual(#FAKE.Photos('pos'),i+1)
    end
end)

test('umbral de pos es estricto y se acumula desde el último envío', function()
    Ubicar(); iniciar()
    for _,x in ipairs({0.251,0.252}) do
        FAKE.x=x; FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1); igual(#FAKE.Photos('pos'),1)
    end
    FAKE.x=0.2521; FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1); igual(#FAKE.Photos('pos'),2)
    FAKE.y=0.753; FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1); igual(#FAKE.Photos('pos'),3)
    FAKE.map=38; FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1); igual(#FAKE.Photos('pos'),4)
end)

test('giro sólo envía al cambiar el paso de diez grados', function()
    Ubicar(); iniciar()
    FAKE.facing=math.rad(4); FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1)
    igual(#FAKE.Photos('pos'),1)
    FAKE.facing=math.rad(6); FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1)
    igual(#FAKE.Photos('pos'),2); igual(PosPayload(),'37,0.2500,0.7500,0.175#')
end)

-- El juego escribe el log por bloques: cada posición nueva lleva relleno para que la app la vea en el segundo.
test('cada posición nueva se vuelca enseguida, una vez por segundo', function()
    Ubicar(); iniciar(); igual(Rellenos(),12)
    for i=1,5 do
        FAKE.x=0.25+i*0.003; FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1)
        igual(Rellenos(),12+12*i)
    end
    FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1); igual(Rellenos(),72)
end)

test('pos y otro tipo en la misma tanda comparten un solo relleno', function()
    Ubicar(); iniciar(); FAKE.Advance(4)
    FAKE.money=1; FAKE.x=0.3
    FAKE.Event('PLAYER_MONEY'); FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1)
    igual(Rellenos(),24)
end)

test('girar quieto vuelca la dirección nueva', function()
    Ubicar(); iniciar(); FAKE.Advance(1)
    FAKE.facing=math.rad(90); FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1)
    igual(#FAKE.Photos('pos'),2); igual(Rellenos(),24)
end)

test('relleno de otro tipo también confirma la posición ya volcada', function()
    Ubicar(); iniciar()
    FAKE.x=0.4; FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1)
    FAKE.money=1; FAKE.Event('PLAYER_MONEY'); FAKE.Advance(1)
    igual(Rellenos(),36)
    FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1); igual(Rellenos(),36)
end)

test('GPS quieto no sondea y al frenar se apaga', function()
    Ubicar(); iniciar(); igual(#FAKE.timers,0)
    FAKE.Advance(20); igual(#FAKE.Photos('pos'),1)
    FAKE.moving=true; FAKE.Event('PLAYER_STARTED_MOVING'); FAKE.Advance(1)
    for i=1,3 do FAKE.x=FAKE.x+0.01; FAKE.Advance(1) end
    assert(#FAKE.Photos('pos')>2)
    FAKE.moving=false; FAKE.Event('PLAYER_STOPPED_MOVING'); FAKE.Advance(13)
    igual(#FAKE.timers,0)
    local n=#FAKE.lines; FAKE.Advance(30); igual(#FAKE.lines,n)
end)

-- Auditoría de Gemini (2026-11-23): al frenar, la posición final no puede quedar en el búfer del juego.
test('al frenar la posición final queda volcada', function()
    Ubicar(); iniciar()
    FAKE.moving=true; FAKE.Event('PLAYER_STARTED_MOVING'); FAKE.Advance(1)
    FAKE.x=FAKE.x+0.05; FAKE.moving=false; FAKE.Event('PLAYER_STOPPED_MOVING'); FAKE.Advance(2)
    local ultimaPos=0
    for i, linea in ipairs(FAKE.lines) do if linea.text:match('|pos|') then ultimaPos=i end end
    local despues=0
    for i=ultimaPos+1, #FAKE.lines do if FAKE.lines[i].text:match('^KCP') then despues=despues+1 end end
    assert(despues>=12, 'falta el relleno después de la última posición')
    FAKE.Advance(12); igual(#FAKE.timers,0)
end)

test('GPS sigue taxi y vehículo aunque IsPlayerMoving sea falso', function()
    for _, campo in ipairs({'taxi','vehicle'}) do
        FAKE.Reset(); Ubicar(); iniciar()
        FAKE[campo]=true
        FAKE.Event(campo == 'taxi' and 'UNIT_FLAGS' or 'UNIT_ENTERED_VEHICLE','player')
        FAKE.Advance(2)
        FAKE.x=0.4; FAKE.Advance(2); assert(#FAKE.Photos('pos')>=2)
        FAKE[campo]=false; FAKE.Advance(13); igual(#FAKE.timers,0)
    end
end)

test('banderas de otra unidad o sin taxi no despiertan el GPS', function()
    Ubicar(); iniciar()
    FAKE.Event('UNIT_FLAGS','player'); FAKE.Event('UNIT_FLAGS','target')
    FAKE.Event('UNIT_ENTERED_VEHICLE','target'); FAKE.Advance(10)
    igual(#FAKE.timers,0); igual(#FAKE.Photos('pos'),1)
end)

test('GPS despierta al girar y se apaga cinco segundos después del cambio real', function()
    Ubicar(); iniciar(); FAKE.Event('PLAYER_STARTED_TURNING')
    FAKE.facing=math.rad(20); FAKE.Advance(1)
    FAKE.facing=math.rad(40); FAKE.Advance(1)
    FAKE.Advance(3); assert(#FAKE.timers>0)
    FAKE.Advance(13); igual(#FAKE.timers,0)
    local n=#FAKE.lines; FAKE.Advance(20); igual(#FAKE.lines,n)
end)

test('inicio de giro sin giro real no deja un sondeo permanente', function()
    Ubicar(); iniciar(); FAKE.Event('PLAYER_STARTED_TURNING'); FAKE.Advance(3)
    igual(#FAKE.timers,0)
end)

test('gps off descarta envíos pendientes, persiste y conserva eventos de posición', function()
    Ubicar(); iniciar(); FAKE.moving=true; FAKE.Event('PLAYER_STARTED_MOVING')
    SlashCmdList.WOWC('gps off'); FAKE.x=0.5; FAKE.Advance(10)
    igual(WOWCompanionDB.gps,false); igual(#FAKE.Photos('pos'),1); igual(#FAKE.timers,0)
    recargarTips(); FAKE.Event('PLAYER_ENTERING_WORLD'); FAKE.Advance(3)
    igual(WOWCompanionDB.gps,false); igual(#FAKE.timers,0)
    FAKE.x=0.6; FAKE.Event('PLAYER_STOPPED_MOVING'); FAKE.Advance(1)
    igual(PosPayload(),'37,0.6000,0.7500,0.000#')
    SlashCmdList.WOWC('gps on'); igual(WOWCompanionDB.gps,true)
    FAKE.Advance(1); FAKE.x=0.7; FAKE.Advance(2)
    igual(PosPayload(),'37,0.7000,0.7500,0.000#')
end)

test('off general corta el GPS y on lo reactiva sin duplicarlo', function()
    Ubicar(); FAKE.moving=true; iniciar()
    SlashCmdList.WOWC('off'); FAKE.Advance(10); igual(#FAKE.timers,0)
    local n=#FAKE.lines; FAKE.Advance(10); igual(#FAKE.lines,n)
    SlashCmdList.WOWC('on'); SlashCmdList.WOWC('gps on'); SlashCmdList.WOWC('gps on')
    FAKE.Advance(1); FAKE.x=0.4; FAKE.Advance(3)
    local tiempos={}
    for _, foto in ipairs(FAKE.Photos('pos')) do
        assert(not tiempos[foto.time]); tiempos[foto.time]=true
    end
    FAKE.moving=false; FAKE.Advance(13); igual(#FAKE.timers,0)
end)

test('fallo de pos sin relleno reintenta y fallo de relleno forzado no confirma', function()
    Ubicar(); iniciar(); FAKE.x=0.3; FAKE.fail=true
    FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1); igual(#FAKE.Photos('pos'),1)
    FAKE.fail=false; FAKE.Advance(2); igual(#FAKE.Photos('pos'),2)
    FAKE.Advance(6); FAKE.x=0.4; FAKE.failAt=FAKE.calls+2
    FAKE.ns.Pedir('gps','pos'); FAKE.Advance(1); igual(#FAKE.Photos('pos'),3)
    FAKE.failAt=nil; FAKE.Advance(2); igual(#FAKE.Photos('pos'),4)
end)

test('General.log simulado usa CRLF y relleno x', function()
    Ubicar(); iniciar()
    assert(not FAKE.log:gsub('\r\n',''):find('[\r\n]'))
    assert(FAKE.log:find('KCP'..string.rep('x',4086)..'\r\n',1,true))
end)

test('char escapa el reino y limpia nil o secretos', function(P)
    FAKE.realm = "Reino,con|#;"
    iniciar()
    assert(FAKE.Photos('char')[1].text:find(',' .. P.Escape(FAKE.realm) .. '#', 1, true))
    FAKE.realm = FAKE.secret
    FAKE.Event('PLAYER_XP_UPDATE'); FAKE.Advance(1)
    assert(FAKE.Photos('char')[2].text:find(',120,1000,#', 1, true))
    FAKE.realm = nil
    FAKE.xp = 121
    FAKE.Event('PLAYER_XP_UPDATE'); FAKE.Advance(1)
    assert(FAKE.Photos('char')[3].text:find(',121,1000,#', 1, true))
end)

test('marca opcional sin API ni registro de evento', function()
    FAKE.Item(); iniciar()
    assert(datos():sub(-1) == ',')
    igual(FAKE.handlers.GET_ITEM_INFO_RECEIVED, nil)
end)

test('marcas API escapadas en bolsas banco y equipo', function(P)
    FAKE.Syndicator(true, 'Actual')
    local link = '|Hitem:123:0|h[Objeto]|h'
    FAKE.Item({itemID=123, hyperlink=link})
    FAKE.equip[1] = {id=123, link=link, quality=1}
    SYNDICATOR_DATA.Characters.Actual = {bankTabs={{slots={{itemID=123,itemLink=link}}}}}
    KnuJunkAPI = {MarkFor=function(l, bag, slot)
        igual(l, link)
        if bag then igual(bag, 0); igual(slot, 1) end
        return 'trash,|;#'
    end}
    iniciar()
    for _, tipo in ipairs({'bags', 'bank', 'equip'}) do
        assert(FAKE.Photos(tipo)[1].text:find(',' .. P.Escape('trash,|;#'), 1, true))
    end
end)

test('marca nil pendiente reintenta tras evento aunque agotó los intentos', function()
    local ready = false
    FAKE.Item({itemID=123, hyperlink='|Hitem:123|h[Objeto]|h'})
    KnuJunkAPI = {MarkFor=function() return ready and 'quest' or nil end}
    iniciar(); FAKE.Advance(20)
    igual(#FAKE.Photos(), 3)
    assert(FAKE.handlers.GET_ITEM_INFO_RECEIVED)
    FAKE.Event('GET_ITEM_INFO_RECEIVED', FAKE.secret)
    FAKE.Event('GET_ITEM_INFO_RECEIVED', 999)
    igual(#FAKE.timers, 0)
    ready = true; FAKE.names[123] = 'Objeto'
    FAKE.Event('GET_ITEM_INFO_RECEIVED', 123, true)
    igual(FAKE.handlers.GET_ITEM_INFO_RECEIVED, nil)
    FAKE.Advance(1)
    igual(#FAKE.Photos(), 4)
    assert(FAKE.Photos()[4].text:find(',quest', 1, true))
end)

-- Auditoría de Gemini: si el servidor no devuelve el objeto, no puede quedar un ciclo de pedidos.
test('marca con evento fallido no se vuelve a pedir', function()
    FAKE.Item({itemID=123, hyperlink='|Hitem:123|h[Objeto]|h'})
    KnuJunkAPI = {MarkFor=function() return nil end}
    iniciar(); FAKE.Advance(20)
    assert(FAKE.handlers.GET_ITEM_INFO_RECEIVED)
    local antes = #FAKE.Photos()
    FAKE.Event('GET_ITEM_INFO_RECEIVED', 123, false)
    igual(FAKE.handlers.GET_ITEM_INFO_RECEIVED, nil)
    FAKE.Advance(5)
    igual(#FAKE.Photos(), antes)
end)

test('marca nil con datos cargados no pide eventos ni reintentos', function()
    FAKE.Item({itemID=123, hyperlink='|Hitem:123|h[Objeto]|h'})
    FAKE.names[123] = 'Objeto'
    KnuJunkAPI = {MarkFor=function() return nil end}
    iniciar(); FAKE.Advance(20)
    igual(#FAKE.Photos(), 1)
    igual(FAKE.handlers.GET_ITEM_INFO_RECEIVED, nil)
end)

test('API inválida y link secreto o inválido no se invocan', function()
    KnuJunkAPI = {MarkFor=function() error('No se debe invocar') end}
    FAKE.Item({itemID=123, hyperlink=FAKE.secret}); iniciar()
    FAKE.items['0:1'].hyperlink = 'inválido'
    FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(1)
    KnuJunkAPI = {MarkFor=true}
    FAKE.items['0:1'].hyperlink = '|Hitem:123|h[Objeto]|h'
    FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(1)
    igual(FAKE.handlers.GET_ITEM_INFO_RECEIVED, nil)
end)

test('marca pendiente se cancela al retirar el objeto', function()
    FAKE.Item({itemID=123, hyperlink='|Hitem:123|h[Objeto]|h'})
    KnuJunkAPI = {MarkFor=function() return nil end}
    iniciar(); assert(FAKE.handlers.GET_ITEM_INFO_RECEIVED)
    FAKE.items = {}; FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(2)
    igual(FAKE.handlers.GET_ITEM_INFO_RECEIVED, nil)
end)

local function ConMisiones(lista, objetivos, entregar, seguida, fn)
    C_QuestLog = {
        GetQuestsOnMap=function(map) igual(map,37); return lista end,
        GetTitleForQuestID=function(id) return 'Misión, ' .. id end,
        GetQuestObjectives=function(id) return objetivos[id] end,
        ReadyForTurnIn=function(id) return entregar[id] end,
    }
    C_SuperTrack = {GetSuperTrackedQuestID=function() return seguida end}
    local ok, err = pcall(fn)
    C_QuestLog, C_SuperTrack = nil, nil
    if not ok then error(err, 0) end
end
local function QuestPayload()
    local fotos=FAKE.Photos('quest')
    return fotos[#fotos].text:match('|quest|(.*)$')
end

-- Caso real del 2026-11-23 en Desolace: GetQuestsOnMap devolvió 1365, 1368, 1434 y 1481 con x,y entre 0 y 1.
test('quest manda las misiones del mapa con objetivos escapados', function()
    Ubicar()
    ConMisiones({{questID=1365,x=0.5619,y=0.5957},{questID=1368,x=0.6833,y=0.7155}},
        {[1365]={{text='Kodos: 3/8',numFulfilled=3,numRequired=8,finished=false}}}, {[1368]=true}, 1365, function()
        iniciar()
        igual(QuestPayload(), '37,1365#1365,0.5619,0.5957,0,Misión\\c 1365,3,8,0,Kodos: 3/8;1368,0.6833,0.7155,1,Misión\\c 1368')
    end)
end)

test('quest descarta secretos y coordenadas fuera del mapa, y no repite sin cambios', function()
    Ubicar()
    ConMisiones({{questID=FAKE.secret,x=0.1,y=0.1},{questID=7,x=1.5,y=0.2},{questID=8,x=FAKE.secret,y=0.2},{questID=9,x=0.3,y=0.4}},
        {[9]={{text=FAKE.secret,numFulfilled=FAKE.secret,numRequired=2,finished=FAKE.secret}}}, {}, FAKE.secret, function()
        iniciar()
        igual(QuestPayload(), '37,#9,0.3000,0.4000,0,Misión\\c 9,,2,0,')
        FAKE.Event('QUEST_LOG_UPDATE'); FAKE.Advance(1); igual(#FAKE.Photos('quest'),1)
    end)
end)

test('quest corta en 25 misiones y sin la API manda la lista vacía', function()
    Ubicar()
    local lista = {}
    for i=1,30 do lista[i]={questID=i,x=0.5,y=0.5} end
    ConMisiones(lista, {}, {}, nil, function()
        iniciar()
        local _, n = QuestPayload():gsub(';',';'); igual(n,24)
    end)
    FAKE.Reset(); Ubicar(); iniciar(); igual(QuestPayload(), '37,#')
end)

-- Auditoría de Gemini (2026-11-23): sin misión seguida el juego da 0, y la seguida podía quedar afuera del tope de 25.
test('quest manda vacío sin misión seguida y siempre incluye la seguida', function()
    Ubicar()
    ConMisiones({{questID=5,x=0.5,y=0.5}}, {}, {}, 0, function()
        iniciar(); igual(QuestPayload():match('^[^#]*'), '37,')
    end)
    FAKE.Reset(); Ubicar()
    local lista = {}
    for i=1,30 do lista[i]={questID=i,x=0.5,y=0.5} end
    ConMisiones(lista, {}, {}, 30, function()
        iniciar()
        local payload = QuestPayload()
        igual(payload:match('^[^#]*'), '37,30'); assert(payload:find('#30,0.5000',1,true))
    end)
end)

local function MailPayload()
    local fotos=FAKE.Photos('mail')
    return fotos[#fotos].text:match('|mail|(.*)$')
end
test('mail avisa correo nuevo con hasta tres remitentes y descarta secretos', function()
    HasNewMail = function() return true end
    GetLatestThreeSenders = function() return 'Zero, Zimmer', FAKE.secret, 'Manners' end
    local ok, err = pcall(function()
        iniciar(); igual(MailPayload(), '1#Zero\\c Zimmer;Manners')
        HasNewMail = function() return false end
        FAKE.Event('UPDATE_PENDING_MAIL'); FAKE.Advance(1); igual(MailPayload(), '0#')
    end)
    HasNewMail, GetLatestThreeSenders = nil, nil
    if not ok then error(err, 0) end
end)
test('mail sin la API manda cero', function() iniciar(); igual(MailPayload(), '0#') end)

local function avisos()
    local n = 0
    for _, s in ipairs(FAKE.chat) do if s:find('app de escritorio',1,true) then n = n + 1 end end
    return n
end
local function primerIngreso() WOWCompanionDB = nil; recargarTips() end
test('aviso de la app sale una vez, a los 8 s del primer ingreso', function()
    primerIngreso(); FAKE.Advance(7); igual(avisos(),0)
    FAKE.Advance(1); igual(avisos(),1); igual(WOWCompanionDB.avisoApp,true)
    assert(FAKE.chat[#FAKE.chat]:find('https://',1,true))
end)
test('aviso de la app no se repite al recargar', function()
    primerIngreso(); FAKE.Advance(8); recargarTips(); FAKE.Advance(20); igual(avisos(),1)
end)
test('instalado desde la app no muestra el aviso ni después de actualizar', function()
    FAKE.ns.desdeApp = true; primerIngreso(); FAKE.Advance(20); igual(avisos(),0); igual(WOWCompanionDB.avisoApp,true)
    FAKE.ns.desdeApp = nil; recargarTips(); FAKE.Advance(20); igual(avisos(),0)
end)
test('/wowc app repite el aviso y figura en el uso', function()
    primerIngreso(); FAKE.Advance(8); FAKE.command('app'); igual(avisos(),2)
    FAKE.command('cualquiera'); assert(FAKE.chat[#FAKE.chat]:find('| app',1,true))
end)

local function DestPayload()
    local fotos = FAKE.Photos('dest')
    return fotos[#fotos] and fotos[#fotos].text:match('|dest|(.*)$')
end
local function ConTomTom(fn)
    local cb
    TomTom = {RegisterCallback=function(owner, evento, f) assert(owner == FAKE.ns and evento == 'ArrowTargetChanged'); cb = f end}
    FAKE.timers, FAKE.handlers = {}, {}
    assert(loadfile('Core.lua'))('WOWCompanion', FAKE.ns)
    local ok, err = pcall(fn, function(uid) cb('ArrowTargetChanged', uid) end)
    TomTom = nil
    if not ok then error(err, 0) end
end
test('dest sin TomTom manda vacío una vez', function()
    iniciar(); igual(DestPayload(), ',,,,#')
    FAKE.Event('PLAYER_ENTERING_WORLD'); FAKE.Advance(1); igual(#FAKE.Photos('dest'), 1)
end)
test('dest manda mapa, coordenadas, título y origen de la flecha, y vacío al quitarla', function()
    ConTomTom(function(Flecha)
        iniciar(); igual(DestPayload(), ',,,,#')
        Flecha({405, 0.51234, 0.7, title='Shellfish; 3,5', from='WoWPro'}); FAKE.Advance(1)
        igual(DestPayload(), '405,0.5123,0.7000,Shellfish\\s 3\\c5,WoWPro#')
        local lineas = #FAKE.lines
        assert(lineas >= 13, 'dest lleva relleno')
        Flecha(nil); FAKE.Advance(1); igual(DestPayload(), ',,,,#')
    end)
end)
test('dest descarta coordenadas fuera de rango y secretos', function()
    ConTomTom(function(Flecha)
        iniciar()
        Flecha({405, 1.5, 0.2, title='X'}); FAKE.Advance(1); igual(DestPayload(), ',,,,#')
        Flecha({405, 0.2, 0.2, title=FAKE.secret, from=FAKE.secret}); FAKE.Advance(1); igual(DestPayload(), '405,0.2000,0.2000,,#')
        Flecha(FAKE.secret); FAKE.Advance(1); igual(DestPayload(), ',,,,#')
    end)
end)

local function LogPayload()
    local fotos = FAKE.Photos('log')
    return fotos[#fotos].text:match('|log|(.*)$')
end
local function ConRegistro(filas, objetivos, extra, fn)
    C_QuestLog = {
        GetNumQuestLogEntries=function() return #filas, 99 end,
        GetInfo=function(i) return filas[i] end,
        GetQuestObjectives=function(id) return objetivos[id] end,
        ReadyForTurnIn=function(id) return extra.lista[id] end,
        IsFailed=function(id) return extra.fallida[id] end,
    }
    local ok, err = pcall(fn)
    C_QuestLog = nil
    if not ok then error(err, 0) end
end
test('log manda el registro en orden con categoría, nivel, estado y objetivos', function()
    ConRegistro({{title='Desolace', isHeader=true}, {title='Shellfish', level=33, questID=5386},
        {title='Kodos, otra vez', level=34, questID=1365}, {title='Plegada', isHeader=true, isCollapsed=true}},
        {[5386]={{text='Almejas: 2/10',numFulfilled=2,numRequired=10,finished=false}}},
        {lista={[1365]=true}, fallida={[5386]=false}}, function()
        iniciar()
        igual(LogPayload(), '1#5386,33,0,0,Desolace,Shellfish,2,10,0,Almejas: 2/10;1365,34,1,0,Desolace,Kodos\\c otra vez')
        FAKE.Event('QUEST_LOG_UPDATE'); FAKE.Advance(1); igual(#FAKE.Photos('log'), 1)
    end)
end)
test('log marca fallidas, descarta secretos y corta en 35', function()
    local filas = {{title=FAKE.secret, isHeader=true}, {title='Escolta', level=FAKE.secret, questID=10}, FAKE.secret,
        {title='X', questID=FAKE.secret}}
    for i = 1, 40 do filas[#filas + 1] = {title='M' .. i, level=1, questID=100 + i} end
    ConRegistro(filas, {}, {lista={}, fallida={[10]=true}}, function()
        iniciar()
        local datos = LogPayload()
        assert(datos:find('^0#10,,0,1,,Escolta;101,1,0,0,,M1;'), datos)
        local n = select(2, datos:gsub(';', ';')) + 1
        igual(n, 35)
    end)
end)
test('log sin API del registro manda cero sin misiones', function() iniciar(); igual(LogPayload(), '0#') end)

print(string.format('%d pruebas, %d fallas',total,fallas))
os.exit(fallas == 0 and 0 or 1)
