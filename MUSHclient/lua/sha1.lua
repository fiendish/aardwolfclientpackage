--[[
   Copyright (C) 2011 Chris Osgood <chris at luadev.com>
   
   Permission is hereby granted, free of charge, to any person obtaining a copy
   of  this  software  and  associated documentation files (the "Software"), to
   deal  in  the Software without restriction, including without limitation the
   rights  to use, copy, modify, merge, publish, distribute, sublicense, and/or
   sell  copies  of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:
  
   The  above  copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.
  
   THE  SOFTWARE  IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED,  INCLUDING  BUT  NOT  LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS  FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS  OR  COPYRIGHT  HOLDERS  BE  LIABLE  FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY,  WHETHER  IN  AN  ACTION  OF CONTRACT, TORT OR OTHERWISE, ARISING
   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
   IN THE SOFTWARE. 
--]]

--[[
   SHA1 module
   
   Notes:
      final() may be called multiple times but only to retrieve the existing
      hash.  No data updates should be performed once the hash is finalized.
   
   Example usage:
      require('sha1')

      -- Short form:
      hash_bytes = sha1.hash('foobar')

      -- Long form:
      hash = sha1.init()
      sha1.update(hash, 'foo')
      sha1.update(hash, 'bar')
      hash_bytes = sha1.final(hash)

--]]

module('sha1', package.seeall)

local ffi = require('ffi')
require('bit')

-- Local versions of bit operations -------------------------------------------

local band, bor, bxor, bnot, rshift, lshift, rol, bswap, tohex =
      bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.lshift, bit.rol,
      bit.bswap, bit.tohex

if ffi.abi('be') then
   bswap = function(n) return n end
end

-- Local utility --------------------------------------------------------------

local uint32_ptr = ffi.typeof('uint32_t*')
local w = ffi.new('uint32_t[80]')

local function nbinary32(n)
   return string.char(band(rshift(n, 24), 0xFF),
                      band(rshift(n, 16), 0xFF),
                      band(rshift(n, 8), 0xFF),
                      band(n, 0xFF))
end

-- Main -----------------------------------------------------------------------

--[[
   @param data Optional data to hash
   @returns Hash object
--]]
function init(data)
   -- Initialize variables
   local hash = {
      0x67452301, -- h0
      0xEFCDAB89, -- h1
      0x98BADCFE, -- h2
      0x10325476, -- h3
      0xC3D2E1F0, -- h4
      0,          -- data length
      '',         -- partial data buffer
      nil         -- flag: hash is finalized
   }

   if data then update(hash, data) end
   return hash
end

--[[
   @param hash Hash object
   @param data Data to hash
   @returns nothing
--]]
function update(hash, data)
   if not data then return end

   hash[6] = hash[6] + #data
   data = hash[7]..data

   -- Process 512-bit chunks
   local steps = math.floor(#data / 64) * 16 - 1
   local pdata = ffi.cast(uint32_ptr, data)

   for pos=0,steps,16 do
      for i=0,15,1 do
         w[i] = bswap(pdata[pos + i])
      end
   
      for i=16,79,1 do
         w[i] = rol(bxor(bxor(bxor(w[i-3], w[i-8]), w[i-14]), w[i-16]), 1)
      end
   
      local a,b,c,d,e = hash[1],hash[2],hash[3],hash[4],hash[5]
      local f,k,temp
   
      -- Main loop
      for i=0,19,1 do
         f, k = bor(band(b, c), band(bnot(b), d)), 0x5A827999
         temp = band(rol(a, 5) + f + e + k + w[i], 0xFFFFFFFF)
         e,d,c,b,a = d,c,rol(b, 30),a,temp
      end
      for i=20,39,1 do
         f, k = bxor(bxor(b, c), d), 0x6ED9EBA1
         temp = band(rol(a, 5) + f + e + k + w[i], 0xFFFFFFFF)
         e,d,c,b,a = d,c,rol(b, 30),a,temp
      end
      for i=40,59,1 do
         f, k = bor(bor(band(b, c), band(b, d)), band(c, d)), 0x8F1BBCDC
         temp = band(rol(a, 5) + f + e + k + w[i], 0xFFFFFFFF)
         e,d,c,b,a = d,c,rol(b, 30),a,temp
      end
      for i=60,79,1 do
         f, k = bxor(bxor(b, c), d), 0xCA62C1D6
         temp = band(rol(a, 5) + f + e + k + w[i], 0xFFFFFFFF)
         e,d,c,b,a = d,c,rol(b, 30),a,temp
      end
   
      hash[1] = band(hash[1] + a, 0xFFFFFFFF)
      hash[2] = band(hash[2] + b, 0xFFFFFFFF)
      hash[3] = band(hash[3] + c, 0xFFFFFFFF)
      hash[4] = band(hash[4] + d, 0xFFFFFFFF)
      hash[5] = band(hash[5] + e, 0xFFFFFFFF)
   end

   hash[7] = data:sub((steps+1) * 4 + 1)
end

--[[
   @param hash Hash object
   @param data Optional data to hash
   @param text Boolean: Return a text string (default returns binary string)
   @returns Hash string (20 binary bytes or 40 text characters)
--]]
function final(hash, data, text)
   if not hash[8] then
      -- Pre-processing
      data = data or ''
      local len = (hash[6] + #data) * 8
   
      -- FIXME: need 64-bit "bit" functions
      len = string.char(band(math.floor(len / 0x100000000000000), 0xFF),
                        band(math.floor(len / 0x1000000000000), 0xFF),
                        band(math.floor(len / 0x10000000000), 0xFF),
                        band(math.floor(len / 0x100000000), 0xFF),
                        band(rshift(len, 24), 0xFF),
                        band(rshift(len, 16), 0xFF),
                        band(rshift(len, 8), 0xFF),
                        band(len, 0xFF))
   
      local pad = 64 - ((hash[6] + 9) % 64)
      if pad == 64 then pad = 0 end
      data = data.."\128"..string.rep("\0", pad)..len
   
      -- Produce the final hash value
      update(hash, data)
      hash[8] = true
   end

   if text then
      return tohex(hash[1])..
             tohex(hash[2])..
             tohex(hash[3])..
             tohex(hash[4])..
             tohex(hash[5])
   else
      return nbinary32(hash[1])..
             nbinary32(hash[2])..
             nbinary32(hash[3])..
             nbinary32(hash[4])..
             nbinary32(hash[5])
   end
end

--[[
   Convenience "all in one" hash function
   @param data Data to hash
   @param text Boolean: Return a text string (default returns binary string)
   @returns Hash string (20 binary bytes or 40 text characters)
--]]
function hash(data, text)
   return final(init(data), nil, text)
end

