local M={}
local accent='{D3DE96}';local white='{FFFFFF}';local muted='{A6B1A8}'
local labels={
 [147]='Президент Республики',
 [1061]='СВ — генерал',[61]='СВ — полковник',[255]='СВ — капитан',[179]='Полевой военный',[287]='Армейский военный',
 [285]='SFU-17 — боец, пустыня',[1285]='SFU-17 — боец, город',
 [2285]='ОСН — сапёр, пустыня',[2287]='ОСН — разведчик, пустыня',[3287]='ОСН — разведчик, город',
 [4285]='ОСН — командир, пустыня',[5285]='ОСН — командир, город',
 [120]='ОСН — оперативник 120, город',[1120]='ОСН — оперативник 120, пустыня',
 [2120]='FBI — оперативник',[4287]='FBI — разведчик'}
function M.new(o)
    local self={pending=nil,opening=false,view=nil}
    local function modelName(id)return labels[id]or (o.models[id]and o.models[id].name)or tostring(id)end
    local function simpleError(e)return tostring(e):gsub('^.-:%d+: ','')end
    function self:cancel()if not self.opening then self.pending=nil;self.view=nil end end
    function self:show(view,title,text,style,first,second,handler)
        local c=o.context()
        if not c.nickname or c.server==''then o.message('Сначала войди персонажем на сервер.');return end
        if o.foreignDialog()then o.message('Сначала закрой открытое окно сервера.');return end
        self.opening=true
        local ok,err=pcall(o.show,title,text,style,first or 'Выбрать',second or 'Назад')
        self.opening=false
        if not ok then error(err)end
        self.view=view;self.pending={server=c.server,owner=c.nickname,handler=handler}
    end
    function self:list(view,title,rows,back)
        local header=view=='models'and 'Облик\tКод'or view=='assignments'and 'Игрок\tОблик'or 'Действие\tСостояние'
        local text={muted..header}
        for _,r in ipairs(rows)do text[#text+1]=white..r[1]..'\t'..muted..(r[2]or '')end
        self:show(view,title,table.concat(text,'\n'),5,'Выбрать',back and 'Назад'or 'Закрыть',function(button,row)
            if button~=1 then if back then back()end;return end
            local selected=rows[row+1];if selected then selected[3]()end
        end)
    end
    function self:home()
        local s=o.state();local rows={}
        if s.manager then
            rows[#rows+1]={'Назначить облик игроку','По ID или нику',function()self:target('set')end}
            rows[#rows+1]={'Снять замену с игрока','Вернуть серверный облик',function()self:target('remove')end}
        end
        rows[#rows+1]={'Мой облик',s.hidden and 'Скрыт у меня'or 'Показывается',function()self:mine()end}
        rows[#rows+1]={'Назначенные облики',tostring(s.count)..' игроков',function()self:assignments(1)end}
        rows[#rows+1]={'Показывать замены',s.enabled and 'Включено'or 'Выключено',function()o.command(s.enabled and 'off'or 'on');self:home()end}
        rows[#rows+1]={s.manager and 'Мой доступ'or 'Получить доступ',s.manager and 'Управляющий'or 'Назначать облики другим',function()self:access()end}
        rows[#rows+1]={'Краткая справка','Как пользоваться',function()self:help()end}
        rows[#rows+1]={'Состояние','Подключение и версия',function()self:status()end}
        rows[#rows+1]={'Проверить обновления','Версия '..s.version,function()o.command('update')end}
        rows[#rows+1]={'Перезагрузить скрипт','Без перезапуска игры',function()o.command('reload')end}
        self:list('home','MilitarySkins',rows)
    end
    function self:mine()
        local s=o.state();local rows={
            {s.hidden and 'Показать мой назначенный облик'or 'Скрыть мой назначенный облик','Только на моём экране',function()o.command(s.hidden and 'me on'or 'me off');self:mine()end}}
        rows[#rows+1]={'Сбросить мой скин у всех','Вернуть серверный облик',function()self:resetSelf()end}
        if s.manager then rows[#rows+1]={'Выбрать облик себе','Из общего списка',function()self:modelsMenu(o.context().nickname)end}end
        self:list('mine','Мой облик',rows,function()self:home()end)
    end
    function self:target(verb)
        if not o.state().manager then self:access();return end
        self:show('target',verb=='set'and 'Кому назначить облик?'or 'С кого снять замену?',
            white..'Введи ID игрока из TAB или точный Nick_Name.\n\n'..muted..'Пример: '..accent..'42\n'..muted..'При вводе ID скрипт сам запомнит ник.',1,'Продолжить','Назад',function(button,row,input)
                if button~=1 then self:home();return end
                input=tostring(input or ''):match('^%s*(.-)%s*$')
                if #input<1 or #input>24 or input:find('%s')then o.message('Введи один ID или Nick_Name без пробелов.');self:target(verb);return end
                o.command(verb..' '..input)
                if verb=='remove'then self:home()end
            end)
    end
    function self:resetSelf()
        self:show('selfreset','Сбросить мой скин у всех?',white..'Общее назначение твоего ника будет удалено.\nВсе пользователи скрипта увидят обычный серверный скин.\n\n'..muted..'Назначения других игроков сохранятся.',0,'Сбросить','Назад',function(button)
            if button==1 then o.command('me reset')else self:mine()end
        end)
    end
    function self:modelsMenu(name,category)
        if not o.state().manager then self:access();return end
        if not category then
            self:list('categories','Категория для '..name,{
                {'Сухопутные войска','Состав СВ и ОСН',function()self:modelsMenu(name,'army')end},
                {'ФБР','Оперативник и разведчик FBI',function()self:modelsMenu(name,'fbi')end},
                {'Правительство','Президент Республики',function()self:modelsMenu(name,'government')end}
            },function()self:home()end);return
        end
        local rows={}
        for _,id in ipairs(o.order)do
            local group=o.models[id].category or ((id==2120 or id==4287)and 'fbi'or 'army')
            if category==group then local selected=id;rows[#rows+1]={modelName(id),tostring(id),function()o.command('set '..name..' '..selected);self:home()end}end
        end
        self:list('models',(category=='government'and 'Правительство — 'or category=='fbi'and 'ФБР — 'or 'СВ — ')..name,rows,function()self:modelsMenu(name)end)
    end
    function self:player(name)
        if not o.state().manager then self:assignments(1);return end
        self:list('player',name,{
            {'Изменить облик','Выбрать из списка',function()self:modelsMenu(name)end},
            {'Снять замену','Для всех пользователей скрипта',function()o.command('remove '..name);self:home()end}
        },function()self:assignments(1)end)
    end
    function self:assignments(page)
        local list={};for _,r in pairs(o.assignments())do list[#list+1]=r end
        table.sort(list,function(a,b)return a.nickname:lower()<b.nickname:lower()end)
        local pages=math.max(1,math.ceil(#list/15));page=math.max(1,math.min(page,pages));local rows={}
        for n=(page-1)*15+1,math.min(page*15,#list)do
            local r=list[n];rows[#rows+1]={r.nickname,modelName(r.model),function()self:player(r.nickname)end}
        end
        if #list==0 then rows[1]={'Назначений пока нет','',function()self:home()end}end
        if page<pages then rows[#rows+1]={'Следующая страница',tostring(page+1)..' / '..pages,function()self:assignments(page+1)end}end
        if page>1 then rows[#rows+1]={'Предыдущая страница',tostring(page-1)..' / '..pages,function()self:assignments(page-1)end}end
        self:list('assignments','Назначенные облики '..page..' / '..pages,rows,function()self:home()end)
    end
    function self:help()
        local manager=o.state().manager
        local lines={accent..'В ИГРЕ',white..'Открой /mskin и выбери нужное действие.',''}
        if manager then
            lines[#lines+1]=accent..'НАЗНАЧИТЬ ИГРОКУ'
            lines[#lines+1]=white..'«Назначить облик»  >  ID из TAB  >  выбрать форму.'
            lines[#lines+1]=muted..'Ник сохраняется автоматически, даже если ID позже изменится.'
            lines[#lines+1]=''
            lines[#lines+1]=accent..'БЫСТРЫЕ КОМАНДЫ'
            lines[#lines+1]=white..'/mskin 42 — выбрать облик игроку с ID 42'
            lines[#lines+1]=white..'/mskin remove 42 — снять общее назначение'
        else
            lines[#lines+1]=accent..'ПОЛУЧИТЬ ДОСТУП'
            lines[#lines+1]=white..'«Получить доступ»  >  создать запрос  >  сообщить код владельцу.'
            lines[#lines+1]=muted..'После одобрения доступ подключится автоматически.'
        end
        lines[#lines+1]='';lines[#lines+1]=accent..'СВОЙ ЭКРАН'
        lines[#lines+1]=white..'/mskin me off / on — скрыть или показать свой облик'
        lines[#lines+1]=white..'/mskin me reset — сбросить свой скин у всех'
        lines[#lines+1]=white..'/mskin off / on — скрыть или показать все замены'
        lines[#lines+1]=white..'/mskin update — проверить обновления, update off / on — автообновление'
        lines[#lines+1]=white..'/mskin reload — перезагрузить скрипт без перезапуска игры'
        lines[#lines+1]=muted..'Локальное скрытие не меняет общий список и видимость у других.'
        self:show('help','MilitarySkins — краткая справка',table.concat(lines,'\n'),0,'Назад','Закрыть',function(button)if button==1 then self:home()end end)
    end
    function self:access()
        local s=o.state();local a=o.access();local status=a.status or 'idle'
        local code=a.code and (a.code:sub(1,4)..'-'..a.code:sub(5))or nil
        local text,button
        if s.manager then text=accent..'Доступ управляющего активен.\n\n'..white..'Можно назначать и снимать облики через главное меню.';button='Назад'
        elseif status=='pending'or status=='confirming'then
            text=white..'Твой код: '..accent..(code or 'получаем...')..'\n\n'..white..'Сообщи код владельцу панели.\nОн сверит его с запросом и нажмёт «Разрешить».\n\n'..muted..'Подтверждение проверяется автоматически. Код действует 10 минут.';button='Обновить'
        elseif status=='sending'then text=white..'Отправляем запрос доступа...';button='Обновить'
        else
            local prefix=({denied='Запрос отклонён владельцем.\n\n',expired='Срок запроса истёк.\n\n',revoked='Доступ отозван.\n\n',error='Запрос не отправлен.\n\n'})[status]or ''
            text=white..prefix..'Нажми «Отправить запрос».\nВ панели появятся твой ник и короткий код.\n\n'..muted..'После подтверждения владельцем доступ включится сам.\nДлинные ключи вводить не нужно.';button='Отправить'
        end
        if a.scope=='self'and not s.manager then
            text=text..'\n\n'..muted..'Это подтверждение своего ника только для сброса скина.\nПраво менять облики других игроков не выдаётся.'
        end
        self:show('access',a.scope=='self'and 'Подтверждение моего ника'or 'Доступ к назначению обликов',text,0,button,'Назад',function(response)
            if response~=1 or s.manager then self:home();return end
            if status~='pending'and status~='sending'and status~='confirming'then o.command('access request')end
            self:access()
        end)
    end
    function self:accessChanged()
        if self.view=='access'and self.pending and o.ownDialog()then self:access()end
    end
    function self:status()
        local s=o.state();local text=white..'Версия: '..s.version..'\nДоступ: '..(s.manager and 'управляющий'or s.identified and 'свой скин'or 'просмотр')..
            '\nПодключение: '..(s.connected and 'есть'or 'ожидание')..'\nОбщих назначений: '..s.count..
            '\nПрименено рядом: '..s.active..'\nЗамены у меня: '..(s.enabled and 'включены'or 'выключены')..
            '\nАвтообновление: '..(s.autoUpdate and 'включено'or 'выключено')..
            '\n\n'..muted..'Подробная диагностика: /mskin debug'
        self:show('status','MilitarySkins — состояние',text,0,'Назад','Закрыть',function(button)if button==1 then self:home()end end)
    end
    function self:respond(button,row,input)
        local p=self.pending;if not p then return end
        self.pending=nil;self.view=nil
        local c=o.context()
        if c.server~=p.server or c.nickname~=p.owner then return end
        local ok,err=pcall(p.handler,button,row,input)
        if not ok then o.message(simpleError(err))end
    end
    return self
end
return M
