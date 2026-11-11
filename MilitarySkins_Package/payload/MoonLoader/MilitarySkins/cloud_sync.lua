local M={}
local function endpoint(url)
    if type(url)~='string'then return end
    return url:match('^https://([%w%.%-]+)/?$')
end
function M.new(o)
    local self={host=endpoint(o.url),server='',role='viewer',manager=nil,entries={},revision=-1,
        lastSuccess=0,nextPoll=0,backoff=5,queue={},active=nil,error=nil,epoch=0,key=o.key or '',nextIdentity=nil,persistedKey=o.key or ''}
    if o.accessFactory then
        self.access=o.accessFactory({clock=o.clock,nickname=o.localNickname,validNick=o.validNick,newKey=o.newKey,
            pending=o.accessPending,save=o.savePending,changed=o.accessChanged,message=o.message,
            isManager=function()return self.role=='manager'end,
            send=function(request)assert(#self.queue<8,'Подожди завершения запроса');self.queue[#self.queue+1]=request end,
            authorize=function(key)self.key=key;self.queue[#self.queue+1]={kind='identity',path='/api/me',method='GET',key=key}end})
    end
    function self:requestAccess()assert(self.access,'Получение доступа недоступно');self.access:request('manager')end
    function self:accessStatus()return self.access and self.access:public()or {status=self.role=='manager'and 'approved'or 'idle'}end
    function self:enabled()return self.host~=nil end
    function self:setServer(s)
        if self.server==s then return end
        self.server=s;self.epoch=self.epoch+1;self.entries={};self.revision=-1;self.lastSuccess=0
        self.role='viewer';self.manager=nil;self.profile=nil;self.queue={};self.nextPoll=0;self.nextIdentity=nil;self.error=nil
        if self.key~=''then self.queue[1]={kind='identity',path='/api/me',method='GET',key=self.key}end
        if self.access then self.access:setServer(s)end
        o.policy(nil)
    end
    function self:accept(data,context)
        assert(data.ok and data.server==context.server,'Wrong game server in response')
        assert(type(data.revision)=='number'and data.revision>=0 and data.revision%1==0 and data.revision>=self.revision,'Invalid snapshot revision')
        if data.unchanged then assert(data.revision==self.revision,'Invalid unchanged revision');self.lastSuccess=o.clock();return end
        assert(type(data.assignments)=='table'and #data.assignments<=1004,'Invalid assignments')
        assert(type(data.policy)=='table','Missing duty policy')
        for _,name in ipairs({'civilianColors','maskColors','factionColors'})do
            assert(type(data.policy[name])=='table'and #data.policy[name]<=32,'Invalid policy colors')
            for _,c in ipairs(data.policy[name])do assert(type(c)=='string'and c:match('^%x%x%x%x%x%x$'),'Invalid color')end
        end
        local rows={}
        for _,row in ipairs(data.assignments)do
            assert(type(row)=='table'and o.validNick(row.nickname),'Invalid snapshot nickname')
            local entry=o.models[row.model];assert(entry and not entry.localOnly,'Unsupported shared model')
            local key=row.nickname:lower();assert(not rows[key],'Duplicate nickname')
            rows[key]={nickname=row.nickname,model=row.model}
        end
        local function fingerprint(p)if not p then return ''end;return tostring(p.enabled)..'/'..tostring(p.strictFactionColors==true)..'/'..table.concat(p.civilianColors,',')..'/'..table.concat(p.maskColors,',')..'/'..table.concat(p.factionColors,',')end
        local previous=fingerprint(self.profile)
        self.entries=rows;self.revision=data.revision;self.profile=data.policy;self.lastSuccess=o.clock()
        if previous~=fingerprint(data.policy)then o.policy(data.policy)end
    end
    function self:wanted()
        -- Never let an old server response or an unbounded offline cache control players.
        if self.lastSuccess==0 or o.clock()-self.lastSuccess>60 then return {}end
        return self.entries
    end
    function self:authenticate(key)
        assert(type(key)=='string'and key:match('^ms_%x+$')and #key==67,'Неверный формат ключа')
        assert(#self.queue<8,'Подожди завершения запроса')
        self.key=key;self.role='viewer';self.manager=nil
        self.queue[#self.queue+1]={kind='identity',path='/api/me',method='GET',key=key,manual=true}
    end
    function self:write(nickname,model,remove)
        assert(self.role=='manager'and self.manager and self.manager.server==self.server,'Для назначения открой /mskin и выбери «Получить доступ»')
        local localName=o.localNickname()
        assert(localName and localName:lower()==self.manager.nickname:lower(),'Ключ выдан другому нику. Обратись к владельцу панели')
        assert(o.validNick(nickname),'Неверный ник')
        if not remove then assert(o.models[model]and not o.models[model].localOnly,'Модель недоступна для общего списка')end
        assert(#self.queue<8,'Подожди завершения запроса')
        self.queue[#self.queue+1]={kind='write',path=remove and '/api/assignment/remove'or '/api/assignment',method='POST',key=self.key,
            body={catalog=3,server=self.server,nickname=nickname,model=not remove and model or nil},nickname=nickname,remove=remove}
    end
    function self:resetSelf()
        assert((self.role=='manager'or self.role=='player')and self.manager and self.manager.server==self.server,'Сначала подтверди свой ник')
        local name=o.localNickname()
        assert(name and name:lower()==self.manager.nickname:lower(),'Подтверждение выдано другому нику')
        assert(#self.queue<8,'Подожди завершения запроса')
        self.queue[#self.queue+1]={kind='self_reset',path='/api/self/reset',method='POST',key=self.key,
            body={server=self.server,catalog=3},nickname=name}
    end
    function self:tick()
        if not self:enabled()or self.server==''then return end
        local result=o.transport.poll()
        if result then
            local request=self.active;self.active=nil
            if request and request.epoch==self.epoch and request.server==self.server then
                local good,data=pcall(o.decode,result.body)
                if result.error~=0 or not good or type(data)~='table'or result.status~=200 or data.ok~=true then
                    self.error=result.error~=0 and ('HTTPS '..result.error)or (type(data)=='table'and data.error or 'invalid_response')
                    if result.status==401 or result.status==403 then self.role='viewer';self.manager=nil;self.nextIdentity=nil end
                    if request.kind=='identity'and result.status~=401 and result.status~=403 then self.nextIdentity=o.clock()+30 end
                    if request.kind:match('^access_')and self.access then self.access:failed(request)end
                    if request.kind~='snapshot'and request.kind~='access_poll'then o.message('Запрос не подтверждён: '..tostring(self.error)..'. Общий список будет перечитан.')end
                    self.nextPoll=o.clock()+self.backoff;self.backoff=math.min(30,self.backoff*2)
                else
                    local applied,err=pcall(function()
                        if request.kind:match('^access_')then self.access:handle(request,data)
                        elseif request.kind=='identity'then
                            local previousRole=self.role
                            assert((data.role=='manager'or data.role=='player')and data.server==self.server and o.validNick(data.nickname),'Ключ не подходит для этого сервера')
                            local currentName=o.localNickname();assert(currentName and currentName:lower()==data.nickname:lower(),'Доступ выдан другому нику. Открой /mskin  >  Получить доступ')
                            self.role=data.role;self.manager={server=data.server,nickname=data.nickname};self.nextIdentity=o.clock()+30
                            if self.persistedKey~=request.key then o.saveKey(request.key);self.persistedKey=request.key end
                            if self.access then self.access:identity(request.key,data.role)end
                            if previousRole=='player'and data.role=='manager'then o.message('Полный доступ активирован. Можно назначать скины себе и другим.')end
                            if request.manual then o.message('Ник и доступ подтверждены: '..data.nickname)end
                        else self:accept(data,request);if request.kind=='write'then o.message((request.remove and 'Замена снята: 'or 'Облик назначен: ')..request.nickname)
                            elseif request.kind=='self_reset'then o.message('Твой назначенный скин сброшен у всех пользователей скрипта.')end end
                    end)
                    if applied then self.error=nil else self.error=tostring(err)end
                    if not applied and request.kind:match('^access_')and self.access then self.access:failed(request)end
                    if not applied and request.kind=='identity'then self.role='viewer';self.manager=nil;self.nextIdentity=nil end
                    if not applied and request.kind~='snapshot'then o.message(tostring(err))end
                    self.backoff=5;self.nextPoll=o.clock()+(request.kind=='identity'and 0 or 5)
                end
            end
        end
        if self.access then self.access:tick()end
        if self.active then return end
        local request=table.remove(self.queue,1)
        if not request and self.nextIdentity and o.clock()>=self.nextIdentity and self.key~=''then
            self.nextIdentity=o.clock()+30;request={kind='identity',path='/api/me',method='GET',key=self.key}
        end
        if not request and o.clock()>=self.nextPoll then request={kind='snapshot',method='GET',path='/api/snapshot?server='..self.server..'&catalog=3&since='..self.revision,key=''}end
        if not request then return end
        request.server=self.server;request.epoch=self.epoch
        local body=request.body and o.encode(request.body)or ''
        if o.transport.start(self.host,request.path,request.method,body,request.key or '')then self.active=request
        else
            if request.kind~='snapshot'then table.insert(self.queue,1,request)end
            self.nextPoll=o.clock()+1
        end
    end
    return self
end
return M
