module (..., package.seeall)
require "string_split"

-- Returns an array of {start, end, text}
function findURLs(text)
   local URLs = {}
   local start, position = 0, 0
   -- "rex" is a table supplied by MUSHclient for PCRE functionality.
   local re = rex.new("(?:https?://|mailto:)\\S*[\\w/=@#\\-\\?]")
   re:gmatch(text,
      function (link, _)
         start, position = string.find(text, link, position, true)
         table.insert(URLs, {start=start, stop=position, text=link})
      end
   )
   return URLs
end -- function findURL

version_file = "AardwolfPackageChanges.txt"
git_branch = "MUSHclient"
function PackageVersion()
   local ver = nil
   local file,err = io.open(version_file, "r")
   if file then -- the file exists
      --- read the snapshot revision from the third line
      line = file:read("*l") -- read one line
      line = file:read("*l") -- read one line
      line = file:read("*l") -- read one line
      file:close()
      if line then -- if we got something
         ver = tonumber(string.match(line, "r(%d+)"))
         err = nil
      end
   end

   return ver, err
end

function PackageVersionFull()
   local ver, err = PackageVersion()
   if ver then
      ver = ver..(aard_req_novisuals_mode and "_VI" or "")
   end
   return ver or "ERROR"
end

function PackageVersionExtended()
   local version, err = PackageVersion()
   local msg = ""
   local succ = false
   if not version then -- the file is missing or unreadable
      msg = "The file "..version_file.." appears to be missing or unreadable (this is bad), so the version check cannot proceed."
      if err then
         msg = msg.."\nThe system gave the error: "..err
      end
   else
      succ = true
      msg = "You are using Aardwolf MUSHclient Package version: r"..version..(aard_req_novisuals_mode and "\nIf someone asked you to report your version to them, consider also telling them that it's the no-visuals edition if you think that it might be useful information." or "")
   end

   return succ, version, msg
end

function osexecute(cmd)
   local n = GetInfo(66).."aard_package_temp_file.txt" -- temp file for catching output
   cmd = cmd .. " > \""..n.."\""
   local err = os.execute(cmd)
   local message_accumulator = {}
   -- It's not so simple to catch errors from os.execute, so grab the system output from a catfile
   for line in io.lines (n) do
      table.insert(message_accumulator, line)
   end
   os.remove(n) -- remove temp file
   return err, message_accumulator
end
