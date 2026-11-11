-- Pure state machine. Selected assets never become the server's model ID.
local M={};M.__index=M
function M.new(models)
    assert(type(models)=='table','Model registry required')
    return setmetatable({models=models,enabled=true,tracks={},candidates={},failures={}},M)
end
function M:setEnabled(value)self.enabled=value==true;self.candidates={};self.failures={}end
-- A native stream-in/skin RPC has already instantiated the assigned template.
-- Record ownership even when the newly created ped is seated in a vehicle.
function M:adopt(backend,key,selected)
    local s=backend.state(key)
    if not self.enabled or not self.models[selected] or not s.ready or s.blocked then return false end
    local entry=self.models[selected]
    if (entry.localOnly and not s.isLocal) or (entry.serverModel and entry.serverModel~=s.model) then return false end
    self.tracks[key]={ped=s.ped,clump=s.clump,model=s.model,playerId=s.playerId,server=s.server,asset=selected}
    self.candidates[key]=nil;self.failures[key]=nil
    return true
end
local function owned(t,s)
    return t and t.ped==s.ped and t.clump==s.clump and t.model==s.model and t.playerId==s.playerId and t.server==s.server
end
local function asset(entry)
    if type(entry)=='string' then return 179 end
    return type(entry)=='table' and entry.model or nil
end
function M:tick(backend,assignments)
    if backend.sweep then backend.sweep()end
    local keys,notices={},{}
    for k in pairs(assignments)do keys[k]=true end
    for k in pairs(self.tracks)do keys[k]=true end
    for key in pairs(keys)do
        local s=backend.state(key);local t=self.tracks[key]
        if not s.ready then self.tracks[key]=nil;self.candidates[key]=nil;self.failures[key]=nil
        else
            if t and (not owned(t,s) or (backend.owns and not backend.owns(key,s,t.asset))) then self.tracks[key]=nil;self.candidates[key]=nil;self.failures[key]=nil;t=nil end
            local selected=asset(assignments[key]);local wanted=self.enabled and selected~=nil and not s.blocked
            if wanted and not self.models[selected] then
                if self.failures[key]~='unsupported' then notices[#notices+1]=key..': unsupported custom model' end
                self.failures[key]='unsupported';wanted=false
            end
            local entry=selected and self.models[selected]
            if entry and ((entry.localOnly and not s.isLocal) or (entry.serverModel and entry.serverModel~=s.model)) then wanted=false end
            if s.safe then
                if not wanted and t and self.failures[key]~='restore' then
                    local ok,result=pcall(backend.replace,false,key,s)
                    if not ok then self.failures[key]='restore';notices[#notices+1]=key..': '..tostring(result)
                    elseif result then self.tracks[key]=nil;self.candidates[key]=nil;self.failures[key]=nil end
                elseif wanted and (not t or t.asset~=selected) and self.failures[key]~=('apply:'..selected) then
                    local identity=table.concat({s.server,s.playerId,s.ped,s.clump,s.model,selected},':');local c=self.candidates[key]
                    if not c or c.identity~=identity then c={identity=identity,count=0};self.candidates[key]=c end
                    c.count=c.count+1
                    if c.count>=3 then
                        -- Prepare first: a missing replacement must not remove an owned model.
                        local ok,result=pcall(function()backend.prepare(selected);return backend.replace(true,key,s,selected)end)
                        if not ok then self.failures[key]='apply:'..selected;notices[#notices+1]=key..': '..tostring(result)
                        elseif result then
                            self.tracks[key]={ped=s.ped,clump=result,model=s.model,playerId=s.playerId,server=s.server,asset=selected}
                            self.candidates[key]=nil;self.failures[key]=nil
                        end
                    end
                end
            else self.candidates[key]=nil end
        end
    end
    return notices
end
function M:restoreAll(backend)self.enabled=false;return self:tick(backend,{})end
return M
