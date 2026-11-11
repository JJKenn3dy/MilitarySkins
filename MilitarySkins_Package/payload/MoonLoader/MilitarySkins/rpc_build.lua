-- SA-MP 0.3.7-R3-1 native handlers, verified against C:\game\samp.dll.
-- The SEH address in each prologue is relocated with samp.dll's load base.
local ffi=require 'ffi'
local M={}
function M.validator()
    ffi.cdef 'void* __stdcall GetModuleHandleA(const char* moduleName);'
    local base=tonumber(ffi.cast('uintptr_t',ffi.load('kernel32').GetModuleHandleA('samp.dll')))
    if not base or base==0 then return function()return false end end
    local specs={[32]={0x107D0,0xE118B},[153]={0x18AA0,0xE16AB}}
    local function le(n)local t={};for i=1,4 do t[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(t)end
    return function(id,address)
        local spec=specs[id]
        if not spec or address~=base+spec[1] then return false end
        local expected=string.char(0x6a,0xff,0x68)..le(base+spec[2])..string.char(0x64,0xa1,0,0,0,0,0x50,0x64,0x89)
        return ffi.string(ffi.cast('const char*',address),#expected)==expected
    end
end
return M
