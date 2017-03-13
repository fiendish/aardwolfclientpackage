-- This module simplifies (and hopefully makes a bit safer) use of some Windows APIs
-- through the LuaJIT FFI library. See http://luajit.org/ext_ffi.html
-- Author: Avi Kelman (Fiendish)
--
-- Usage Notes:
--
-->>
-- After doing 'require "aard_lua_ffi"' from a script, you get access to the
-- aard_lua_ffi function namespace which includes a curated and safened set of
-- a few Windows API functions ( https://en.wikipedia.org/wiki/Windows_API ).
--<<
--
-->>
-- See the table at the very end for the list of exported functions
-- and their input arguments.
-- It looks something like:
--
-- --
-- -- export public functions
-- --
-- aard_lua_ffi = {
--    MoveFile = MoveFile, -- (source, destination, acceptable_errors)
--    CreateDirectory = CreateDirectory, -- (path_to_create, recursive, acceptable_errors)
--    DeleteFile = DeleteFile, -- (path_name, recursive, acceptable_errors)
--    ...
-- }
--<<
--
-->>
-- The acceptable_errors input argument on each of the functions is given
-- either nil or a list of Windows error codes that you want to be
-- ignored by the error checker. This will be function-specific, and
-- using it requires knowledge of what error codes might be thrown.
-- See the API call documentation linked in the function comments and also
-- the list of error codes at
-- https://msdn.microsoft.com/en-us/library/windows/desktop/ms681381.aspx
--
-- Some functions will have default reasonable acceptable_errors already set
-- if you pass in nil.
--
-- For instance: CreateDirectory has {183} assigned by default, which
--          ignores the error given if the directory already exists.
--          To re-enable this error you need to pass in either the empty
--          list {} or another list of other error codes, but reasonably
--          you probably don't care if a CreateDirectory attempt technically
--          fails because the directory already exists.
--<<
--
--Example Useage:
-->>
-- require "aard_lua_ffi"
--
-- print("A")
-- if not aard_lua_ffi.CreateDirectory(GetInfo(66).."test\\test", true) then
--    print("Failed A")
-- end
--
-- print("B")
-- if not aard_lua_ffi.CreateDirectory(GetInfo(66).."test\\test", true) then
--    print("Failed B")
-- end
--
-- print("C")
-- if not aard_lua_ffi.CreateDirectory(GetInfo(66).."test\\test", true, {}) then
--    print("Failed C")
-- end
--<<
--This will likely print: "A", "B", "C", an error report that the directory already exists, "Failed C"
--
--


--
-- declarations
--
local ffi_ok, ffi = pcall(require, "ffi")
if not ffi_ok then
   utils.msgbox ( "Your MUSHclient package appears to be missing the LuaJIT FFI extensions.\r\nThis is bad.\r\nMostly this is bad, because one of your plugins wants to use LuaJIT FFI extension capability.\r\n\r\nHow did you get here?\r\n\r\n1) You thought it would be safe to replace your Lua DLLs? It's not.\r\n2) You downloaded an installer from mushclient.com or gammon.com.au and thought it would be safe to install that on top of the Aardwolf MUSHclient Package? It's not.\r\n3) You accidentally something something? Be more careful.\r\n4) File system corruption? Ruh-roh, Shaggy. Time to call tech support.", "Your MUSHclient Install is Broken", "ok", ".")
end

local ffi_charstr = ffi.typeof("char[?]")

ffi.cdef([[
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
BOOL PathCanonicalizeA(LPTSTR lpszDst, LPCTSTR lpszSrc);

DWORD __stdcall GetLastError(void);
DWORD __stdcall FormatMessageA(DWORD dwFlags, LPCVOID lpSource, DWORD dwMessageId, DWORD dwLanguageId, LPTSTR lpBuffer, DWORD nSize, va_list *Arguments);
]])

--
-- connect non-automatic libraries
--

local SHFileOperationA = ffi.load("Shell32").SHFileOperationA
local SHCreateDirectoryExA = ffi.load("Shell32").SHCreateDirectoryExA  -- deprecated api?
local PathCanonicalizeA = ffi.load("shlwapi.dll").PathCanonicalizeA

--------------------------
--------------------------

local function CheckForWinError(err, acceptable_errors)
   acceptable_errors = acceptable_errors or {}

   for i,v in ipairs(acceptable_errors) do
      acceptable_errors[tostring(v)] = true
   end

   if err ~= 0 and not acceptable_errors[tostring(err)] then
      print("")

      local str = ffi_charstr(1024, 0)
      local errlen = ffi.C.FormatMessageA(ffi.C.FORMAT_MESSAGE_FROM_SYSTEM + ffi.C.FORMAT_MESSAGE_IGNORE_INSERTS, nil, err, 0, str, 1023, nil)
      if errlen == 0 then
         ColourNote("yellow", "red", "Received Win32 error code: "..tostring(err).." but encountered another error calling FormatMessageA")
         ColourNote("yellow", "red", "Try to see what this code means at:")
         ColourNote("yellow", "red", "    https://msdn.microsoft.com/en-us/library/windows/desktop/ms681381.aspx")
      else
         ColourNote("yellow", "red", "Received Win32 error code:", err, ffi.string(str, errlen))
      end

      local author = GetPluginInfo(GetPluginID(), 2) -- GetPluginInfo and GetPluginID are a MUSHclient API call
      if author == nil or author == "" then
         author = "Fiendish"
      end
      ColourNote("yellow", "red", "If you think this shouldn't be considered an error, please tell the script author (maybe "..author.."?).")

      ColourNote("yellow", "red", debug.traceback())
      print("")
      return false
   end

   return true
end

local function RestrictPathScope(path)
   local original_path = path

   -- clean up path separators
   path = path:gsub("/","\\")
   repeat
      path, num = path:gsub("\\\\", "\\")
   until num == 0

   local firstchar = string.sub(original_path,1,1)
   if firstchar == "\\" or firstchar == "/" then
      path = "\\"..path -- put UNC code back
   end

   local mushclient_canonical_path = ffi_charstr(1024, 0)
   if not PathCanonicalizeA(mushclient_canonical_path, GetInfo(66)) then -- GetInfo is a MUSHclient API call
      CheckForWinError(ffi.C.GetLastError())
      return false
   end

   local canonical_path = ffi_charstr(1024, 0)
   if not PathCanonicalizeA(canonical_path, path) then
      CheckForWinError(ffi.C.GetLastError())
      return false
   end

   canonical_path = ffi.string(canonical_path)
   if canonical_path:find(ffi.string(mushclient_canonical_path), nil, true) ~= 1 then
      ColourNote("yellow", "red", "ERROR: A script just tried to operate on a file outside of your MUSHclient directory.")
      ColourNote("yellow", "red", "The action has been prevented.")
      ColourNote("yellow", "red", "Details:")
      ColourNote("yellow", "red", "-------------------------------------------------------")
      ColourNote("yellow", "red", "Attempted File Path:  "..original_path)
      ColourNote("yellow", "red", "MUSHclient Directory: "..GetInfo(66))  -- GetInfo is a MUSHclient API call
      plugin_id = GetPluginID()  -- GetPluginID is a MUSHclient API call
      if plugin_id ~= "" then
         ColourNote("yellow", "red", "Plugin ID:   "..plugin_id)
         ColourNote("yellow", "red", "Plugin Name: "..GetPluginInfo(plugin_id, 1))  -- GetPluginInfo is a MUSHclient API call
         ColourNote("yellow", "red", "Plugin File: "..GetPluginInfo(plugin_id, 6))  -- GetPluginInfo is a MUSHclient API call
      end
      ColourNote("yellow", "red", debug.traceback())
      print("")
      return false
   end

   return true, canonical_path
end

--
-- public interface functions:
--

-- wraps SHFileOperationA using SHFILEOPSTRUCTA.wFunc=FO_DELETE
-- https://msdn.microsoft.com/en-us/library/windows/desktop/bb762164.aspx
-- https://msdn.microsoft.com/en-us/library/windows/desktop/bb759795.aspx
local function DeleteFile(pathname, recursive, acceptable_errors)
   succ, pathname = RestrictPathScope(pathname)
   if not succ then
      return false
   end

   acceptable_errors = acceptable_errors or {2, 1026} -- already gone

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

-- wraps SHCreateDirectoryExA if recursive
-- wraps CreateDirectoryA if not
-- https://msdn.microsoft.com/en-us/library/windows/desktop/bb762131.aspx
-- https://msdn.microsoft.com/en-us/library/windows/desktop/aa363855.aspx
local function CreateDirectory(path_to_create, recursive, acceptable_errors)
   succ, path_to_create = RestrictPathScope(path_to_create)
   if not succ then
      return false
   end

   acceptable_errors = acceptable_errors or {183} -- already exists

   if recursive then
      return CheckForWinError(SHCreateDirectoryExA(nil, path_to_create, nil), acceptable_errors)
   else
      ffi.C.CreateDirectoryA(path_to_create, nil)
      return CheckForWinError(ffi.C.GetLastError(), acceptable_errors)
   end
end

-- wraps MoveFileA
-- https://msdn.microsoft.com/en-us/library/windows/desktop/aa365239.aspx
local function MoveFile(src, dest, acceptable_errors)
   acceptable_errors = acceptable_errors or {}

   succ, src = RestrictPathScope(src)
   if not succ then
      return false
   end

   succ, dest = RestrictPathScope(dest)
   if not succ then
      return false
   end

   if 0 == ffi.C.MoveFileA(src, dest) then
      return CheckForWinError(ffi.C.GetLastError(), acceptable_errors)
   end
end

--
-- export public functions
--

aard_lua_ffi = {
   MoveFile = MoveFile, -- (source, destination, acceptable_errors)
   CreateDirectory = CreateDirectory, -- (path_to_create, recursive, acceptable_errors)
   DeleteFile = DeleteFile, -- (path_name, recursive, acceptable_errors)
   RestrictPathScope = RestrictPathScope
}

