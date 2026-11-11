script_name('MilitarySkins')
script_author('Codex')
script_version('4.3.0')
script_description('Unified local military skins, personal general and nickname assignments')
-- Refuse duplicate autorun if a root archive was extracted but migration was not run.
local function legacyEntryExists(name)
    local f=io.open(getWorkingDirectory()..'\\'..name,'r')
    if f then f:close();return true end
    return false
end
if legacyEntryExists('Soldier179.lua') or legacyEntryExists('ShunSkin61.lua') then
    function main()
        repeat wait(250) until isSampAvailable()
        sampAddChatMessage('[MilitarySkins] Close GTA and run Install.cmd to finish migration.',0xE0BD77)
    end
    return
end
local folder=getWorkingDirectory()..'\\MilitarySkins'
local function trace(phase)
    local f=io.open(folder..'\\startup_trace.log','a')
    if f then f:write(os.date('!%Y-%m-%dT%H:%M:%SZ'),' ',phase,'\n');f:close()end
end
trace('4.3.0 module load; native creation disabled; HTTPS deferred until spawn')
local Controller=dofile(folder..'\\controller.lua')
local Engine=dofile(folder..'\\engine.lua')
local Settings=dofile(folder..'\\settings.lua')
local RpcBridge=dofile(folder..'\\rpc_bridge.lua')
local RpcBuild=dofile(folder..'\\rpc_build.lua')
local MemoryGuard=dofile(folder..'\\memory_guard.lua')
local DutyPolicy=dofile(folder..'\\duty_policy.lua')
local Diagnostics=dofile(folder..'\\duty_diagnostics.lua')
local Menu=dofile(folder..'\\menu.lua')
local AccessClient=dofile(folder..'\\access_client.lua')
local SecureRandom=dofile(folder..'\\secure_random.lua')
local events=require 'samp.events'
local utf8=require('encoding').UTF8
local function gameText(s)return utf8:decode(s,'CP1251')end
local controller=Controller.new(Settings.models)
local config={version=2,enabled=true,servers={}}
local configPath=folder..'\\assignments.json'
local generalPath=folder..'\\general_enabled.txt'
local generalEnabled=false
do
    local f=io.open(generalPath,'r')
    if f then generalEnabled=f:read('*l')=='1';f:close()end
end
local function setGeneral(value)
    local temp=generalPath..'.tmp'
    local f,err=io.open(temp,'w');assert(f,err);assert(f:write(value and '1\n' or '0\n'));f:close()
    local old=io.open(generalPath,'r')
    if old then local data=old:read('*a');old:close();local backup=assert(io.open(generalPath..'.bak','w'));backup:write(data);backup:close()end
    os.remove(generalPath);assert(os.rename(temp,generalPath),'Cannot save general preference; .bak retained')
    generalEnabled=value
end

local backend,server,lookup=nil,'',{}
local creationBridge
local diagnostic
local cloud,cloudConfigured,cloudError
local menu
local cloudPrefs={url='',hideSelf={}}
local duty=DutyPolicy.new({enabled=false})
local creationDisabled=true -- diagnostic safe mode: no native RPC callback changes
local function updateCreationBridge()
    if not creationBridge or creationDisabled then return end
    local ok,err=pcall(creationBridge.refresh)
    if not ok then
        creationDisabled=true;creationBridge.active=false
        pcall(creationBridge.stop)
        print('[MilitarySkins] Early creation unavailable; normal skins remain enabled: '..tostring(err))
    end
end
local function message(text)
    print('[MilitarySkins] '..text)
    if isSampAvailable() then sampAddChatMessage(gameText('[MilitarySkins] '..text),0xB7C497) end
end
local validNick=Settings.validNick
local function currentServer()
    if not isSampAvailable() then return '' end
    local ip,port=sampGetCurrentServerAddress()
    if not ip or ip=='' or not port or port==0 then return '' end
    return tostring(ip)..':'..tostring(port)
