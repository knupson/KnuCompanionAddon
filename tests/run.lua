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
    iniciar(); igual(datos():match('#(.*)'), '0,1,,,,,,')
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
    FAKE.Item(); iniciar(); igual(#FAKE.lines,17)
    assert(datos():find('Cajón arrebatado',1,true))
    assert(FAKE.lines[1].text:match('^KC1|%x%x%x%x%x%x%x%x|1|1|1|bags|'))
    for i=6,17 do igual(#FAKE.lines[i].text,4089); igual(FAKE.lines[i].text:sub(1,3),'KCP') end
end)
test('sin cambios no hay datos ni relleno', function()
    FAKE.Item(); iniciar(); FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(1); igual(#FAKE.lines,17)
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
    FAKE.Advance(1.99); igual(FAKE.calls,17)
    FAKE.Advance(20); igual(FAKE.calls,51); igual(#FAKE.timers,0); igual(FAKE.maxTimers,1)
end)
test('foto fallida no queda marcada como enviada', function()
    FAKE.fail=true; iniciar(); FAKE.fail=false; FAKE.Advance(2)
    igual(#FAKE.Photos(),1); assert(FAKE.Photos()[1].text:find('|6|1|1|bags|',1,true))
    FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(1); igual(#FAKE.Photos(),1)
end)
test('fallo en una parte conserva el reintento', function()
    FAKE.failAt=1; iniciar(); FAKE.Advance(2); igual(#FAKE.Photos(),1)
end)
test('fallo de relleno tampoco confirma la foto', function()
    FAKE.failAt=6; iniciar(); FAKE.Advance(2); igual(#FAKE.Photos(),2)
end)
test('off durante reintento impide el envío', function()
    FAKE.fail=true; iniciar(); SlashCmdList.WOWC('off'); FAKE.Advance(10); igual(FAKE.calls,17)
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
    iniciar(); igual(#FAKE.Photos('*'),5); igual(#FAKE.lines,17)
    FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Event('PLAYER_EQUIPMENT_CHANGED')
    FAKE.Event('BARBER_SHOP_CLOSE'); FAKE.Advance(1); igual(#FAKE.lines,17)
    SlashCmdList.WOWC('send'); FAKE.Advance(1); igual(#FAKE.Photos('*'),10); igual(#FAKE.lines,34)
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
    assert(FAKE.Photos('char')[1].text:find('31,,Zona\\pcon\\ccoma,Distrito,Yaestoy Muerto,PALADIN,Humano,32.2,1,0#',1,true))
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
    FAKE.failAt=6; iniciar(); igual(#FAKE.Photos('tip'),0)
    FAKE.failAt=20; FAKE.Advance(2); igual(#FAKE.Photos('tip'),1)
    FAKE.failAt=nil; FAKE.Advance(2); igual(#FAKE.Photos('tip'),2)
    FAKE.Event('BAG_UPDATE_DELAYED'); FAKE.Advance(1); igual(#FAKE.Photos('tip'),2)
    SlashCmdList.WOWC('send'); FAKE.Advance(1); igual(#FAKE.Photos('tip'),3)
end)

test('char usa raza numérica y sexo normalizado', function()
    FAKE.raceID, FAKE.sex = 5, 3
    iniciar(); assert(FAKE.Photos('char')[1].text:find(',32.2,5,1#',1,true))
end)

test('char diez campos con equipado decimal y escalares secretos', function()
    FAKE.name, FAKE.class, FAKE.race, FAKE.ilvl = FAKE.secret, FAKE.secret, FAKE.secret, FAKE.secret
    FAKE.raceID, FAKE.sex = FAKE.secret, FAKE.secret
    iniciar(); assert(FAKE.Photos('char')[1].text:find('31,123456,Ventormenta,Distrito,,,,,,#',1,true))
    FAKE.ilvl=15.67; FAKE.Event('PLAYER_EQUIPMENT_CHANGED'); FAKE.Advance(1)
    assert(FAKE.Photos('char')[2].text:find(',15.7,,#',1,true))
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

print(string.format('%d pruebas, %d fallas',total,fallas))
os.exit(fallas == 0 and 0 or 1)
