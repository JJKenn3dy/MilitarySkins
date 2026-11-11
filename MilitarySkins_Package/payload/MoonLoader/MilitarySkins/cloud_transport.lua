local M={}
function M.new(directory)
    local ffi=require'ffi'
    ffi.cdef[[
        int __cdecl ms_http_start(const char*,const char*,const char*,const char*,const char*);
        int __cdecl ms_http_poll(char*,int,int*,int*);
        int __stdcall GetModuleHandleExA(unsigned long,const char*,void**);
    ]]
    local path=directory..'\\cloud_http.dll'
    local lib=ffi.load(path)
    -- GET_MODULE_HANDLE_EX_FLAG_PIN | FROM_ADDRESS: avoid unloading while native I/O finishes.
    local module=ffi.new('void*[1]')
    assert(ffi.C.GetModuleHandleExA(5,ffi.cast('const char*',lib.ms_http_start),module)~=0,'Cannot pin HTTPS worker')
    local out=ffi.new('char[524289]');local status=ffi.new('int[1]');local err=ffi.new('int[1]')
    return {
        start=function(host,path,method,body,key)return lib.ms_http_start(host,path,method,body or '',key or '')==1 end,
        poll=function()
            local n=lib.ms_http_poll(out,524289,status,err)
            if n>0 then return {status=tonumber(status[0]),error=tonumber(err[0]),body=ffi.string(out,n-1)}end
        end
    }
end
return M
