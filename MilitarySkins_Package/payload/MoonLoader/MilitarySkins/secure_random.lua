local M={}
function M.key()
    local ffi=require'ffi'
    ffi.cdef[[
        unsigned int __stdcall GetSystemDirectoryA(char*,unsigned int);
        long __stdcall BCryptGenRandom(void*,unsigned char*,unsigned long,unsigned long);
    ]]
    local directory=ffi.new('char[260]')
    local size=ffi.C.GetSystemDirectoryA(directory,260)
    assert(size>0 and size<260,'Не удалось открыть системный генератор доступа')
    local bcrypt=ffi.load(ffi.string(directory)..'\\bcrypt.dll')
    local bytes=ffi.new('unsigned char[32]')
    assert(bcrypt.BCryptGenRandom(nil,bytes,32,2)==0,'Не удалось создать защищённый запрос доступа')
    local parts={};for i=0,31 do parts[#parts+1]=string.format('%02x',tonumber(bytes[i]))end
    return 'ms_'..table.concat(parts)
end
return M
