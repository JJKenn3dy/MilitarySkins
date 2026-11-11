-- Read-only telemetry. Never changes models, RPC payloads, assignments or chat.
local M={}
function M.classify(text)
    text=tostring(text or ''):gsub('{%x%x%x%x%x%x}','')
    if text:sub(1,#'[Успешно] Вы надели маску.')=='[Успешно] Вы надели маску.' then return 'mask_on' end
    if text:sub(1,#'[Успешно] Вы сняли маску.')=='[Успешно] Вы сняли маску.' then return 'mask_off' end
    if text:sub(1,#'[Успешно] Вы закончили рабочий день.')=='[Успешно] Вы закончили рабочий день.' then return 'duty_off' end
    if text:sub(1,#'[Успешно] Вы начали рабочий день.')=='[Успешно] Вы начали рабочий день.' then return 'duty_on_candidate' end
end
function M.color(value)
    if type(value)~='number' then return nil end
    return string.format('%08X',value%4294967296)
end
function M.new(options)
    local self={enabled=options.enabled~=false,last={},started=options.clock(),count=0,error=nil}
    local path=options.path
    -- Bound the previous recording; no chat history or credentials are recorded.
    local f=io.open(path,'rb')
    if f then local size=f:seek('end');f:close();if size and size>524288 then os.remove(path..'.previous');os.rename(path,path..'.previous')end end
    function self:write(kind,data)
        if not self.enabled then return end
        if self.count>=6000 or options.clock()-self.started>3600000 then self.enabled=false;return end
        local row={time=os.date('!%Y-%m-%dT%H:%M:%SZ'),elapsed_ms=options.clock()-self.started,event=kind,server=options.server(),data=data}
        local ok,encoded=pcall(options.encode,row)
        if not ok then self.error=tostring(encoded);return end
        local out,err=io.open(path,'ab');if not out then self.error=tostring(err);return end
        out:write(encoded,'\n');out:close();self.count=self.count+1
    end
    function self:player(kind,id,extra)
        if not self.enabled or type(id)~='number' then return end
        local ok,row=pcall(options.observe,id)
        if not ok then self:issue('observe',row);return end
        if not row then return end
        row.id=id;row.details=extra
        self:write(kind,row)
    end
    function self:poll()
        if not self.enabled then return end
        local ok,ids=pcall(options.players);if not ok then self:issue('players',ids);return end
        local seen={}
        for _,id in ipairs(ids)do
            seen[id]=true
            local good,row=pcall(options.observe,id)
            if not good then self:issue('observe',row)end
            if good and row then
                row.id=id
                local fingerprint=options.encode(row)
                if self.last[id]~=fingerprint then self.last[id]=fingerprint;self:write('observed',row)end
            end
        end
        for id in pairs(self.last)do if not seen[id]then self.last[id]=nil end end
    end
    function self:issue(where,err)
        local description=where..': '..tostring(err)
        if self.error~=description then self.error=description;self:write('diagnostic_error',{message=description})end
    end
    function self:message(text,id)
        local kind=M.classify(text)
        if kind then self:player(kind,id);self.last={}end
    end
    function self:command(arg)
        if arg=='off' then self:write('recording_stopped',{});self.enabled=false
        elseif arg=='on' then self.enabled=true;self.started=options.clock();self.count=0;self.last={};self:write('recording_started',{})
        elseif arg:match('^mark ')then self:write('mark',{label=arg:sub(6,70)})end
        return 'Диагностика: '..(self.enabled and 'включена' or 'выключена')..'; записей: '..self.count..(self.error and '; ошибка: '..self.error or '')..'. Файл duty_diagnostics.jsonl'
    end
    self:write('recording_started',{version=1})
    return self
end
return M