end
local function loadConfig()
    local f=io.open(configPath,'r');if not f then return end
    local text=f:read('*a');f:close()
    local ok,value=pcall(decodeJson,text)
    assert(ok,'Invalid assignments.json; original file retained')
    local normalized,migrated=Settings.normalize(value);config=normalized;return migrated
end
local function saveConfig()
    local data=encodeJson(config);local temp=configPath..'.tmp'
    local f,err=io.open(temp,'w');assert(f,err);assert(f:write(data));f:close()
    local old=io.open(configPath,'r')
    if old then
        local text=old:read('*a');old:close();local backup=assert(io.open(configPath..'.bak','w'));backup:write(text);backup:close()
    end
    -- Windows rename cannot replace an existing file; the saved backup remains.
    os.remove(configPath)
    assert(os.rename(temp,configPath),'Could not save assignments.json; .bak retained')
end
local function assignments()
    if cloudConfigured then return cloud and cloud:wanted()or {}end
    return config.servers[server] or {}
end
local function localPlayerId()
    if not isSampAvailable() or not sampIsLocalPlayerSpawned() or not doesCharExist(PLAYER_PED) then return nil end
    local ok,id=sampGetPlayerIdByCharHandle(PLAYER_PED)
    if ok and type(id)=='number' and id>=0 and id<=1003 then return id end
end
local function refreshPlayers()
    lookup={}
    if server=='' then return end
    for id=0,1003 do
        if sampIsPlayerConnected(id) then
            local name=sampGetPlayerNickname(id)
            if validNick(name) then lookup[name:lower()]={id=id,nickname=name,server=server} end
        end
    end
    -- Some SA-MP bindings enumerate only REMOTE players. Always insert self
    -- explicitly instead of relying on sampIsPlayerConnected(localId).
    local id=localPlayerId()
    if id then
        local name=sampGetPlayerNickname(id)
        if validNick(name)then lookup[name:lower()]={id=id,nickname=name,server=server}end
    end
end
local function resolveArg(arg)
    if arg:match('^%d+$') then
        local id=tonumber(arg)
        if id>1003 or (id~=localPlayerId() and not sampIsPlayerConnected(id)) then return nil,'Этот ID сейчас не подключён.' end
        return sampGetPlayerNickname(id)
    end
    if not validNick(arg) then return nil,'Укажи ID подключённого игрока или точный ник (до 24 символов).' end
    local row=lookup[arg:lower()];return row and row.nickname or arg
end
local command
local DIALOG=29385
local pending=nil
local function localNickname()
    local id=localPlayerId()
    return id and sampGetPlayerNickname(id) or nil
end
local function saveCloudPrefs()
    local path=folder..'\\cloud_config.json';local f=assert(io.open(path..'.tmp','w'))
    f:write(encodeJson(cloudPrefs));f:close();os.remove(path);assert(os.rename(path..'.tmp',path))
end
local function selfHidden(name)
    return cloudConfigured and name and cloudPrefs.hideSelf[server..'/'..name:lower()]==true
end
local function allowed(name,id)
    return not (id==localPlayerId()and selfHidden(name))and duty:allows(id,name)
end
local function wantedAssignments()
    local wanted={}
    for key,row in pairs(assignments())do
        local player=lookup[key]
        if not player or allowed(row.nickname,player.id)then wanted[key]=row end
    end
    if not cloudConfigured and generalEnabled and backend and server~=''then
        local name=localNickname();local id=localPlayerId()
        if name and allowed(name,id)then
            local state=backend.state(name:lower())
            if state.ready and state.model==61 then wanted[name:lower()]={nickname=name,model=1061}end
        end
    end
    return wanted
end
local function defaultPolicy()
    if server=='185.207.214.114:7777'then return {enabled=true,civilianColors={'FFFFFF'},maskColors={'7A7667'},factionColors={'704214'}}end
    return {enabled=false,civilianColors={},maskColors={},factionColors={}}
