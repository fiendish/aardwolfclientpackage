module (..., package.seeall)

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
function PackageVersion()
   local ver = "missing"
   -- borrowed from the package update checker
   local file,err = io.open(version_file, "r")
   if file then -- the file exists
      --- read the snapshot revision from the third line
      line = file:read("*l") -- read one line
      line = file:read("*l") -- read one line
      line = file:read("*l") -- read one line
      file:close()
      if line then -- if we got something
         ver = tonumber(string.match(line, "r(%d+)")) or "modified"
      end
   end
   
   return ver, err
end

function PackageVersionExtended()
   local version, err = PackageVersion()
   local msg = ""
   local succ = false
   if version == "missing" then -- the file is missing or unreadable
      msg = "The file "..version_file.." appears to be missing or unreadable (this is bad), so the version check cannot proceed.\nThe system gave the error: "..err
   elseif version == "modified" then
      msg = "The file "..version_file.." appears to have been modified (this is bad), so the version check cannot proceed."
   else
      succ = true
      msg = "You are currently using Aardwolf MUSHclient Package version: r"..version
   end
   
   return succ, version, msg
end
