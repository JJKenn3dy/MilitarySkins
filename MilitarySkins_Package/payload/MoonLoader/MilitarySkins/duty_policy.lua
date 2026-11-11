-- SAMPFUNCS colors are AARRGGBB; RPC SetPlayerColor carries RRGGBBAA.
local M={}
function M.rgb(value,rpc)
    if type(value)=='string' then
        if #value==6 and value:match('^%x+$')then return value:upper()end
        if #value==8 and value:match('^%x+$')then return rpc and value:sub(1,6):upper()or value:sub(3,8):upper()end
    elseif type(value)=='number'then
        local n=value%4294967296
        return string.format('%06X',rpc and math.floor(n/256)or n%16777216)
    end
end
local function has(list,value)for _,v in ipairs(list or {})do if v==value then return true end end;return false end
function M.new(profile)
    local self={profile=profile or {},states={}}
    function self:configure(value)self.profile=value or {};self.states={}end
    function self:clear(id)self.states[id]=nil end
    function self:color(id,nickname,color,rpc,source)
        if type(nickname)~='string'then return end
        local key=nickname:lower();local p=self.profile;local rgb=M.rgb(color,rpc)
        if not rgb then return end
        local row=self.states[id]
        if not row or row.key~=key then row={key=key,duty='unknown'};self.states[id]=row end
        row.rgb=rgb
        if not p.enabled then return end
        if has(p.civilianColors,rgb)then row.duty='off';row.masked=false;row.evidence=source or 'color'
        elseif has(p.maskColors,rgb)then row.masked=true -- NEVER change duty for mask, including alpha 00 -> AA.
        elseif has(p.factionColors,rgb)then row.duty='on';row.masked=false;row.evidence=source or 'color'
        elseif not p.strictFactionColors then row.duty='on';row.masked=false;row.evidence=source or 'non_civilian_color'
        else row.masked=false end
    end
    function self:ownMessage(id,nickname,kind)
        if not nickname then return end
        local key=nickname:lower();local r=self.states[id]
        if not r or r.key~=key then r={key=key,duty='unknown'};self.states[id]=r end
        if kind=='duty_off'then r.duty='off';r.evidence='own_server_message'
        elseif kind=='duty_on_candidate'then r.duty='on';r.evidence='own_server_message'
        elseif kind=='mask_on'then r.masked=true
        elseif kind=='mask_off'then r.masked=false end
    end
    function self:allows(id,nickname)
        if not self.profile.enabled then return true end
        local r=self.states[id]
        if not r or r.key~=nickname:lower()then return true end
        if r.duty=='off'then return false end
        -- A mask is not evidence of being off duty. A late viewer/reconnecting
        -- player can already have it on before any faction color is observed.
        -- Keep duty unknown but allow the saved assignment until an actual
        -- civilian color/end-of-shift is observed in this connection.
        return true
    end
    return self
end
return M