end
local function startCloud()
    local f=io.open(folder..'\\cloud_config.json','r')
    if f then local good,value=pcall(decodeJson,f:read('*a'));f:close();assert(good and type(value)=='table','Invalid cloud_config.json');cloudPrefs=value end
    cloudPrefs.hideSelf=type(cloudPrefs.hideSelf)=='table'and cloudPrefs.hideSelf or {}
    cloudConfigured=type(cloudPrefs.url)=='string'and cloudPrefs.url~=''
    if not cloudConfigured then return end
    local key='';local secret=io.open(folder..'\\cloud_credentials.json','r')
    if secret then local good,value=pcall(decodeJson,secret:read('*a'));secret:close();if good and type(value)=='table'then key=value.key or ''end end
    local Transport=dofile(folder..'\\cloud_transport.lua')
    local Sync=dofile(folder..'\\cloud_sync.lua')
    local accessPending
    local pendingFile=io.open(folder..'\\cloud_access_pending.json','r')
    if pendingFile then local good,value=pcall(decodeJson,pendingFile:read('*a'));pendingFile:close();if good and type(value)=='table'then accessPending=value end end
    local nativeTransport
    local lazyTransport={
        start=function(...)
            if not nativeTransport then trace('HTTPS native load begin');nativeTransport=Transport.new(folder);trace('HTTPS native load done')end
            trace('HTTPS request begin')
            return nativeTransport.start(...)
        end,
        poll=function()
            if not nativeTransport then return end
            local r=nativeTransport.poll()
            if r then trace('HTTPS response status='..tostring(r.status)..' error='..tostring(r.error))end
            return r
        end}
    cloud=Sync.new({url=cloudPrefs.url,key=key,clock=os.time,encode=encodeJson,decode=decodeJson,models=Settings.models,
        validNick=validNick,localNickname=localNickname,message=message,transport=lazyTransport,
        accessFactory=AccessClient.new,newKey=SecureRandom.key,accessPending=accessPending,
        accessChanged=function()if menu then menu:accessChanged()end end,
        savePending=function(value)
            local path=folder..'\\cloud_access_pending.json'
            if not value then os.remove(path);return end
            local out=assert(io.open(path..'.tmp','w'));out:write(encodeJson(value));out:close();os.remove(path);assert(os.rename(path..'.tmp',path))
        end,
        policy=function(profile)duty:configure(profile or defaultPolicy())end,
        saveKey=function(value)
            local path=folder..'\\cloud_credentials.json';local out=assert(io.open(path..'.tmp','w'))
            out:write(encodeJson({key=value}));out:close();os.remove(path);assert(os.rename(path..'.tmp',path))
        end})
    assert(cloud:enabled(),'Cloud URL must use HTTPS')
    cloud:setServer(server)
end
local function sampleDuty()
    local own=localPlayerId();local names={}
    for key in pairs(assignments())do names[key]=true end
    local name=own and localNickname();if name then names[name:lower()]=true end
    for key in pairs(names)do
        local row=lookup[key]
        if row then local ok,color=pcall(sampGetPlayerColor,row.id);if ok then duty:color(row.id,row.nickname,color,false,'poll')end end
    end
end
local function syncServer()
    local address=currentServer()
    if address~=server then
        pending=nil;if menu then menu:cancel()end;server=address;lookup={}
        duty:configure(defaultPolicy());if cloud then cloud:setServer(server)end
        controller=Controller.new(Settings.models);controller:setEnabled(config.enabled)
    end
    return address
end
local preloadFailures={}
local function preloadAssignments()
    if not config.enabled or server=='' or not localPlayerId()or sampGetGamestate()~=3 then return end
    local assets={}
    for _,entry in pairs(assignments())do assets[entry.model]=true end
    if generalEnabled then assets[1061]=true end
    for asset in pairs(assets)do
        if not preloadFailures[asset]then
            local ok,err=pcall(backend.prepare,asset)
            if not ok then preloadFailures[asset]=true;print('[MilitarySkins] preload '..asset..': '..tostring(err))end
        end
    end
