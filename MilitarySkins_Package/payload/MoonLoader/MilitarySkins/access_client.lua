local M={}
function M.new(o)
    local self={server='',state='idle',record=o.pending,nextPoll=0,busy=false}
    if type(self.record)=='table'then self.record.scope='manager'end
    local terminal={denied=true,expired=true,revoked=true}
    local function changed()if o.changed then o.changed()end end
    function self:public()
        if o.isManager()then return {status='approved'}end
        return {status=self.state,scope=self.record and self.record.scope or nil,code=self.record and self.record.code or nil,expires=self.record and self.record.expires or nil}
    end
    function self:setServer(s)
        self.server=s;self.busy=false;self.nextPoll=0;self.state='idle'
        local r=self.record
        if type(r)=='table'and r.server==s and type(r.key)=='string'and #r.key==67 and type(r.expires)=='number'and r.expires>o.clock()then self.state='pending'
        else self.record=nil end
    end
    function self:request(scope)
        scope='manager' -- One owner-approved permission for self and other players.
        if o.isManager()then changed();return end
        local name=o.nickname();assert(o.validNick(name),'Сначала войди персонажем')
        assert(self.server~='','Сначала подключись к серверу')
        if self.busy then return end
        local r=self.record
        if not r or r.server~=self.server or r.nickname~=name or r.scope~=scope or r.expires<=o.clock()or terminal[self.state]then
            r={server=self.server,nickname=name,scope=scope,key=o.newKey(),expires=o.clock()+600};self.record=r
            o.save(r)
        end
        self.state='sending';self.busy=true
        o.send({kind='access_request',method='POST',path='/api/access/request',key='',
            body={server=r.server,nickname=r.nickname,proof=r.key,scope=r.scope}})
        changed()
    end
    function self:tick()
        if o.isManager()or self.busy or not self.record or self.record.server~=self.server then return end
        local r=self.record
        if r.expires<=o.clock()then self.state='expired';self.record=nil;o.save(nil);changed();return end
        if r.nickname~=o.nickname()then return end
        if (self.state=='pending'or self.state=='confirming')and o.clock()>=self.nextPoll then
            if not r.id then self:request();return end
            self.busy=true
            o.send({kind='access_poll',method='POST',path='/api/access/poll',key='',body={id=r.id,proof=r.key}})
        end
    end
    function self:handle(request,data)
        self.busy=false;local r=assert(self.record,'Запрос уже закрыт')
        if request.kind=='access_request'then
            assert(data.server==r.server and data.nickname==r.nickname and type(data.id)=='string'and #data.id==36,'Некорректный ответ запроса')
            assert(type(data.code)=='string'and data.code:match('^%d%d%d%d%d%d%d%d$')and type(data.expires)=='number','Некорректный код подтверждения')
            r.id=data.id;r.code=data.code;r.expires=data.expires;o.save(r);self.state='pending';self.nextPoll=o.clock()+3
        else
            assert(data.status=='pending'or data.status=='approved'or terminal[data.status],'Неизвестное состояние доступа')
            if data.status=='approved'then
                assert(data.server==r.server and data.nickname==r.nickname,'Ответ для другого персонажа')
                self.state='confirming';self.nextPoll=o.clock()+10;o.authorize(r.key)
            elseif terminal[data.status]then self.state=data.status;self.record=nil;o.save(nil)
            else self.state='pending';self.nextPoll=o.clock()+3 end
        end
        changed()
    end
    function self:failed(request)
        self.busy=false;self.nextPoll=o.clock()+10
        self.state=self.record and 'pending'or 'error';changed()
    end
    function self:identity(key,role)
        if self.record and self.record.key==key then
            self.state='approved';self.record=nil;o.save(nil);changed()
            o.message(role=='manager'and 'Полный доступ получен. В /mskin можно назначать скины себе и другим.'or 'Доступ ограничен. Попроси владельца панели разрешить назначения.')
        end
    end
    return self
end
return M
