local M={}
M.order={1061,61,179,255,285,287,1285,2285,2287,3287,4285,5285,120,1120,2120,4287,147,1305,6285,1165,1166,1286,2286,228}
M.models={
    [61]={name='Полковник СВ',category='army',base=61,dff='officer61.dff',txd='officer61.txd',dictionary='military61_private'},
    [120]={name='ОСН SFU-17 — оперативник 120, город',category='army',base=285,dff='osn_operator120_urban.dff',txd='osn_operator120_urban.txd',dictionary='osn_op120_urban_private'},
    [179]={name='Полевой военный — пустыня',category='army',base=179,dff='soldier179.dff',txd='soldier179.txd',dictionary='military179_private'},
    [255]={name='Капитан СВ',category='army',base=255,dff='captain255.dff',txd='captain255.txd',dictionary='military255_private'},
    [285]={name='Спецназ SFU-17 — пустыня',category='army',base=285,dff='special285.dff',txd='special285.txd',dictionary='military285_private'},
    [287]={name='Армейский военный — пустыня',category='army',base=287,dff='army287.dff',txd='army287.txd',dictionary='military287_private'},
    [1061]={name='Генерал СВ',category='army',base=61,dff='general61.dff',txd='general61.txd',dictionary='militarygen_private'},
    [1120]={name='ОСН SFU-17 — оперативник 120, пустыня',category='army',base=285,dff='osn_operator120_desert.dff',txd='osn_operator120_desert.txd',dictionary='osn_op120_desert_private'},
    [1285]={name='SFU-17 — город',category='army',base=285,dff='sfu17urban.dff',txd='sfu17urban.txd',dictionary='sfu17urban_private'},
    [1305]={name='Полковник СВ — полевая форма (305)',category='army',base=287,dff='gf_colonel_field305.dff',txd='gf_colonel_field305.txd',dictionary='gf_colonel305_private'},
    [2285]={name='ОСН SFU-17 — сапёр, пустыня',category='army',base=285,dff='osn_sapper.dff',txd='osn_sapper.txd',dictionary='osn_sapper_private'},
    [2287]={name='ОСН SFU-17 — разведчик, пустыня',category='army',base=285,dff='osn_scout.dff',txd='osn_scout.txd',dictionary='osn_scout_private'},
    [3287]={name='ОСН SFU-17 — разведчик, город',category='army',base=285,dff='osn_scout_urban.dff',txd='osn_scout_urban.txd',dictionary='osn_scout_urban_private'},
    [4285]={name='ОСН SFU-17 — командир, пустыня',category='army',base=285,dff='osn_commander.dff',txd='osn_commander.txd',dictionary='osn_cmd_desert_private'},
    [5285]={name='ОСН SFU-17 — командир, город',category='army',base=285,dff='osn_commander_urban.dff',txd='osn_commander_urban.txd',dictionary='osn_cmd_urban_private'},
    [6285]={name='Старший лейтенант СВ — пустыня',category='army',base=285,dff='gf_senior_lieutenant_desert.dff',txd='gf_senior_lieutenant_desert.txd',dictionary='gfsl_desert_private'},
    [1165]={name='FBI — агент в костюме (165)',category='fbi',base=165,dff='fbi_agent165.dff',txd='fbi_agent165.txd',dictionary='fbi_agent165_private'},
    [1166]={name='FBI — агент в костюме (166)',category='fbi',base=166,dff='fbi_agent166.dff',txd='fbi_agent166.txd',dictionary='fbi_agent166_private'},
    [1286]={name='FBI — агент',category='fbi',base=286,dff='fbi.dff',txd='fbi.txd',dictionary='fbi_agent_enh_private'},
    [2120]={name='FBI — оперативник 120',category='fbi',base=285,dff='fbi_operator120.dff',txd='fbi_operator120.txd',dictionary='fbi_op120_private'},
    [2286]={name='FBI — специальный агент',category='fbi',base=286,dff='fbi_agent286.dff',txd='fbi_agent286.txd',dictionary='fbi_agent286_private'},
    [4287]={name='FBI — разведчик',category='fbi',base=285,dff='fbi_scout.dff',txd='fbi_scout.txd',dictionary='fbi_scout_private'},
    [147]={name='Президент Республики',category='government',base=147,dff='president147.dff',txd='president147.txd',dictionary='republic_pres147_private'},
    [228]={name='Мэр города',category='government',base=228,dff='mayor228.dff',txd='mayor228.txd',dictionary='republic_mayor228_private'},
}
function M.menuOrder(isSelf)
    local ids={};for _,id in ipairs(M.order)do ids[#ids+1]=id end
    return ids
end
function M.modelIds(isSelf)return table.concat(M.menuOrder(isSelf),'|')end
function M.dialogText(isSelf)
    local rows={}
    for _,id in ipairs(M.menuOrder(isSelf))do rows[#rows+1]=id..' — '..M.models[id].name end
    rows[#rows+1]='Обычный серверный скин'
    return table.concat(rows,'\n')
end
function M.dialogSelection(row,isSelf)
    if type(row)~='number' or row%1~=0 or row<0 then return nil,false end
    local ids=M.menuOrder(isSelf)
    return ids[row+1],row==#ids
end
function M.validNick(n)
    return type(n)=='string' and #n>=1 and #n<=24 and not n:find('[^%w_%[%]$@=().]')
end
function M.normalize(data)
    assert(type(data)=='table' and (data.version==1 or data.version==2),'Unsupported assignments.json version')
    assert(type(data.servers)=='table','Invalid server assignments')
    local out={version=2,enabled=data.enabled~=false,servers={}}
    local migrated=data.version~=2
    for address,list in pairs(data.servers) do
        assert(type(address)=='string' and type(list)=='table','Invalid server entry')
        local dest={};out.servers[address]=dest
        for key,entry in pairs(list) do
            local nickname,model
            if type(entry)=='string' then nickname,model=entry,179;migrated=true
            else
                assert(type(entry)=='table','Invalid player assignment')
                nickname,model=entry.nickname,entry.model
            end
            assert(M.validNick(nickname) and type(key)=='string' and key==nickname:lower(),'Invalid nickname assignment')
            assert(type(model)=='number' and M.models[model],'Unsupported custom model: '..tostring(model))
            dest[key]={nickname=nickname,model=model}
        end
    end
    return out,migrated
end
function M.assign(config,server,nickname,model)
    assert(M.validNick(nickname),'Invalid nickname')
    config.servers[server]=config.servers[server] or {}
    local key=nickname:lower();local existing=config.servers[server][key]
    model=model or (existing and existing.model) or 179
    assert(M.models[model],'Unsupported custom model: '..tostring(model))
    config.servers[server][key]={nickname=nickname,model=model}
    return model
end
return M
