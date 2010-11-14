-- well-known options


TELOPT_STATMON = 1
TELOPT_BIGMAP = 2
TELOPT_HELPS = 3
TELOPT_MAP = 4
TELOPT_CHANNELS = 5
TELOPT_TELLS = 6
TELOPT_SPELLUP = 7
TELOPT_SKILLGAINS = 8
TELOPT_SAYS = 9
TELOPT_SCORE = 11
TELOPT_ROOM_NAMES = 12
TELOPT_EXIT_NAMES = 14
TELOPT_EDITOR_TAGS = 15
TELOPT_EQUIPMENT = 16
TELOPT_INVENTORY = 17
            
TELOPT_QUIET = 50
TELOPT_AUTOTICK = 51
TELOPT_PROMPT = 52
TELOPT_PAGING = 53
TELOPT_AUTOMAP = 54
TELOPT_SHORTMAP = 55


TELOPT_REQUEST_STATUS = 100



local function TelnetOption (which, on)
  -- Telnet Negotiation Options
  local IAC, SB, SE = 0xFF, 0xFA, 0xF0
  local TELOPT_WILL, TELOPT_WONT, TELOPT_DO, TELOPT_DONT = 0xFB,0xFC, 0xFD, 0xFE       
  
  -- Telnet subnegotiation for Aardwolf
  local AARDWOLF_TELOPT = 102
  
  local TELOPT_ON, TELOPT_OFF = 1, 2  -- turn on or off
  


  if on then
    SendPkt (string.char (IAC, SB, AARDWOLF_TELOPT, which, TELOPT_ON, IAC, SE)) 
  else
    SendPkt (string.char (IAC, SB, AARDWOLF_TELOPT, which, TELOPT_OFF, IAC, SE)) 
  end -- if
  
end -- TelnetOption


function TelnetOptionOn (which)
  TelnetOption (which, true)
end -- TelnetOptionOn


function TelnetOptionOff (which)
  TelnetOption (which, false)
end -- TelnetOptionOff


if GetOption ("enable_triggers") ~= 1 then
  ColourNote ("white", "red", "Warning: Triggers not enabled")
end -- if no triggers


if GetOption ("enable_aliases") ~= 1 then
  ColourNote ("white", "red", "Warning: Aliases not enabled")
end -- if no triggers


if GetOption ("enable_timers") ~= 1 then
  ColourNote ("white", "red", "Warning: Timers not enabled")
end -- if no triggers


