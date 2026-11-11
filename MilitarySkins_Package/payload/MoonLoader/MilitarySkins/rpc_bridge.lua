-- Connect before inspecting RPC nodes. Opcode 0B7D crashes on this R3 build;
-- validate the actual native handler in the readable/writable node instead.
local ffi=require'ffi'
local M={}
local cast='void (__cdecl *)(void*)'
local function address(p)return tonumber(ffi.cast('uintptr_t',p))end
local function u32(p,offset)return tonumber(ffi.cast('uint32_t*',ffi.cast('uint8_t*',p)+offset)[0])end
local function slot(p,offset)return ffi.cast('uint32_t*',ffi.cast('uint8_t*',p)+offset)end
local function decode(id,params,access)
    if params==nil or not access(address(params),8,false) then return end
    local head=ffi.cast('uint32_t*',params);local ptr,bits=tonumber(head[0]),tonumber(head[1])
    local bytes=id==32 and 28 or 8
    if bits<bytes*8 or not access(ptr,bytes,false)then return end
    local b=ffi.cast('uint8_t*',ptr)
    local function unsigned(off,size)local n=0;for j=0,size-1 do n=n+tonumber(b[off+j])*256^j end;return n end
    local player,model
    if id==32 then player,model=unsigned(0,2),unsigned(3,4)
    elseif id==153 then player,model=unsigned(0,4),unsigned(4,4)
    else return end
    if player>1003 or model<1 or model>311 or model==74 then return end
    return {rpc=id,playerId=player,serverModel=model,color=id==32 and unsigned(23,4)or nil}
end
function M.new(handler,onError,api)
    api=api or {}
    local getNode=api.getNode or sampGetRpcNodeByRpcId
    local validate=assert(api.validate,'Native RPC build validator required')
    local access=assert(api.access,'Native memory span validator required')
    local ready=api.ready or function()return true end
    local bridge={records={},retired={},calls=0,applied=0,lastError=nil,active=false}
    local function errorOnce(message)
        message=tostring(message)
        if bridge.lastError~=message then bridge.lastError=message;if onError then pcall(onError,message)end end
    end
    local function liveNode(id)
        local ok,node=pcall(getNode,id)
        if not ok then errorOnce('RPC node getter: '..tostring(node));return 0 end
        node=tonumber(node) or 0;if node<0 then node=node+0x100000000 end
        if not access(node,8,true)then return 0 end
        if tonumber(ffi.cast('uint8_t*',node)[0])~=id then return 0 end
        return node
    end
    function bridge.refresh()
        bridge.active=false
        if not ready() then return false end
        if type(getNode)~='function' then errorOnce('SAMPFUNCS RPC node API unavailable');return false end
        local active=0
        for _,id in ipairs({32,153})do
            local node=liveNode(id);local r=bridge.records[id]
            if r and node==r.node and u32(node,r.offset)==r.callbackAddress then active=active+1
            else
                if r then bridge.retired[#bridge.retired+1]=r;bridge.records[id]=nil end
                if node~=0 then
                    local offset,original
                    for _,candidate in ipairs({1,4})do
                        local pointer=u32(node,candidate)
                        if pointer~=0 and validate(id,pointer)then
                            assert(not offset,'Ambiguous RPC callback slot');offset,original=candidate,pointer
                        end
                    end
                    if offset then
                        local originalCall=ffi.cast(cast,original)
                        local callback=ffi.cast(cast,function(params)
                            local called=false
                            local function invoke()assert(not called,'RPC invoked twice');called=true;return originalCall(params)end
                            local ok,err=pcall(function()
                                local data=decode(id,params,access)
                                if data then bridge.calls=bridge.calls+1;if handler(data,invoke)then bridge.applied=bridge.applied+1 end end
                            end)
                            if not ok then errorOnce(err)end
                            if not called then local good,e=pcall(invoke);if not good then errorOnce(e)end end
                        end)
                        local record={node=node,offset=offset,original=original,callback=callback,callbackAddress=address(callback)}
                        slot(node,offset)[0]=record.callbackAddress;bridge.records[id]=record;active=active+1
                    else errorOnce('Native RPC build/callback mismatch: '..id)end
                end
            end
        end
        bridge.active=active==2;return bridge.active
    end
    function bridge.stop()
        for id,r in pairs(bridge.records)do
            local current=liveNode(id)
            if current==r.node and u32(current,r.offset)==r.callbackAddress then slot(current,r.offset)[0]=r.original end
            bridge.retired[#bridge.retired+1]=r
        end
        bridge.records={};bridge.active=false
    end
    return bridge
end
local ok,jit=pcall(require,'jit');if ok then jit.off(M.new,true);jit.off(decode,true)end
return M