end
local function onNativeCreation(data,invoke)
    if not config.enabled or syncServer()=='' then return false end
    local id=data.playerId
    -- Remote stream-in names already exist in SA-MP's player table.
    local own=localPlayerId();local isLocal=own~=nil and own==id
    if not isLocal and not sampIsPlayerConnected(id)then return false end
    local name=sampGetPlayerNickname(id);if not validNick(name)then return false end
    if data.color then duty:color(id,name,data.color,true,'native_stream')end
    if not allowed(name,id)then return false end
    local key=name:lower();local saved=assignments()[key];local selected=saved and saved.model
    if isLocal and generalEnabled and data.serverModel==61 then selected=1061 end
    local entry=selected and Settings.models[selected]
    if not entry or (entry.localOnly and not isLocal) or (entry.serverModel and entry.serverModel~=data.serverModel)then return false end
    lookup[key]={id=id,nickname=name,server=server}
    local before=backend.state(key);local old=controller.tracks[key]
    if not backend.withCreationTemplate(data.serverModel,selected,invoke)then return false end
    local after=backend.state(key)
    if not after.ready or after.model~=data.serverModel then return false end
    -- A native same-model request can be a no-op. Never mark an unchanged
    -- original renderer as ours; the normal safe fallback will handle it.
    local changed=not before.ready or before.ped~=after.ped or before.clump~=after.clump
    local alreadyOurs=old and old.asset==selected and old.ped==after.ped and old.clump==after.clump and old.model==after.model
    if changed or alreadyOurs then return controller:adopt(backend,key,selected)end
    return false
