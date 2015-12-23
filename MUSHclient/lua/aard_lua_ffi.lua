-- This module simplifies (and hopefully makes a bit safer) use of some Win32 APIs 
-- through the LuaJIT FFI library. See http://luajit.org/ext_ffi.html
-- Author: Avi Kelman (Fiendish)
-- 

module (..., package.seeall)

--
-- interface functions:
--

function DeleteFile(pathname, recursive, acceptable_errors)
   acceptable_errors = acceptable_errors or {["2"]=true}
   
   local SHDeleteFlags = ffi.C.FOF_NOCONFIRMATION + ffi.C.FOF_NOERRORUI + ffi.C.FOF_SILENT
   if not recursive then
      SHDeleteFlags = SHDeleteFlags + ffi.C.FOF_NORECURSION
   end
   
   local fos = ffi.new("SHFILEOPSTRUCTA")
   fos.wFunc = "FO_DELETE"
   fos.pFrom = pathname.."\000"
   fos.fFlags = SHDeleteFlags
   return CheckForWinError(SHFileOperationA(fos), acceptable_errors)
end

function CreateDirectory(path_to_create, recursive, acceptable_errors)
   acceptable_errors = acceptable_errors or {["183"]=true}
   
   if recursive then
      return CheckForWinError(SHCreateDirectoryExA(nil, path_to_create, nil), acceptable_errors)
   else
      ffi.C.CreateDirectoryA(path_to_create, nil)
      return CheckForWinError(ffi.C.GetLastError(), acceptable_errors)
   end
end

function MoveFile(src, dest)
   if 0 == ffi.C.MoveFileA(src, dest) then
      return CheckForWinError(ffi.C.GetLastError())
   end
end

--[[
function Copy(source, dest)
    wstring new_sf = source_folder + L"\\*";
    WCHAR sf[MAX_PATH+1];
    WCHAR tf[MAX_PATH+1];

    wcscpy_s(sf, MAX_PATH, new_sf.c_str());
    wcscpy_s(tf, MAX_PATH, target_folder.c_str());

    sf[lstrlenW(sf)+1] = 0;
    tf[lstrlenW(tf)+1] = 0;

    SHFILEOPSTRUCTW s = { 0 };
    s.wFunc = FO_COPY;
    s.pTo = tf;
    s.pFrom = sf;
    s.fFlags = FOF_SILENT | FOF_NOCONFIRMMKDIR | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_NO_UI;
    int res = SHFileOperationW( &s );

    return res == 0;
end
--]]

--
-- ignore everything below this point
--

function CheckForWinError(err, acceptable_errors)
   acceptable_errors = acceptable_errors or {}
   
   if err ~= 0 and not acceptable_errors[tostring(err)] then
      print("")
      
      local str = ffi_charstr(1024)
      local ferr = ffi.C.FormatMessageA(ffi.C.FORMAT_MESSAGE_FROM_SYSTEM + ffi.C.FORMAT_MESSAGE_IGNORE_INSERTS, nil, err, 0, str, 1023, nil)
      if ferr == 0 then
         print("Received Win32 error code:", err, "but encountered another error calling FormatMessage")
         print("Try to see what this code means at:")
         print("    https://msdn.microsoft.com/en-us/library/windows/desktop/ms681381.aspx")
      else
         print("Received Win32 error code:", err, ffi.string(str, numout))
      end
      
      local author = GetPluginInfo(GetPluginID(), 2)
      if author == nil or author == "" then
         author = "Fiendish"
      end
      print("If you think this shouldn't be considered an error, please tell "..author..".")
      
      print(debug.traceback())
      print("")
      return false
   end
   
   return true
end

ffi = require "ffi"

local ffi_charstr = ffi.typeof("char[?]")

ffi.cdef[[
typedef enum {
   FO_MOVE         = 0x0001,
   FO_COPY         = 0x0002,
   FO_DELETE       = 0x0003,
   FO_RENAME       = 0x0004,
   ___size         = 0xFFFFFFFF
} FILEOP_FUNC;

typedef enum {
   FOF_MULTIDESTFILES        = 0x0001,
   FOF_CONFIRMMOUSE          = 0x0002,
   FOF_SILENT                = 0x0004,
   FOF_RENAMEONCOLLISION     = 0x0008,
   FOF_NOCONFIRMATION        = 0x0010,
   FOF_WANTMAPPINGHANDLE     = 0x0020,
   FOF_ALLOWUNDO             = 0x0040,
   FOF_FILESONLY             = 0x0080,
   FOF_SIMPLEPROGRESS        = 0x0100,
   FOF_NOCONFIRMMKDIR        = 0x0200,
   FOF_NOERRORUI             = 0x0400,
   FOF_NOCOPYSECURITYATTRIBS = 0x0800,
   FOF_NORECURSION           = 0x1000
} FILEOP_FLAGS;

typedef bool BOOL;
typedef unsigned long DWORD, *PDWORD, *LPDWORD;
typedef void *PVOID, *LPVOID;
typedef const void *LPCVOID;
typedef PVOID HWND;
typedef char *LPTSTR;
typedef const char *LPCSTR, *LPCTSTR, *PCTSTR, *PCZZTSTR;

typedef struct {
   HWND          hwnd;
   FILEOP_FUNC     wFunc;
   PCZZTSTR        pFrom; // zero zero terminated
   PCZZTSTR        pTo;   // zero zero terminated
   FILEOP_FLAGS    fFlags;
   BOOL            fAnyOperationsAborted;
   LPVOID          hNameMappings;
   PCTSTR          lpszProgressTitle; // only used if FOF_SIMPLEPROGRESS
} SHFILEOPSTRUCTA, *LPSHFILEOPSTRUCTA;

typedef struct _SECURITY_ATTRIBUTES {
  DWORD  nLength;
  LPVOID lpSecurityDescriptor;
  BOOL   bInheritHandle;
} SECURITY_ATTRIBUTES, *PSECURITY_ATTRIBUTES, *LPSECURITY_ATTRIBUTES;

static const int FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000;
static const int FORMAT_MESSAGE_IGNORE_INSERTS = 0x00000200;

int __stdcall SHFileOperationA(LPSHFILEOPSTRUCTA lpFileOp);
int __stdcall SHCreateDirectoryExA(HWND hwnd, LPCTSTR pszPath, const SECURITY_ATTRIBUTES* lpSecurityAttributes); // deprecated api?
BOOL __stdcall CreateDirectoryA(LPCTSTR lpPathName, LPSECURITY_ATTRIBUTES lpSecurityAttributes);
BOOL __stdcall MoveFileA(LPCTSTR lpExistingFileName, LPCTSTR lpNewFileName);

DWORD __stdcall GetLastError(void);
DWORD __stdcall FormatMessageA(DWORD dwFlags, LPCVOID lpSource, DWORD dwMessageId, DWORD dwLanguageId, LPTSTR lpBuffer, DWORD nSize, va_list *Arguments);
]]

SHFileOperationA = ffi.load("Shell32", true).SHFileOperationA
SHCreateDirectoryExA = ffi.load("Shell32", true).SHCreateDirectoryExA  -- deprecated api?
