--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--- gmcphelper.lua
--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
require "serialize"

---------------------------------------------------------------------------------------------------
-- FUNCTION:: gmcp
--   Returns, in DWIM manner, the GMCP data from matching category.
--   Examples: gmcp("room"), gmcp("char.base.tier")
---------------------------------------------------------------------------------------------------
function gmcp(what)
   local ret, datastring = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpdata_as_string", what)
   pcall(loadstring("data = "..datastring))
   return data
end -- gmcp


---------------------------------------------------------------------------------------------------
-- Helper function to send GMCP data.
---------------------------------------------------------------------------------------------------
function Send_GMCP_Packet (what)
   CallPlugin("3e7dedbe37e44942dd46d264", "GMCP_send", what)
end -- Send_GMCP_Packet




-- everything below this point is deprecated --









---------------------------------------------------------------------------------------------------
-- FUNCTION:: get_gmcp
--   Reverse of parse_gmcp - takes a value like "room.info.exits.n" and checks each level for
--   the next table and then for the actual value.
---------------------------------------------------------------------------------------------------
function get_gmcp(fieldname, parent)

   assert (fieldname, "nil fieldname passed to get_gmcp")
   assert (parent, "nil parent passed to get_gmcp")
   assert (type (parent) == "table", "non-table parent value passed to get_gmcp")

   local lastval = get_last_tag(fieldname)

   for item in string.gmatch(fieldname,"%a+") do
      if parent[item] ~= nil then

         if item == lastval then return parent[item] end

         if type(parent[item])  == "table" then
            parent = parent[item]
         else
            return parent[item]
         end
      else
         return "" -- if we asked for something valid, shouldn't get this.
      end
   end -- for item

   return "" -- shouldn't reach here either if we asked for something valid.
end -- function get_gmcp

---------------------------------------------------------------------------------------------------
-- FUNCTION:: get_last_tag
--   Parses inbound string to pull the last of "char.vitals.str" or "room". First is "str",
--   second is just "room". Used to check if we're at the last level when accessing gmcpdata
--   by a keyword.
---------------------------------------------------------------------------------------------------
function get_last_tag(instr)
   return string.match(instr,"^.*%.(%a+)$") or instr
end -- get_last_tag

---------------------------------------------------------------------------------------------------
-- FUNCTION:: gmcpval
--   Return an item from the table. Just a wrapper to serialize a table or return a uniqie
--   value that won't error if a value that doesn't exist is requested.
---------------------------------------------------------------------------------------------------
function gmcpval(fieldname)
   return gmcpsection(fieldname,true)
end

---------------------------------------------------------------------------------------------------
-- FUNCTION:: gmcpitem
--   Version of gmcpval that should never return a table. Considered an error if it does.
---------------------------------------------------------------------------------------------------
function gmcpitem(fieldname)
   return gmcpsection(fieldname,false)
end

---------------------------------------------------------------------------------------------------
-- FUNCTION:: gmcpsection
--   Return an item from the table, may be either a nested table serialized or a single
--   item - depends on the flag. Called by gmcpval (table ok) and gmcpitem (not ok).
---------------------------------------------------------------------------------------------------
function gmcpsection(fieldname,nesting)
   assert (gmcpdata, "No gmcpdata variable set.")
   local outval = get_gmcp(fieldname,gmcpdata)
   if (type(outval) == "table") then
      assert(nesting,"nested table value requested from GMCP. Should be single element.")
      return serialize.save_simple(outval)
   end

   if outval == nil or type(outval) == "string" then
      return outval
   else
      return tostring (outval)
   end
end
