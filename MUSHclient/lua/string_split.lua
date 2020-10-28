-- This string.split works like MUSHclient's utils.split, but allows
-- any pattern and also allows you to preserve the pattern match entities.
function string.split(self, pat, add_pattern_matches_to_result, max_matches)
   local fields = {}
   local start = 1
   local match_times = 0
   self:gsub("()("..pat..")",
      function(index,match)
         if max_matches == nil or max_matches > match_times then
            table.insert(fields, self:sub(start,index-1))
            if add_pattern_matches_to_result then
               table.insert(fields, match)
            end
            start = index + #match
            match_times = match_times + 1
         end
      end
   )
   table.insert(fields, self:sub(start))
   return fields
end
