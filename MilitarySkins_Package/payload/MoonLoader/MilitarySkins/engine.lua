-- GTA SA 1.0 US backend, checked against the user's gta_sa.exe.
-- No SA-MP patches, packets, server skin changes, or spare ped model IDs.
local ffi = require 'ffi'
local M = {}

local signatures = {
    [0x749D40] = '568b742408578b7c', -- RpAtomicSetGeometry
    [0x74CCC0] = '568b742408668b46', -- RpGeometryDestroy
    [0x7C7520] = '8b4424048b15a478', -- RpSkinAtomicSetHAnimHierarchy
    [0x7C7540] = '8b4424048b0da478', -- RpSkinAtomicGetHAnimHierarchy
    [0x7C7550] = '8b4424048b0da878', -- RpSkinGeometryGetSkin
    [0x7C77E0] = '8b4424048b00c390', -- RpSkinGetNumBones
    [0x4C7340] = '56578b7c240c578b', -- CPedModelInfo::SetClump
    [0x7ECEF0] = 'a1247bc9008b0d2c', -- RwStreamOpen
    [0x7ECE20] = '83ec08568b742410', -- RwStreamClose
    [0x7ED2D0] = '83ec0c8d4424048d', -- RwStreamFindChunk
    [0x74B420] = '83ec448d4424048d', -- RpClumpStreamRead
    [0x731C80] = '8b0d0c80c80056e8', -- CTxdStore::AddTxdSlot
    [0x7320B0] = '8b44240890e9a700', -- CTxdStore::LoadTxd(filename)
    [0x7316A0] = 'e8eb230c00e9ce04', -- CTxdStore::PushCurrentTxd
    [0x7316B0] = 'a11080c80050e8b5', -- CTxdStore::PopCurrentTxd
    [0x7319C0] = '8b0d0c80c8008b51', -- CTxdStore::SetCurrentTxd
    [0x731A00] = '8b0d0c80c8008b51', -- CTxdStore::AddRef
}

local function ptr(value) return ffi.cast('uint8_t*', value) end
local function number(value) return tonumber(ffi.cast('uintptr_t', value)) end
local function pointerAt(value, offset) return ffi.cast('void**', ptr(value) + offset) end
local function hex(value)
    return (value:gsub('.', function(c) return string.format('%02x', c:byte()) end))
end
local function fileExists(path)
    local f = io.open(path, 'rb')
    if f then f:close(); return true end
    return false
end

