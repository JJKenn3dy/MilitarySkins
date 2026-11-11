-- Обновление из GitHub Releases без перезапуска игры (не путать с прежним updater.lua
-- через Cloudflare: установщик отключает тот файл как устаревший).
-- Список файлов: manifest.json последнего релиза. Файлы: тот же тег (v<версия>).
-- Ставится только версия НОВЕЕ установленной: локальные правки не перезаписываются.
-- Всё скачивается рядом (.msnew) и проверяется по SHA256 до замены; прежние файлы
-- остаются как .msold для отката. Работает по одному шагу за вызов tick().
local ffi=require'ffi'
local M={}
M.manifestUrl='https://github.com/JJKenn3dy/MilitarySkins/releases/latest/download/manifest.json'
M.rawBase='https://raw.githubusercontent.com/JJKenn3dy/MilitarySkins/'
local FIRST_DELAY,INTERVAL,RETRY=30,1800,600
local MANIFEST_TIMEOUT,FILE_TIMEOUT=30,240
local PERSONAL={['moonloader\\militaryskins\\cloud_config.json']=true}

function M.compare(a,b)
    local function parts(v)local t={};for n in tostring(v):gmatch('%d+')do t[#t+1]=tonumber(n)end;return t end
    local x,y=parts(a),parts(b)
    for i=1,math.max(#x,#y)do
        local p,q=x[i]or 0,y[i]or 0
        if p~=q then return p<q and -1 or 1 end
    end
    return 0
end

local bcrypt,algorithm
local function declare(line)pcall(ffi.cdef,line)end
-- SHA256 через Windows CNG, файл читается частями по 1 МБ. nil, если файла нет.
function M.sha256(path)
    local f=io.open(path,'rb');if not f then return nil end
    if not bcrypt then
        declare'long __stdcall BCryptOpenAlgorithmProvider(void**,const uint16_t*,const uint16_t*,unsigned long);'
        declare'long __stdcall BCryptCreateHash(void*,void**,unsigned char*,unsigned long,unsigned char*,unsigned long,unsigned long);'
        declare'long __stdcall BCryptHashData(void*,const char*,unsigned long,unsigned long);'
        declare'long __stdcall BCryptFinishHash(void*,unsigned char*,unsigned long,unsigned long);'
        declare'long __stdcall BCryptDestroyHash(void*);'
        local lib=ffi.load('bcrypt')
        local handle=ffi.new('void*[1]');local name=ffi.new('uint16_t[7]',{83,72,65,50,53,54,0})
        if lib.BCryptOpenAlgorithmProvider(handle,name,nil,0)~=0 then f:close();error('SHA256 недоступен')end
        bcrypt,algorithm=lib,handle[0]
    end
    local hash=ffi.new('void*[1]')
    if bcrypt.BCryptCreateHash(algorithm,hash,nil,0,nil,0,0)~=0 then f:close();error('SHA256 недоступен')end
    local ok=true
    while true do
        local chunk=f:read(1048576);if not chunk then break end
        if bcrypt.BCryptHashData(hash[0],chunk,#chunk,0)~=0 then ok=false;break end
    end
    f:close()
    local out=ffi.new('unsigned char[32]')
    if ok and bcrypt.BCryptFinishHash(hash[0],out,32,0)~=0 then ok=false end
    bcrypt.BCryptDestroyHash(hash[0])
    assert(ok,'Ошибка SHA256')
    local hex={};for i=0,31 do hex[#hex+1]=string.format('%02x',out[i])end
    return table.concat(hex)
end

local function readFile(path)
    local f=io.open(path,'rb');if not f then return nil end
    local text=f:read('*a');f:close();return text
end
local function exists(path)local f=io.open(path,'rb');if f then f:close();return true end;return false end

-- Проверка списка из сети: только файлы внутри MoonLoader, только известный формат.
function M.validate(m)
    assert(type(m)=='table'and type(m.version)=='string'and m.version:match('^%d+%.%d+%.%d+$'),'Неверная версия в списке файлов')
    assert(type(m.files)=='table'and #m.files>0,'Пустой список файлов')
    for _,f in ipairs(m.files)do
        assert(type(f)=='table'and type(f.name)=='string'and type(f.sha256)=='string','Неверная запись в списке файлов')
        assert(f.name:sub(1,11):lower()=='moonloader\\'and not f.name:find('..',1,true)
            and f.name:match('^[%w_%.\\%-]+$'),'Недопустимый путь: '..f.name)
        assert(#f.sha256==64 and f.sha256:match('^%x+$'),'Неверный SHA256: '..f.name)
        f.sha256=f.sha256:lower()
    end
    return m
end

function M.new(o)
    local sha=o.sha256 or M.sha256
    local self={phase='idle',auto=true,manual=false,nextCheck=o.clock()+FIRST_DELAY,last='ещё не проверялось',latest=nil}
    local saved={}
    do
        local text=readFile(o.settingsPath)
        if text then local ok,value=pcall(o.decode,text);if ok and type(value)=='table'then saved=value end end
        if saved.auto==false then self.auto=false end
    end
    local function save()
        saved.auto=self.auto
        local f=io.open(o.settingsPath,'w');if f then f:write(o.encode(saved));f:close()end
    end
    local function localPath(name)return o.root..'\\'..name:sub(12)end
    local function short(name)return (name:match('([^\\]+)$'))end
    local function cleanup()
        for _,item in ipairs(self.queue or {})do os.remove(item.path..'.msnew')end
        self.queue=nil;self.remote=nil
    end
    local function finish(text,delay)
        self.phase='idle';self.last=text;self.nextCheck=o.clock()+(delay or INTERVAL)
        o.trace('Update: '..text)
        if self.manual then o.message('Обновление: '..text)end
        self.manual=false
    end
    local function fail(text)cleanup();finish(text,RETRY)end

    function self:check(manual)
        if self.phase~='idle'then if manual then o.message('Обновление: проверка уже идёт.')end;return end
        self.manual=manual and true or false
        if manual then o.message('Проверяю обновления...')end
        local path=o.root..'\\MilitarySkins\\manifest.update.json';os.remove(path)
        self.job=o.download(M.manifestUrl..'?t='..tostring(o.clock()),path)
        self.started=o.clock();self.phase='manifest'
    end
    function self:setAuto(value)self.auto=value and true or false;save()end

    function self:tick()
        local now=o.clock()
        if self.phase=='idle'then
            if self.auto and now>=self.nextCheck then self:check(false)end
        elseif self.phase=='manifest'then
            local state=self.job:state()
            if state=='pending'then
                if now-self.started>MANIFEST_TIMEOUT then fail('нет ответа от GitHub')end
                return
            end
            local text=readFile(self.job.path);os.remove(self.job.path)
            if state=='failed'or not text or text==''then return fail('не удалось получить список версий')end
            local ok,m=pcall(function()return M.validate(o.decode(text))end)
            if not ok then return fail(tostring(m))end
            self.latest=m.version
            if M.compare(m.version,o.version)<=0 then return finish('установлена актуальная версия '..o.version)end
            self.remote=m;self.queue={};self.index=1;self.phase='hash'
            o.trace('Update: found '..m.version)
        elseif self.phase=='hash'then
            -- Один файл за вызов, чтобы не было заметного подвисания.
            local f=self.remote.files[self.index]
            if not f then
                if #self.queue==0 then local v=self.remote.version;cleanup();return finish('файлы '..v..' уже на месте')end
                self.phase='download';self.index=1
                o.message('Найдено обновление '..self.remote.version..', загружаю файлов: '..#self.queue)
                return
            end
            self.index=self.index+1
            local path=localPath(f.name)
            if PERSONAL[f.name:lower()]and exists(path)then return end
            if sha(path)~=f.sha256 then self.queue[#self.queue+1]={entry=f,path=path}end
        elseif self.phase=='download'then
            local item=self.queue[self.index]
            if not item then self.phase='apply';return end
            if not item.job then
                os.remove(item.path..'.msnew')
                local url=M.rawBase..'v'..self.remote.version..'/MilitarySkins_Package/payload/'..(item.entry.name:gsub('\\','/'))
                item.job=o.download(url,item.path..'.msnew');item.started=now;return
            end
            local state=item.job:state()
            if state=='pending'then
                if now-item.started>FILE_TIMEOUT then fail('нет ответа при загрузке '..short(item.entry.name))end
                return
            end
            if state=='failed'or sha(item.path..'.msnew')~=item.entry.sha256 then
                return fail('файл '..short(item.entry.name)..' загрузился с ошибкой, повторю позже')
            end
            self.index=self.index+1
        elseif self.phase=='apply'then
            self:apply()
        end
    end

    -- Замена всех файлов сразу. При любой ошибке уже заменённые возвращаются.
    function self:apply()
        local done,restart={},false
        for _,item in ipairs(self.queue)do
            local target=item.path;local old=target..'.msold'
            os.remove(old)
            local existed=exists(target);local ok=true
            if existed then ok=os.rename(target,old)end
            if ok then
                ok=os.rename(target..'.msnew',target)
                if not ok and existed then os.rename(old,target)end
            end
            if not ok then
                for i=#done,1,-1 do
                    local d=done[i];os.remove(d.path)
                    if d.existed then os.rename(d.path..'.msold',d.path)end
                end
                return fail('не удалось заменить '..short(item.entry.name)..', прежние файлы возвращены')
            end
            done[#done+1]={path=target,existed=existed}
            if target:lower():match('%.dll$')then restart=true end
        end
        local version=self.remote.version
        saved.lastApplied={version=version,from=o.version,files={}}
        for _,d in ipairs(done)do saved.lastApplied.files[#saved.lastApplied.files+1]={path=d.path,existed=d.existed}end
        save()
        self.queue=nil;self.remote=nil;self.phase='applied';self.last='установлена '..version
        o.trace('Update: applied '..version..' files='..#done)
        o.applied(version,restart,#done)
    end

    -- Вернуть файлы, заменённые последним обновлением (из .msold).
    function self:rollback()
        local last=saved.lastApplied
        if not last or type(last.files)~='table'or #last.files==0 then o.message('Обновление: откатывать нечего.');return false end
        if self.phase~='idle'and self.phase~='applied'then o.message('Обновление: дождись окончания текущей проверки.');return false end
        for _,d in ipairs(last.files)do
            if d.existed and not exists(d.path..'.msold')then o.message('Обновление: нет прежней копии '..short(d.path)..', откат отменён.');return false end
        end
        for _,d in ipairs(last.files)do
            if d.existed then
                os.remove(d.path..'.msback');os.rename(d.path,d.path..'.msback')
                os.rename(d.path..'.msold',d.path);os.remove(d.path..'.msback')
            else os.remove(d.path)end
        end
        -- Не ставить ту же версию снова автоматически.
        self.auto=false;saved.lastApplied=nil;save()
        o.trace('Update: rolled back '..tostring(last.version)..' -> '..tostring(last.from))
        o.applied(last.from,false,#last.files,true)
        return true
    end

    function self:statusText()
        local text='версия '..o.version..', автообновление '..(self.auto and 'включено'or 'выключено')
        if self.latest then text=text..', в релизе '..self.latest end
        return text..'. Последняя проверка: '..self.last
    end
    return self
end
return M
