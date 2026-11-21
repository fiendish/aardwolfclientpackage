-- Bounded, world-specific image slots. Metadata commits after the image.
local M = {}

local function read(path)
   local file,message,code=io.open(path,"rb")
   if not file then
      if code==2 then return nil end -- A missing cache is a normal first build.
      error(message,0)
   end
   local contents=assert(file:read("*a"))
   assert(file:close())
   return contents
end

local function remove(path)
   local removed, message, code = os.remove(path)
   if not removed and code ~= 2 then error(message, 0) end
end

function M.capture(sources)
   if not utils or not utils.hash then return nil end -- Host fixtures can have no native hash API.
   local parts={"mapper-image-cache-1",type(Version)=="function" and Version() or ""}
   for _,source in ipairs(sources) do
      if source:sub(1,1)~="@" then return nil end
      local bytes=read(source:sub(2))
      if not bytes then return nil end -- Virtual source names exist in host fixtures.
      parts[#parts+1]=bytes
   end
   return utils.hash(table.concat(parts,"\0"))
end

function M.new(api,check,prefix,version)
   local hash=assert(api.utils.hash,"Mapper image cache requires utils.hash")
   assert(version,"Mapper image cache has no source version")
   local cache={}
   function cache.key(parts)
      -- Keep the fixed-map key format used on disk.
      return hash(version.."\0\0"..table.concat(parts))
   end
   local function paths(slot)
      assert(slot:match("^[%w_]+$"),"Invalid mapper cache slot")
      return prefix.."-"..slot..".png",prefix.."-"..slot..".txt"
   end
   function cache.load(slot,key,image)
      local path,metadata=paths(slot)
      local saved=read(metadata)
      if not saved then return false end
      local old_key,digest,width,height=saved:match("^(%x+)\n(%x+)\n(%d+)\n(%d+)\n$")
      if not old_key then
         api.Note("Mapper image cache metadata is invalid. Rebuilding the image.")
         return false
      end
      if old_key~=key then return false end
      local bytes=read(path)
      if not bytes or hash(bytes)~=digest or tonumber(width)~=image.width or tonumber(height)~=image.height then
         api.Note("Mapper image cache is incomplete. Rebuilding the image.")
         return false
      end
      check(api.WindowLoadImageMemory(image.window,"mapper_disk_cache",bytes))
      assert(api.WindowImageInfo(image.window,"mapper_disk_cache",2)==image.width
         and api.WindowImageInfo(image.window,"mapper_disk_cache",3)==image.height,"Invalid mapper cache dimensions")
      check(api.WindowDrawImage(image.window,"mapper_disk_cache",0,0,0,0,1))
      check(api.WindowLoadImage(image.window,"mapper_disk_cache",""))
      return true
   end
   function cache.save(slot,key,image)
      local path,metadata=paths(slot)
      local temporary=path..".tmp.png"
      check(api.WindowWrite(image.window,temporary))
      local bytes=assert(read(temporary))
      local file=assert(io.open(metadata..".tmp","wb"))
      assert(file:write(key.."\n"..hash(bytes).."\n"..image.width.."\n"..image.height.."\n"))
      assert(file:close())
      -- A stopped write can leave no usable cache, but never a valid stale image.
      remove(path);assert(os.rename(temporary,path))
      remove(metadata);assert(os.rename(metadata..".tmp",metadata))
   end
   return cache
end

return M
