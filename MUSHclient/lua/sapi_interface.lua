--[[
Microsoft Speech API interface for Lua
copyright 2016 by Avital Kelman (Fiendish)
https://github.com/fiendish/MS_Speech_API_Lua

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

Depends on LuaCOM ( http://luaforge.net/projects/luacom/ )

Idea descends originally from a basic MUSHclient plugin by Tyler Spivey and Nick Gammon
See: https://www.mushclient.com/forum/bbshowpost.php?bbsubject_id=7767
See: https://github.com/nickgammon/mushclient/commits/master/plugins/Text_To_Speech.xml
--]]

require "luacom"

-- Instantiate a SAPI voice obejct
local engine = luacom.CreateObject("SAPI.SpVoice")

if not engine then
   return -1
end

local NUM_SAPI_VOICES = engine:GetVoices().Count

if NUM_SAPI_VOICES == 0 then
   return -2
end

local SAPI_ENUMS = luacom.GetTypeInfo(engine):GetTypeLib():ExportEnumerations()

local filter_descs = {
  "Say all punctuation.",
  "Say only non-standard punctuation.",
  "Extra filtering to mask symbols and other garbage."
}

local current_voice_index = 0
local current_voice = engine:setVoice(engine:GetVoices():Item(current_voice_index))
local filtering_level = 3
local muted = false
local print_spoken_lines = false

local replacements = { -- arbitrary text filtering heuristics
   {"[:]%-?[D%)%]]", ", smiley. "}, -- western emoticons
   {"[:;]%-?[%(%[]", ", sad-face. "}, -- western emoticons
   {";%-?[D%)%]]", ", winks. "}, -- western emoticons
   {"[:;]%-?[pP9b]", " sticks-tongue-out. "}, -- western emoticons
   {"8%-[D%)%]]", ", smiley. "}, -- 8- western emoticons
   {"8%-[%(%[]", ", sad-face. "}, -- 8- western emoticons
   {"8%-[pP9b]]", ", sticks-tongue-out. "}, -- 8- western emoticons
   {"%^_%^", ", smiley. "}, -- another emoticon
   {"%-_%-", ", sad-face. "}, -- another emoticon
   {string.rep("[%p\\/|_%-%(%)%[%]%{%}%%%+%^%#%$~><%*`_]", 3).."+", " "}, -- symbol garbage
   {string.rep("[%-%+%^=#$~><%*`_:]", 2).."+", " "}, -- symbol garbage
   {"|", " "}, -- symbol garbage
   -- fix contextual pronunciation
   {"[pP]lugin", "pluggin"}, -- plug, not pluge
   {"([%[%(%{])", " %1"}, -- "()()"
   {"([%]%}%)])", "%1 "}, -- "()()"
   {"(%d)%*(%d)", "%1 times %2"}, -- "*"
   {"([%d,]+%.?[%d]*)%/(%a)", "%1 per %2"}, -- "#/a"
   {"%f[%a][dD][bB]", ", D B, "}, -- stop saying decibels
   {"%f[%a]afk%f[%A]", " AFK "}, -- spell it
   {"%f[%a]omg%f[%A]", " OMG "}, -- spell it
   {"%f[%a][vV][iI]%f[%A]", " V I "}, -- spell it
   {"%f[%a]pwned", " p'owned "}, -- say it
   {"thx", " thanks "}, -- say it
   {"%f[%a]%u+%f[%A]", function(a) if a:sub(2):find("[AEIOUY]") then return string.lower(a) else return a end end} -- say GLACIATES and ROFL, but still spell AFK and OMG
}


local function custom_filter (msg) -- uses arbitrary heuristics
   for i,sub in ipairs(replacements) do
      msg = msg:gsub(sub[1], sub[2])
   end
   if msg:gsub("[%p%s]+", "") == "" then
      return ""
   else
      return msg
   end
end


local function get_voice_id ()
   return engine:GetVoices():Item(current_voice_index).ID
end


local function get_rate ()
   return engine.Rate
end


local function get_filtering_level ()
   return filtering_level
end


local function print_spoken ()
   print_spoken_lines = not print_spoken_lines
end


local function say (what)
   if not engine then
      return false
   end
   
   if not muted then
      if print_spoken_lines then
         local prev_muted = muted
         muted = true
         print(what)
         muted = prev_muted
      end
   
      if filtering_level == 1 then
         engine:Speak(what, SAPI_ENUMS.SpeechVoiceSpeakFlags.SVSFlagsAsync + SAPI_ENUMS.SpeechVoiceSpeakFlags.SVSFNLPSpeakPunc)
      elseif filtering_level == 2 then
         engine:Speak(what, SAPI_ENUMS.SpeechVoiceSpeakFlags.SVSFlagsAsync)
      else
         local cleaned_speech = custom_filter(what)
         if cleaned_speech ~= "" then
            engine:Speak(cleaned_speech, SAPI_ENUMS.SpeechVoiceSpeakFlags.SVSFlagsAsync)
         end
      end
   end
   
   return true
end


local function list_filtering_levels ()
   say("Filtering level options are:")
   for i,v in ipairs(filter_descs) do
      say("Level "..tostring(i)..": "..v) 
   end
   say("Level "..tostring(#filter_descs).." is recommended.")
end

local function list_voices ()
   local enumerate_voices = luacom.GetEnumerator(engine:GetVoices())
   local voice = enumerate_voices:Next()
   local i = 0
   while voice do
      if voice.ID ~= "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech\\Voices\\Tokens\\SampleTTSVoice" then
         engine:setVoice(voice)
         say("Voice number "..tostring(i+1).." is "..voice:GetDescription())
      end
      i = i + 1
      voice = enumerate_voices:Next()
   end
   engine:setVoice(engine:GetVoices():Item(current_voice_index))
end


local function say_current_voice ()
   say("Voice is "..tostring(current_voice_index+1)..", "..engine.Voice:GetDescription()..".")
end


local function say_current_rate ()
   say("Speech rate is " .. tostring(engine.Rate)..".")
end


local function say_current_filtering_level ()
   say("Filtering level is "..tostring(filtering_level)..". "..filter_descs[filtering_level])
end


local function speech_demo ()
   say("SAPI speech settings:")
   say_current_voice()
   say_current_rate()
   say_current_filtering_level()
end


local function set_filtering_level (level, quietly)
   level = tonumber(level)
   if (level == nil) or (level < 1) or (level > #filter_descs) then
      if not quietly then
         say("SAPI filtering level must be a number between 1 and "..tostring(#filter_descs)..".")
         list_filtering_levels()
      end
   else
      filtering_level = level
      if not quietly then
         say_current_filtering_level()
      end
   end
   return get_filtering_level()
end


local function skip_sentence ()
   if (engine.Status.RunningState == SAPI_ENUMS.SpeechRunState.SRSEIsSpeaking) then
      engine:Skip("Sentence", 1)
   end
end


local function skip_all ()
   if (engine.Status.RunningState == SAPI_ENUMS.SpeechRunState.SRSEIsSpeaking) then
      engine:Speak(' ', SAPI_ENUMS.SpeechVoiceSpeakFlags.SVSFPurgeBeforeSpeak)
   end
end


local function unmute (quietly)
   muted = false
   if not quietly then
      say("SAPI speech on.")
   end
end


local function mute (quietly)
   if not quietly then
      say("SAPI speech off.")
   end
   muted = true
   skip_all()
end


local function faster (quietly)
   engine.Rate = engine.Rate + 1
   if not quietly then
      say_current_rate()
   end
   return get_rate()
end


local function slower (quietly)
   engine.Rate = engine.Rate - 1
   if not quietly then
      say_current_rate()
   end
   return get_rate()
end


local function set_rate (rate, quietly)
   local rate = tonumber(rate)
   if rate then
      engine.Rate = rate
      if not quietly then
         say_current_rate()
      end
   else
      if not quietly then
         say("SAPI speech rate must be a number.")
      end
   end
   return get_rate()
end


local function set_voice_by_id (voice_id, quietly)
   local enumerate_voices = luacom.GetEnumerator(engine:GetVoices())
   local voice = enumerate_voices:Next()
   local i = 0
   local found = false
   while voice do
      if voice.ID == voice_id then
         found = true
         break
      end
      i = i + 1
      voice = enumerate_voices:Next()
   end
   
   if found then
      current_voice_index = i
      engine:setVoice(voice)
      if not quietly then
         say_current_voice()
      end
   else
      if not quietly then
         say("Voice "..voice_id.." not found.")
         list_voices()
      end
   end
   return current_voice_index, get_voice_id()
end


local function set_voice_by_number (voice_number, quietly)
   local voice_number = tonumber(voice_number)
   if (voice_number ~= nil) and (voice_number >= 1) and (voice_number <= NUM_SAPI_VOICES) and (engine:GetVoices():Item(voice_number-1).ID ~= "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech\\Voices\\Tokens\\SampleTTSVoice") then
      current_voice_index = voice_number-1
      engine:setVoice(engine:GetVoices():Item(current_voice_index))
      if not quietly then
         say_current_voice()
      end
   else
      if not quietly then
         say(tostring(voice_number).." is not a valid SAPI voice number.")
         list_voices()
      end
   end
   return current_voice_index, get_voice_id()
end


return {
   say = say,
   skip_sentence = skip_sentence,
   skip_all = skip_all,
   set_voice_by_number = set_voice_by_number,
   set_voice_by_id = set_voice_by_id,
   set_rate = set_rate,
   slower = slower,
   faster = faster,
   set_filtering_level = set_filtering_level,
   get_voice_id = get_voice_id,
   get_rate = get_rate,
   get_filtering_level = get_filtering_level,
   say_current_voice = say_current_voice,
   say_current_rate = say_current_rate,
   say_current_filtering_level = say_current_filtering_level,
   list_voices = list_voices,
   list_filtering_levels = list_filtering_levels,
   mute = mute,
   unmute = unmute,
   speech_demo = speech_demo,
   replacements = replacements,
   print_spoken = print_spoken -- for debugging
}