end
local function startDiagnostics()
    diagnostic=Diagnostics.new({enabled=false,path=folder..'\\duty_diagnostics.jsonl',encode=encodeJson,
        clock=function()return os.time()*1000 end,server=currentServer,
        players=function()
            local ids,seen={},{};local own=localPlayerId()
            if own then ids[#ids+1]=own;seen[own]=true end
            for key in pairs(assignments())do local row=lookup[key];if row and not seen[row.id]then ids[#ids+1]=row.id;seen[row.id]=true end end
            return ids
        end,
        observe=function(id)
            if id~=localPlayerId() and not sampIsPlayerConnected(id)then return nil end
            local name=sampGetPlayerNickname(id);if not validNick(name)then return nil end
            local key=name:lower();if id~=localPlayerId() and not assignments()[key]then return nil end
            local state=backend.state(key)
            return {nickname=name,is_self=id==localPlayerId(),color_samp=Diagnostics.color(sampGetPlayerColor(id)),
                server_model=state.ready and state.model or nil,streamed=state.ready==true,
                on_foot=state.ready and state.safe==true or false}
        end})
end
local function diagnose(kind,id,data)
    if diagnostic then pcall(diagnostic.player,diagnostic,kind,id,data)end
end
local skippedColor={}
local function skipColor(reason)
    if not skippedColor[reason]then skippedColor[reason]=true;trace('Color event ignored: '..reason)end
end
local function eventColor(id,color,rpc,source)
    if type(id)~='number'or id%1~=0 or id<0 or id>1003 then return end
    if not isSampAvailable()or sampGetGamestate()~=3 then skipColor('SA-MP not connected');return end
    -- Color RPCs can precede player-pool creation. pcall cannot make a native
    -- nickname getter safe for a null player slot. Verify pool membership first.
    local own=localPlayerId()
    if id~=own and not sampIsPlayerConnected(id)then skipColor('player pool entry not ready');return end
    local good,name=pcall(sampGetPlayerNickname,id)
    if good and validNick(name)then duty:color(id,name,color,rpc,source)end
end
function events.onSetPlayerColor(id,color)
    eventColor(id,color,true,'rpc_color');diagnose('rpc_color',id,{color_rpc=color})
end
function events.onSetPlayerSkin(id,skin)diagnose('rpc_skin',id,{server_model=skin})end
function events.onPlayerStreamIn(id,team,model,position,rotation,color)
    eventColor(id,color,true,'rpc_stream');diagnose('rpc_stream_in',id,{server_model=model,color_rpc=color,team=team})
end
function events.onSetPlayerName(id,name,success)diagnose('rpc_name',id,{new_nickname=name,success=success})end
function events.onPlayerQuit(id)duty:clear(id);diagnose('rpc_quit',id)end
function events.onPlayerJoin(id)duty:clear(id)end
function events.onServerMessage(color,text)
    local ok,plain=pcall(function()return utf8:encode(text,'CP1251')end)
    if not ok then return end
    if diagnostic then pcall(diagnostic.message,diagnostic,plain,localPlayerId())end
    local kind=Diagnostics.classify(plain)
    if kind then duty:ownMessage(localPlayerId(),localNickname(),kind)end
end
local function chooseModel(name,isSelf)
    if menu then menu:modelsMenu(name)end
end
local function startMenu()
    menu=Menu.new({models=Settings.models,order=Settings.order,
        command=function(arg)return command(arg)end,message=message,assignments=assignments,
        context=function()return {server=currentServer(),nickname=localNickname()}end,
        ownDialog=function()return sampIsDialogActive()and sampGetCurrentDialogId()==DIALOG end,
        foreignDialog=function()return sampIsDialogActive()and sampGetCurrentDialogId()~=DIALOG end,
        show=function(title,text,style,first,second)sampShowDialog(DIALOG,gameText(title),gameText(text),gameText(first),gameText(second),style)end,
        access=function()return cloud and cloud:accessStatus()or {status='idle'}end,
        state=function()
            local count,active=0,0;for _ in pairs(assignments())do count=count+1 end;for _ in pairs(controller.tracks)do active=active+1 end
            local own=localNickname()
            return {manager=not cloudConfigured or (cloud and cloud.role=='manager'and cloud.manager and own and cloud.manager.nickname:lower()==own:lower())or false,
                identified=cloud and (cloud.role=='player'or cloud.role=='manager')or false,count=count,active=active,enabled=config.enabled,hidden=selfHidden(own),general=(own and assignments()[own:lower()]and assignments()[own:lower()].model==1061)or (not cloudConfigured and generalEnabled),version='4.3.0',
                connected=not cloudConfigured or (cloud and cloud.lastSuccess>0 and os.time()-cloud.lastSuccess<=60)or false}
        end})
end
function events.onShowDialog()pending=nil;if menu then menu:cancel()end end
local queuedMenuReply
local function pollSelection()
    if not menu or not menu.pending then return end
    local answered,button,row,input=sampHasDialogRespond(DIALOG)
    local queued=queuedMenuReply;queuedMenuReply=nil
    if answered then menu:respond(button,row,input)
    elseif queued and queued.target==menu.pending then menu:respond(queued.button,queued.row,queued.input)end
end
function events.onSendDialogResponse(id,button,row,input)
    if id~=DIALOG or not menu or not menu.pending then return end
    queuedMenuReply={target=menu.pending,button=button,row=row,input=input};return false
end
command=function(arg)
    local verb,value=(arg or ''):match('^%s*(%S*)%s*(.-)%s*$');verb=verb:lower()
    if verb:match('^%d+$') then verb,value='set',verb..(value~='' and (' '..value) or '') end
    if verb=='remove' then verb='del' end
    if verb=='self' then verb='me' end
    if verb==''or verb=='menu'then if menu then menu:home()end;return end
    if verb=='help'then if menu then menu:help()end;return end
    if verb=='access'then
        if not cloud then message('Подключение ещё не готово. Дождись появления персонажа.');return end
        if value=='request'then cloud:requestAccess()else if menu then menu:access()end end;return
    end
    if verb=='auth' then
        if not cloud then message('Cloudflare недоступен: '..tostring(cloudError or 'нет адреса сервиса'));return end
        if value==''then if menu then menu:access()end
        else cloud:authenticate(value)end
        return
    end
    if verb=='panel'then message('Панель: '..tostring(cloudPrefs.url));return end
    if verb=='diag' then
        if diagnostic then message(diagnostic:command(value))else message('Диагностика недоступна; подробности в moonloader.log')end
        return
    end
    if verb=='general' or verb=='gen' then
        if cloudConfigured then
            local name=localNickname();if not name then message('Дождись появления персонажа.');return end
            local row=assignments()[name:lower()];local selected=row and row.model==1061
            if value=='status'then message(selected and 'Генерал назначен в общем списке.'or 'Генерал не назначен.');return end
            if value~=''and value~='on'and value~='off'then message('Используй /mskin general on, off или status');return end
            if not cloud or cloud.role~='manager'then if menu then menu:access()end;return end
            if value=='on'or (value==''and not selected)then cloud:write(name,1061,false)
            elseif selected then cloud:write(name,nil,true)end
            return
        end
        if value=='status' then
            local name=localNickname();local track=name and controller.tracks[name:lower()] or nil
            message('Мой генерал: '..(generalEnabled and 'включён' or 'выключен')..'; '..(track and track.asset==1061 and 'применён' or 'ожидание серверного скина 61 и появления на ногах'))
        elseif value=='' or value=='on' or value=='off' then
            local enabled=value=='on' or (value=='' and not generalEnabled)
            setGeneral(enabled)
            if enabled and cloudConfigured then local own=localNickname();if own then cloudPrefs.hideSelf[server..'/'..own:lower()]=nil;saveCloudPrefs()end end
            local own=localNickname();if own then controller.failures[own:lower()]=nil;controller.candidates[own:lower()]=nil end
            message(enabled and 'Мой генерал выбран. Применяется только к тебе при серверном скине 61.' or 'Режим генерала выключен. Возврат к назначенному либо серверному скину — на ногах.')
            if enabled and not config.enabled then message('Все замены выключены. Включить: /mskin on')end
        else message('Используй /mskin general on, off или status')end
        return
    end
    if verb=='me' or verb=='skins' then
        local name=localNickname();if not name then message('Дождись появления своего персонажа.');return end
        if value=='reset'then
            if cloudConfigured then
                if not cloud then message('Дождись подключения к общему списку.');return end
                if cloud.role=='manager'or cloud.role=='player'then cloud:resetSelf()
                else cloud:requestAccess('self');if menu then menu:access()end end
            else
                if generalEnabled then setGeneral(false)end
                command('del '..name)
            end
            return
        end
        if cloudConfigured and (value=='off'or value=='original'or value=='on')then
            cloudPrefs.hideSelf[server..'/'..name:lower()]=value~='on'and true or nil;saveCloudPrefs()
            message(value=='on'and 'Свой назначенный облик показан локально.'or 'Свой облик скрыт только у тебя. Общий список не изменён.');return
        end
        if value=='' then if menu then menu:mine()end
        elseif value=='off' or value=='original' then
            if generalEnabled then setGeneral(false)end
            command('del '..name)
        elseif value=='general' or value=='1061' then command('general on')
        elseif Settings.models[tonumber(value)] then command('add '..name..' '..value)
        else message('Открой /mskin и выбери «Мой облик».')end
        return
    end
    if verb=='on' or verb=='off' then
        config.enabled=verb=='on';controller:setEnabled(config.enabled);saveConfig()
        message(config.enabled and 'Замены включены.' or 'Замены выключены. Восстановление — у живых персонажей, включая пассажиров и водителей.');return
    end
    if verb=='status'then if menu then menu:status()end;return end
    if verb=='debug' then
        local n,active=0,0;for _ in pairs(assignments()) do n=n+1 end;for _ in pairs(controller.tracks) do active=active+1 end
        message(string.format('v4.3.0 enabled=%s, saved=%d, active=%d, server=%s',tostring(config.enabled),n,active,server))
        message('Ранняя замена: '..(creationBridge and creationBridge.active and 'включена' or 'отключена; замена геометрии без пересоздания')..'; применено: '..tostring(creationBridge and creationBridge.applied or 0))
        message('Метод замены: геометрия; текущие анимации и IK сохраняются. Генерал: код 1061 в общем списке.')
        if cloudConfigured then message('Cloudflare: '..(cloud and (cloud.role..'; revision='..cloud.revision..'; '..(cloud.error or 'OK'))or tostring(cloudError))..'; свой облик скрыт='..tostring(selfHidden(localNickname())))end
        refreshPlayers()
        for key,entry in pairs(wantedAssignments())do
            local s=backend.state(key);local state
            if not lookup[key] then state='игрок не подключён'
            elseif not s.ready then state='персонаж вне зоны прорисовки или ещё не появился'
            elseif not config.enabled then state=controller.tracks[key] and 'замены выключены; ожидается восстановление' or 'замены выключены'
            elseif s.blocked then state='замена заблокирована для этого серверного скина'
            elseif controller.tracks[key] and controller.tracks[key].clump==s.clump then state='модель применена'
            elseif not s.safe then state='ожидание живого персонажа'
            elseif controller.failures[key] then state='ошибка применения; подробности в moonloader.log'
            else state='ожидание применения'end
            message(entry.nickname..' -> '..entry.model..': '..state)
        end
        return
    end
    if server=='' then message('Сначала подключись к серверу.');return end
    if verb=='list'then if menu then menu:assignments(1)end;return end
    if verb=='add' or verb=='set' or verb=='del' then
        local target,modelArg=value:match('^(%S+)%s*(%S*)$')
        if not target then if menu then menu:target(verb=='del'and 'remove'or 'set')end;return end
        if verb=='del' and modelArg~='' then message('Используй /mskin remove ID или Nick_Name');return end
        local selected=modelArg~='' and tonumber(modelArg) or nil
        if modelArg~='' and not Settings.models[selected] then message('Облик не найден. Выбери его в меню /mskin.');return end
        refreshPlayers();local name,err=resolveArg(target);if not name then message(err);return end
        config.servers[server]=config.servers[server] or {};local key=name:lower()
        if cloudConfigured and (not cloud or cloud.role~='manager')then if menu then menu:access()end;return end
        if verb=='set' and not selected then chooseModel(name,false);return end
        if selected==1061 and not cloudConfigured then
            if name:lower()==tostring(localNickname()):lower() then command('general on')
            else message('Личный генерал доступен только для твоего персонажа. Для другого игрока есть полковник 61.')end
            return
        end
        if cloudConfigured then
            if not cloud then message('Cloudflare недоступен. Общий список не изменён.');return end
            if (verb=='add'or verb=='set')and not selected then selected=assignments()[key]and assignments()[key].model or 179 end
            cloud:write(name,selected,verb=='del')
            if selected and name:lower()==tostring(localNickname()):lower()and generalEnabled then setGeneral(false)end
            return
        end
        if selected and name:lower()==tostring(localNickname()):lower() and generalEnabled then setGeneral(false)end
        if verb=='add' or verb=='set' then selected=Settings.assign(config,server,name,selected)
        else config.servers[server][key]=nil end
        controller.failures[key]=nil;controller.candidates[key]=nil;saveConfig()
        message((verb=='add' or verb=='set') and ('Скин '..selected..' назначен '..name..'. Ник сохранён для этого сервера.') or ('Замена для '..name..' удалена. Восстановление — на ногах.'))
        if selected and not config.enabled then message('Замены сейчас выключены. Включить: /mskin on')end

        return
    end
    command('help')
end
function main()
    repeat wait(250) until isSampAvailable()
    local ok,migrated=pcall(loadConfig);if not ok then message(tostring(migrated));return end
    if migrated then local saved,err=pcall(saveConfig);if not saved then message(tostring(err));return end;message('Old assignments migrated: existing nicknames keep model 179.') end
    controller:setEnabled(config.enabled)
    local built,result=pcall(Engine.new,folder,function(key) return lookup[key] end,currentServer)
    if not built then message('Stopped: '..tostring(result));return end;backend=result
    local originalPrepare,originalReplace=backend.prepare,backend.replace
    local traced={}
    backend.prepare=function(asset)
        if traced[asset]then return originalPrepare(asset)end
        trace('prepare begin asset='..tostring(asset))
        local good,value=pcall(originalPrepare,asset)
        trace('prepare '..(good and 'done'or 'error')..' asset='..tostring(asset))
        if not good then error(value)end
        traced[asset]=true;return value
    end
    backend.replace=function(custom,key,expected,asset)
        trace('replace begin custom='..tostring(custom)..' asset='..tostring(asset))
        local good,value=pcall(originalReplace,custom,key,expected,asset)
        trace('replace '..(good and 'done'or 'error'))
        if not good then error(value)end;return value
    end
    trace('Engine ready')
    local handler=function(arg)local good,e=pcall(command,arg);if not good then message(tostring(e))end end
    sampRegisterChatCommand('mskin',handler)
    server=currentServer();duty:configure(defaultPolicy())
    local sharedOK,sharedErr=pcall(startCloud)
    if not sharedOK then cloudError=tostring(sharedErr);cloud=nil;message('Cloudflare не подключён: '..cloudError)end
    startMenu()
    refreshPlayers();sampleDuty()
    trace('Native early creation skipped by 4.0.1 safe mode')
    updateCreationBridge()
    local diagOK,diagErr=pcall(startDiagnostics)
    if not diagOK then print('[MilitarySkins] Diagnostics skipped: '..tostring(diagErr))end
    message('MilitarySkins готов. /mskin — открыть меню.')
    local refresh=0
    local spawnReadyAt,applicationReady=nil,false
    while true do
        wait(150);local previous=server;syncServer()
        if previous~=server then refresh=0;spawnReadyAt=nil;applicationReady=false end
        if localPlayerId()and sampGetGamestate()==3 then
            if not spawnReadyAt then spawnReadyAt=os.time();trace('Local spawn observed')end
            applicationReady=os.time()-spawnReadyAt>=2
        else spawnReadyAt=nil;applicationReady=false end
        if refresh<=0 then refreshPlayers();if applicationReady then preloadAssignments()end;updateCreationBridge();refresh=3 else refresh=refresh-1 end
        if cloud and applicationReady then local sharedOK,sharedErr=pcall(cloud.tick,cloud);if not sharedOK then cloudError=tostring(sharedErr);cloud.error=cloudError end end
        sampleDuty()
        if diagnostic then pcall(diagnostic.poll,diagnostic)end
        local menuOK,menuErr=pcall(pollSelection)
        if not menuOK then pending=nil;if menu then menu:cancel()end;message('Ошибка локального меню: '..tostring(menuErr))end
        local good,result=true,{}
        if applicationReady then good,result=pcall(controller.tick,controller,backend,wantedAssignments())end
        if not good then controller:setEnabled(false);message('Stopped: '..tostring(result));return
        else for _,line in ipairs(result) do message(line) end end
    end
end
function onScriptTerminate(script,quitGame)
    if script==thisScript() then
        trace('Script terminating quitGame='..tostring(quitGame))
        if creationBridge then pcall(creationBridge.stop)end
    end
    if script==thisScript() and not quitGame then
        if menu and menu.pending and isSampAvailable() and sampIsDialogActive() and sampGetCurrentDialogId()==DIALOG then pcall(sampCloseCurrentDialogWithButton,0)end
        pending=nil;if menu then menu:cancel()end
        if backend then pcall(controller.restoreAll,controller,backend)end
    end
end
