-- MEMORY_BASIC_INFORMATION is exactly seven DWORDs in this 32-bit process.
local ffi=require'ffi'
local bit=require'bit'
local M={}
function M.new()
    assert(ffi.abi('32bit'),'MilitarySkins requires a 32-bit process')
    ffi.cdef 'unsigned long __stdcall VirtualQuery(const void* address, void* info, unsigned long length);'
    local kernel=ffi.load('kernel32')
    return function(address,length,write)
        if type(address)~='number' or address~=math.floor(address) or address<0x10000
            or type(length)~='number' or length<=0 or address+length>0x100000000 then return false end
        local finish=address+length;local cursor=address
        while cursor<finish do
            local info=ffi.new('uint32_t[7]')
            if kernel.VirtualQuery(ffi.cast('void*',cursor),info,28)~=28 then return false end
            local base,size,state,protect=tonumber(info[0]),tonumber(info[3]),tonumber(info[4]),tonumber(info[5])
            if state~=0x1000 or bit.band(protect,0x100)~=0 or bit.band(protect,1)~=0 then return false end
            local permission=bit.band(protect,0xff)
            if write then
                if permission~=4 and permission~=8 and permission~=0x40 and permission~=0x80 then return false end
            elseif permission~=2 and permission~=4 and permission~=8 and permission~=0x20 and permission~=0x40 and permission~=0x80 then return false end
            if cursor<base or size<=0 or base+size<=cursor then return false end
            cursor=math.min(finish,base+size)
        end
        return true
    end
end
return M
