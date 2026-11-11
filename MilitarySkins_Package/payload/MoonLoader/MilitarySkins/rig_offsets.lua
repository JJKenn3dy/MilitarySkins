-- GTA's skinned animation uses absolute clip quaternions and model-specific
-- BonePos translations. Replace only BonePos; keep frame pointers, flags,
-- associations, blend weights, animation time and IK quaternion state intact.
-- Algorithm: RpAnimBlendClumpInitSkinned / SkinGetBonePositionsToTable.
local ffi=require'ffi'
local bit=require'bit'
local M={}
local function ptr(a)return ffi.cast('uint8_t*',a)end
local function u32(a)return tonumber(ffi.cast('uint32_t*',a)[0])end
local function finite(x)return x==x and math.abs(x)<100 end
local function bytes(a,n)return ffi.string(ptr(a),n)end
function M.new(api,guard)
    local self={}
    local function read(a,n,write)assert(a and a>=0x10000 and guard(a,n,write or false),'Invalid animation memory');return a end
    function self:frames(clump,ids)
        local offset=api.blendOffset()
        assert(offset>=0x20 and offset<=0x400 and offset%4==0,'Unsupported animation plugin offset')
        local bd=read(u32(read(clump+offset,4)),20)
        assert(u32(bd+8)==#ids,'Animation frame count does not match skeleton')
        local frames=read(u32(bd+16),#ids*24,true)
        for j,id in ipairs(ids)do
            local fd=frames+(j-1)*24
            assert(u32(fd+20)==id,'Animation bone tag does not match skeleton')
            read(u32(fd+16),36)
        end
        return frames
    end
    function self:positions(skin,flags)
        local matrices=read(tonumber(ffi.cast('uintptr_t',api.skinMatrices(skin))),#flags*64)
        local p=ffi.new('float[?]',#flags*3);local stack={0};local parent=0
        -- Matrices store right/up/at/position as rows, each padded to 16 bytes.
        -- A full affine inverse is used, including non-unit rotations/scales.
        local function invPosition(index)
            local m=ffi.cast('float*',matrices+index*64)
            local a,b,c,d,e,f,g,h,i=m[0],m[1],m[2],m[4],m[5],m[6],m[8],m[9],m[10]
            local det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
            assert(det==det and math.abs(det)>0.01 and math.abs(det)<100,'Invalid skin bind matrix')
            local x,y,z=m[12],m[13],m[14]
            return -(x*(e*i-f*h)+y*(f*g-d*i)+z*(d*h-e*g))/det,
                -(x*(c*h-b*i)+y*(a*i-c*g)+z*(b*g-a*h))/det,
                -(x*(b*f-c*e)+y*(c*d-a*f)+z*(a*e-b*d))/det
        end
        for j=1,#flags-1 do
            local x,y,z=invPosition(j);local m=ffi.cast('float*',matrices+parent*64)
            local v={x*m[0]+y*m[4]+z*m[8]+m[12],x*m[1]+y*m[5]+z*m[9]+m[13],x*m[2]+y*m[6]+z*m[10]+m[14]}
            for k=1,3 do assert(finite(v[k]),'Invalid bone offset');p[j*3+k-1]=v[k]end
            if bit.band(flags[j+1],2)~=0 then stack[#stack+1]=parent end
            if bit.band(flags[j+1],1)~=0 then assert(#stack>0,'Invalid bone parent stack');parent=table.remove(stack)
            else parent=j end
        end
        assert(#stack==0,'Unbalanced skeleton hierarchy')
        return p
    end
    function self:capture(frames,n)
        local saved={}
        for j=0,n-1 do saved[j+1]=bytes(frames+j*24+4,12)end
        return saved
    end
    function self:matches(frames,positions,n)
        for j=0,n-1 do
            if bytes(frames+j*24+4,12)~=bytes(ffi.cast('float*',positions)+j*3,12)then return false end
        end
        return true
    end
    function self:write(frames,positions,n)
        read(frames,n*24,true)
        for j=0,n-1 do ffi.copy(ptr(frames+j*24+4),ffi.cast('float*',positions)+j*3,12)end
    end
    function self:restore(frames,saved)
        read(frames,#saved*24,true)
        for j,value in ipairs(saved)do ffi.copy(ptr(frames+(j-1)*24+4),value,12)end
    end
    return self
end
return M
