rex.gsub = function(str, re, rep)
   local output = ""
   local as_func = (type(rep) == "function")
   local startfrom = 1
   local s, e, t = re:match(str, startfrom)
   while s ~= nil do
      local filled_rep
      if as_func then
         local substr = str:sub(s,e)
         if (#t > 0) then
            filled_rep = rep(unpack(t)) or substr
         else
            filled_rep = rep(substr) or substr
         end
      else
         filled_rep = rep:gsub("%%(%d+)", 
            function(index) 
               local i = tonumber(index)*2
               return t[i-1] or ""
            end)
         end
      output = output..str:sub(startfrom, s-1)..filled_rep
      startfrom = e+1
      s, e, t = re:match(str, startfrom)
   end
   return output..str:sub(startfrom)
end

function character_classes(m)
   -- PCRE doesn't allow nested classes, so just remove the separation between internal ones
   m = m:sub(2,-2):gsub("%[",""):gsub("]","")
   -- temporarily bury minus signs inside the class because we need to do something special with the rest in a second
   m = m:gsub("-", "\0")
   return "["..m.."]"
end

function balance_pattern(a, b)
   special_chars = {
      ["."]=true, ["^"]=true, ["$"]=true, ["*"]=true, ["+"]=true, ["-"]=true,
      ["?"]=true, ["("]=true, [")"]=true, ["["]=true, ["]"]=true, ["{"]=true,
      ["}"]=true, ["\\"]=true, ["|"]=true
   }
   if special_chars[a] then
      a = "\\"..a
   end
   if special_chars[b] then
      b = "\\"..b
   end
   return a.."(?:[^"..a..b.."]*(?R)?)*+"..b
end

local class_pattern = balance_pattern("[", "]")

function lua_to_regex(match_str)
   if rex.new("([^%]|^)%f"):exec(match_str) then
      -- we can't handle the frontier pattern yet
      return nil
   end
   meta = {
      {"(["..[[\{\}\|]].."])", [[\%1]]}, -- escape non-Lua special characters
      {"%%", "\0"}, -- temporarily bury literal %
      {"%b%?(.)%?(.)", balance_pattern}, -- Lua's balanced string operator
      {"%a", "[a-zA-Z]"},
      {"%c", "[\x00-\x1F\x7F]"},
      {"%d", "[0-9]"},
      {"%l", "[a-z]"},
      {"%p", "[!\"\\#$%&'()*+,\\-./:;<=>?@\\[\\\\\\]^_{|}~]"},
      {"%s", "[ \\t\\r\\n\\v\\f]"},
      {"%u", "[A-Z]"},
      {"%w", "[a-zA-Z0-9]"},
      {"%x", "[A-Fa-f0-9]"},
      {[[%\\]], [[\]]},
      {"%(.)", [[\%1]]},
      {"\\0", "%"}, -- resurrect literal %
      {class_pattern, character_classes}, -- PCRE doesn't allow nested classes
      {"\\-", "*?"}, -- Lua minus modifier is nongreedy *
      {"\\0", "-"} -- resurrect minus signs from inside classes
   }
   for _, v in ipairs(meta) do
      match_str = rex.gsub(match_str, rex.new(v[1]), v[2])
   end
   return match_str
end