function M.new(directory, lookup, currentServer)
    local Settings=dofile(directory..'\\settings.lua')
    assert(ffi.abi('32bit'), 'This mod requires 32-bit GTA SA.')
    ffi.cdef 'void* __stdcall GetModuleHandleA(const char* moduleName);'
    assert(number(ffi.load('kernel32').GetModuleHandleA(nil)) == 0x400000,
        'Unsupported GTA image base. No model changed.')
    local setClump = ffi.cast('void (__thiscall *)(void*, void*)', 0x4C7340)
    local streamOpen = ffi.cast('void* (__cdecl *)(int, int, const char*)', 0x7ECEF0)
    local streamClose = ffi.cast('int (__cdecl *)(void*, void*)', 0x7ECE20)
    local findChunk = ffi.cast('int (__cdecl *)(void*, unsigned int, void*, void*)', 0x7ED2D0)
    local readClump = ffi.cast('void* (__cdecl *)(void*)', 0x74B420)
    local addTxd = ffi.cast('int (__cdecl *)(const char*)', 0x731C80)
    local loadTxd = ffi.cast('bool (__cdecl *)(int, const char*)', 0x7320B0)
    local pushTxd = ffi.cast('void (__cdecl *)()', 0x7316A0)
    local popTxd = ffi.cast('void (__cdecl *)()', 0x7316B0)
    local currentTxd = ffi.cast('void (__cdecl *)(int)', 0x7319C0)
    local txdAddRef = ffi.cast('void* (__cdecl *)(int)', 0x731A00)
    local modelInfos = ffi.cast('void**', 0xA9B0C8)
    local templates,privateInfos={},{}
    local checked = false
    local backend = {}
    local function native(signature,address)return ffi.cast(signature,address)end
    local setGeometry=native('void* (__cdecl *)(void*,void*,unsigned int)',0x749D40)
    local setHierarchy=native('void* (__cdecl *)(void*,void*)',0x7C7520)
    local getHierarchy=native('void* (__cdecl *)(void*)',0x7C7540)
    local getSkin=native('void* (__cdecl *)(void*)',0x7C7550)
    local numBones=native('unsigned int (__cdecl *)(void*)',0x7C77E0)
    local destroyGeometry=native('int (__cdecl *)(void*)',0x74CCC0)
    local guard=dofile(directory..'\\memory_guard.lua').new()
    local swap=dofile(directory..'\\geometry_swap.lua').new({
        setGeometry=function(a,g,f)return setGeometry(ptr(a),ptr(g),f)end,
        setHierarchy=function(a,h)return setHierarchy(ptr(a),ptr(h))end,
        getHierarchy=function(a)return getHierarchy(ptr(a))end,
        getSkin=function(g)return getSkin(ptr(g))end,
        numBones=function(s)return numBones(ptr(s))end,
        destroyGeometry=function(g)return destroyGeometry(ptr(g))end},guard)

    local function checkBuild()
        if checked then return end
        for address, expected in pairs(signatures) do
            local actual = hex(ffi.string(ffi.cast('const char*', address), #expected / 2))
            assert(actual == expected,
                string.format('Unsupported GTA build or modified function at 0x%X. No model changed.', address))
        end
        checked = true
    end


    local function resolve(key)
        if not isSampAvailable() or sampGetGamestate()~=3 then return {ready=false} end
        local row=lookup(key)
        if not row or row.server~=currentServer() then return {ready=false} end
        -- The local actor is not guaranteed to appear in the remote player pool.
        -- Re-resolve self before checking the remote connection flag.
        local localIdOk,localId=false,nil
        if sampIsLocalPlayerSpawned() and doesCharExist(PLAYER_PED) then localIdOk,localId=sampGetPlayerIdByCharHandle(PLAYER_PED) end
        local isLocal=localIdOk and row.id==localId
        if not isLocal and not sampIsPlayerConnected(row.id) then return {ready=false} end
        if sampGetPlayerNickname(row.id):lower()~=key then return {ready=false} end
        local streamed,char
        if isLocal then streamed,char=true,PLAYER_PED
        else streamed,char=sampGetCharHandleBySampPlayerId(row.id)end
        if not streamed or not char or not doesCharExist(char) then return {ready=false} end
        local ped=getCharPointer(char);if not ped or ped==0 then return {ready=false} end
        if not guard(ped,0x1c,false)then return {ready=false}end
        local clump=number(pointerAt(ped,0x18)[0]);if clump==0 then return {ready=false} end
        local model=getCharModel(char)
        local unsupported=model<1 or model>311 or model==74
        return {ready=true,ped=ped,clump=clump,model=model,playerId=row.id,
            server=row.server,nickname=row.nickname,
            blocked=unsupported,isLocal=isLocal,
            safe=not isCharDead(char)}
    end
    function backend.state(key)
        local s=resolve(key);swap:collect(key,s);return s
    end
    function backend.sweep()for _,key in ipairs(swap:keys())do backend.state(key)end end
    function backend.owns(key,s,asset)return swap:owns(key,s,asset)end
    function backend.prepare(asset)
        local entry=Settings.models[asset];assert(entry,'Unsupported custom model: '..tostring(asset))
        if templates[asset] then return end
        checkBuild()
        local dff=directory..'\\'..entry.dff;local txd=directory..'\\'..entry.txd
        assert(fileExists(dff) and fileExists(txd),'Missing files for custom model '..asset)
        requestModel(entry.base);loadAllModelsNow()
        local baseInfo=modelInfos[entry.base]
        assert(baseInfo~=nil and pointerAt(baseInfo,0x1C)[0]~=nil,'Base skin not loaded: '..entry.base)
        local txdId=addTxd(entry.dictionary)
        assert(txdId>=0 and loadTxd(txdId,txd),'Could not load '..entry.txd)
        txdAddRef(txdId);pushTxd();currentTxd(txdId)
        local stream=streamOpen(2,1,dff)
        if stream==nil then popTxd();error('Could not open '..entry.dff) end
        local found=findChunk(stream,0x10,nil,nil)~=0;local clump=found and readClump(stream) or nil
        streamClose(stream,nil);popTxd();assert(clump~=nil,'No readable character clump: '..entry.dff)
        ffi.cdef 'void* malloc(size_t size);'
        local info=ptr(ffi.load('msvcrt').malloc(0x44));assert(info~=nil,'Model metadata allocation failed')
        ffi.copy(info,baseInfo,0x44);pointerAt(info,0x1C)[0]=nil;ffi.cast('int16_t*',info+0xA)[0]=txdId
        setClump(info,clump);privateInfos[asset]=info;templates[asset]=clump
    end
    function backend.replace(custom,key,expected,asset)
        checkBuild()
        -- Resolve the name again immediately before any pointer transaction.
        local s=backend.state(key)
        if not s.ready or not s.safe or (custom and s.blocked) or s.ped~=expected.ped
            or s.clump~=expected.clump or s.model~=expected.model
            or s.playerId~=expected.playerId or s.server~=expected.server then return nil end
        local entry=custom and Settings.models[asset] or nil
        if custom and (not entry or (entry.localOnly and not s.isLocal)
            or (entry.serverModel and entry.serverModel~=s.model)) then return nil end
        local template=custom and templates[asset] or nil
        assert(not custom or template~=nil,'Custom template not prepared')
        if custom then return swap:apply(key,s,number(template),asset)end
        return swap:restore(key,s)
    end
    -- Early native creation hooks stay disabled; replacement uses the existing live renderer.
    function backend.withCreationTemplate()return false end
    return backend
end
return M
