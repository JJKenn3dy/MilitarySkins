-- Preserve the LIVE clump, atomic, frame, HAnim hierarchy and animation associations.
-- Geometry and animation BonePos change together, without CPed::SetModelIndex.
local ffi=require'ffi'
local M={}
local function addr(p)return tonumber(ffi.cast('uintptr_t',p))end
local function p32(a)return tonumber(ffi.cast('uint32_t*',a)[0])end
local function i32(a)return tonumber(ffi.cast('int32_t*',a)[0])end
local function same(t,s)
    return s and s.ready and t.ped==s.ped and t.clump==s.clump and t.model==s.model
        and t.playerId==s.playerId and t.server==s.server
end
function M.new(api,guard,rig)
    assert(rig,'Skeleton adaptation is required')
    local records={};local self={}
    local function readable(a,n)assert(guard(a,n,false),'Unreadable RenderWare structure');return a end
    local function atomic(clump)
        readable(clump,16)
        local sentinel=clump+8;local link=p32(sentinel)
        assert(link~=sentinel and link>=0x10040,'Character has no atomic')
        readable(link,8)
        assert(p32(link)==sentinel and p32(link+4)==sentinel and p32(sentinel+4)==link,
            'Only a single skinned atomic is supported')
        local a=readable(link-0x40,0x4c)
        assert(p32(a+0x3c)==clump,'Invalid atomic owner')
        return a,readable(p32(a+0x18),16)
    end
    local function skeleton(a,g)
        local skin=addr(api.getSkin(g));assert(skin~=0,'Character geometry has no skin plugin')
        local n=tonumber(api.numBones(skin));assert(n==32,'Unsupported character bone count')
        local h=addr(api.getHierarchy(a));readable(h,24)
        assert(i32(h+4)==n,'Skin/hierarchy bone count mismatch')
        local nodes=readable(p32(h+16),n*16);local ids,flags={},{}
        for j=0,n-1 do
            assert(i32(nodes+j*16+4)==j,'Unsupported bone matrix order')
            ids[j+1]=i32(nodes+j*16)
            flags[j+1]=i32(nodes+j*16+8)
            assert(flags[j+1]>=0 and flags[j+1]<=3,'Unsupported skeleton traversal')
        end
        return h,table.concat(ids,',')..'/'..table.concat(flags,','),skin,ids,flags
    end
    local function release(t)
        if t and t.original then api.destroyGeometry(t.original);t.original=nil end
    end
    function self:keys()local keys={};for k in pairs(records)do keys[#keys+1]=k end;return keys end
    function self:collect(key,s)
        local t=records[key];if not t then return end
        local live=same(t,s)
        if live then
            local ok,a,g=pcall(atomic,s.clump)
            live=ok and a==t.atomic and g==t.applied
            if live then
                local good,frames=pcall(rig.frames,rig,s.clump,t.ids)
                live=good and frames==t.frames and rig:matches(frames,t.positions,#t.ids)
            end
        end
        if not live then
            -- Only touch a still-owned animation array in a freshly resolved actor.
            -- Streamed-out clumps and recycled addresses are never dereferenced.
            if same(t,s)then
                local ok,frames=pcall(rig.frames,rig,s.clump,t.ids)
                if ok and frames==t.frames and rig:matches(frames,t.positions,#t.ids)then rig:restore(frames,t.saved)end
            end
            records[key]=nil;release(t)
        end
    end
    function self:owns(key,s,asset)
        self:collect(key,s);local t=records[key]
        return t~=nil and t.asset==asset
    end
    function self:apply(key,s,template,asset)
        self:collect(key,s)
        local a,g=atomic(s.clump);local ta,tg=atomic(template)
        local h,order,_,ids=skeleton(a,g);local _,templateOrder,skin,_,flags=skeleton(ta,tg)
        assert(order==templateOrder,'Incompatible skeleton: replacement was not applied')
        local frames=rig:frames(s.clump,ids)
        local positions=rig:positions(skin,flags)
        local t=records[key]
        if t and t.applied==tg then t.asset=asset;return s.clump end
        if not t then
            assert(guard(g+14,2,true),'Geometry reference is not writable')
            local ref=ffi.cast('int16_t*',g+14);assert(ref[0]>0 and ref[0]<32767,'Invalid geometry reference count')
            -- Own an independent reference while the original atomic does not use it.
            ref[0]=ref[0]+1
            t={ped=s.ped,clump=s.clump,model=s.model,playerId=s.playerId,server=s.server,
                atomic=a,original=g,hierarchy=h,applied=g,frames=frames,ids=ids,saved=rig:capture(frames,#ids)}
            records[key]=t
        end
        assert(t.frames==frames,'Animation array changed during replacement')
        -- All validation is complete before this non-yielding RenderWare transaction.
        rig:write(frames,positions,#ids)
        api.setGeometry(a,tg,0)
        api.setHierarchy(a,h)
        t.applied=tg;t.asset=asset;t.positions=positions
        assert(p32(a+0x18)==tg and addr(api.getHierarchy(a))==h,'Geometry swap failed')
        return s.clump
    end
    function self:restore(key,s)
        self:collect(key,s);local t=records[key]
        if not t then return s.clump end
        local a=atomic(s.clump)
        local frames=rig:frames(s.clump,t.ids);assert(frames==t.frames,'Animation array changed before restore')
        rig:restore(frames,t.saved)
        api.setGeometry(a,t.original,0);api.setHierarchy(a,t.hierarchy)
        assert(p32(a+0x18)==t.original,'Original geometry restore failed')
        records[key]=nil;release(t)
        return s.clump
    end
    return self
end
return M
