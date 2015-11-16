require "sha1"

function gitsha (filename)   
   function readAll(file)
       local f = io.open(file, "rb")
       if f == nil then
         return ""
       end
       local content = f:read("*all")
       f:close()
       return content
   end
   local filed = readAll(filename)
   return sha1.hash("blob "..#filed.."\0"..filed, true)
end
