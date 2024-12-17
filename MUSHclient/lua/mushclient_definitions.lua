-- Generated automatically by https://github.com/aardorphean/mushclient-client-declarations
-- Orphean@Aardwolf to blame.

---@meta

---Add or modify an accelerator key (keystroke to command mapping)
---@param Key string
---@param Send string
---@return number
function Accelerator(Key, Send) end

---List defined accelerators
---@return boolean
---@return string
---@return number
---@return nil
function AcceleratorList() end

---Add or modify an accelerator key - with "Send To" parameter
---@param Key string
---@param Send string
---@param SendTo number
---@return number
function AcceleratorTo(Key, Send, SendTo) end

---Activates the world window
---@return nil
function Activate() end

---Activates the main MUSHclient window
---@return nil
function ActivateClient() end

---Activates a notepad window
---@param Title string
---@return boolean
function ActivateNotepad(Title) end

---Adds an alias
---@param AliasName string
---@param MatchText string
---@param ResponseText string
---@param Flags number
---@param ScriptName string
---@return number
function AddAlias(AliasName, MatchText, ResponseText, Flags, ScriptName) end

---Adds a custom font for use by MUSHclient
---@param PathName string
---@return number
function AddFont(PathName) end

---Adds a comment to the auto-map sequence
---@param Comment string
---@return number
function AddMapperComment(Comment) end

---Adds a word to the user spell check dictionary
---@param OriginalWord string
---@param ActionCode string
---@param ReplacementWord string
---@return number
function AddSpellCheckWord(OriginalWord, ActionCode, ReplacementWord) end

---Adds a timer
---@param TimerName string
---@param Hour number
---@param Minute number
---@param Second nil
---@param ResponseText string
---@param Flags number
---@param ScriptName string
---@return number
function AddTimer(TimerName, Hour, Minute, Second, ResponseText, Flags, ScriptName) end

---Adds a mapping direction to the auto-map sequence
---@param Direction string
---@param Reverse string
---@return number
function AddToMapper(Direction, Reverse) end

---Adds a trigger
---@param TriggerName string
---@param MatchText string
---@param ResponseText string
---@param Flags number
---@param Colour number
---@param Wildcard number
---@param SoundFileName string
---@param ScriptName string
---@return number
function AddTrigger(TriggerName, MatchText, ResponseText, Flags, Colour, Wildcard, SoundFileName, ScriptName) end

---Adds a trigger - extended arguments
---@param TriggerName string
---@param MatchText string
---@param ResponseText string
---@param Flags number
---@param Colour number
---@param Wildcard number
---@param SoundFileName string
---@param ScriptName string
---@param SendTo number
---@param Sequence number
---@return number
function AddTriggerEx(TriggerName, MatchText, ResponseText, Flags, Colour, Wildcard, SoundFileName, ScriptName, SendTo, Sequence) end

---Adjust an RGB colour
---@param Colour number
---@param Method number
---@return number
function AdjustColour(Colour, Method) end

---Generates an ANSI colour sequence
---@param Code number
---@return string
function ANSI(Code) end

---Make a note in the output window from text with ANSI colour codes imbedded
---@param Text string
---@return nil
function AnsiNote(Text) end

---Appends text to a notepad window
---@param Title string
---@param Contents string
---@return boolean
function AppendToNotepad(Title, Contents) end

---Clears an array
---@param Name string
---@return number
function ArrayClear(Name) end

---Returns the number of arrays
---@return number
function ArrayCount() end

---Creates an array
---@param Name string
---@return number
function ArrayCreate(Name) end

---Deletes an array
---@param Name string
---@return number
function ArrayDelete(Name) end

---Deletes a key/value pair from an array
---@param Name string
---@param Key string
---@return number
function ArrayDeleteKey(Name, Key) end

---Tests to see if the specified array exists
---@param Name string
---@return boolean
function ArrayExists(Name) end

---Exports values from an array into a single string
---@param Name string
---@param Delimiter string
---@return boolean
---@return string
---@return number
---@return nil
function ArrayExport(Name, Delimiter) end

---Exports keys from an array into a single string
---@param Name string
---@param Delimiter string
---@return boolean
---@return string
---@return number
---@return nil
function ArrayExportKeys(Name, Delimiter) end

---Gets the value of an array item
---@param Name string
---@param Key string
---@return boolean
---@return string
---@return number
---@return nil
function ArrayGet(Name, Key) end

---Gets the key of the first element in the array (if any)
---@param Name string
---@return boolean
---@return string
---@return number
---@return nil
function ArrayGetFirstKey(Name) end

---Gets the key of the last element in the array (if any)
---@param Name string
---@return boolean
---@return string
---@return number
---@return nil
function ArrayGetLastKey(Name) end

---Imports values into an array from a single string
---@param Name string
---@param Values string
---@param Delimiter string
---@return number
function ArrayImport(Name, Values, Delimiter) end

---Tests to see if the specified array key exists
---@param Name string
---@param Key string
---@return boolean
function ArrayKeyExists(Name, Key) end

---Gets the list of arrays
---@return boolean
---@return string
---@return number
---@return nil
function ArrayListAll() end

---Gets the list of all the keys in an array
---@param Name string
---@return boolean
---@return string
---@return number
---@return nil
function ArrayListKeys(Name) end

---Gets the list of all the values in an array
---@param Name string
---@return boolean
---@return string
---@return number
---@return nil
function ArrayListValues(Name) end

---Sets the value of an array item
---@param Name string
---@param Key string
---@param Value string
---@return number
function ArraySet(Name, Key, Value) end

---Returns the number of elements in a specified array
---@param Name string
---@return number
function ArraySize(Name) end

---Takes a base-64 encoded string and decodes it.
---@param Text string
---@return boolean
---@return string
---@return number
---@return nil
function Base64Decode(Text) end

---Encodes a string using base-64 encoding.
---@param Text string
---@param MultiLine boolean
---@return boolean
---@return string
---@return number
---@return nil
function Base64Encode(Text, MultiLine) end

---Blends a single pixel with another, using a specified blending mode
---@param Blend number
---@param Base number
---@param Mode number
---@param Opacity nil
---@return number
function BlendPixel(Blend, Base, Mode, Opacity) end

---Gets/sets the RGB colour for one of the 8 ANSI bold colours
---@return number
BoldColour = nil

---Sets of clears a bookmark on the nominated line
---@param LineNumber number
---@param Set boolean
---@return nil
function Bookmark(LineNumber, Set) end

---Broadcasts a message to all installed plugins
---@param Message number
---@param Text string
---@return number
function BroadcastPlugin(Message, Text) end

---Calls a routine in a plugin
---@param PluginID string
---@param Routine string
---@param Argument string
---@return number
function CallPlugin(PluginID, Routine, Argument) end

---Changes the MUSHclient working directory
---@param Path string
---@return number
function ChangeDir(Path) end

---Accepts incoming chat calls
---@param Port number
---@return number
function ChatAcceptCalls(Port) end

---Calls a chat server (makes an outgoing call) using the MudMaster chat protocol
---@param Server string
---@param Port number
---@return number
function ChatCall(Server, Port) end

---Calls a zChat chat server (makes an outgoing call)
---@param Server string
---@param Port number
---@return number
function ChatCallzChat(Server, Port) end

---Disconnects a current chat call
---@param ID number
---@return number
function ChatDisconnect(ID) end

---Disconnects all current chat calls
---@return number
function ChatDisconnectAll() end

---Sends a chat message to every connected chat user
---@param Message string
---@param Emote boolean
---@return number
function ChatEverybody(Message, Emote) end

---Looks up what chat ID (identifier) corresponds to a particular chat name
---@param Who string
---@return number
function ChatGetID(Who) end

---Sends a chat message to every connected chat user in the specified group
---@param Group string
---@param Message string
---@param Emote boolean
---@return number
function ChatGroup(Group, Message, Emote) end

---Sends a chat message to a particular chat session
---@param ID number
---@param Message string
---@param Emote boolean
---@return number
function ChatID(ID, Message, Emote) end

---Sends a message to a chat user (raw format)
---@param ID number
---@param Message number
---@param Text string
---@return number
function ChatMessage(ID, Message, Text) end

---Changes your chat name
---@param NewName string
---@return number
function ChatNameChange(NewName) end

---Does a note using ANSI codes for the chat system
---@param NoteType number
---@param Message string
---@return nil
function ChatNote(NoteType, Message) end

---Pastes the clipboard contents to every connected person
---@return number
function ChatPasteEverybody() end

---Pastes the clipboard contents to that person
---@param ID number
---@return number
function ChatPasteText(ID) end

---Sends a "peek connections" message to the specified chat user
---@param ID number
---@return number
function ChatPeekConnections(ID) end

---Sends a chat message to a particular person
---@param Who string
---@param Message string
---@param Emote boolean
---@return number
function ChatPersonal(Who, Message, Emote) end

---Sends a ping message to the specified chat user
---@param ID number
---@return number
function ChatPing(ID) end

---Sends a "request connections" message to the specified chat user
---@param ID number
---@return number
function ChatRequestConnections(ID) end

---Starts sending a file to the specified chat user
---@param ID number
---@param FileName string
---@return number
function ChatSendFile(ID, FileName) end

---Stops this world from accepting chat calls
---@return nil
function ChatStopAcceptingCalls() end

---Stops a file transfer in progress to that chat user
---@param ID number
---@return number
function ChatStopFileTransfer(ID) end

---Closes the log file
---@return number
function CloseLog() end

---Closes a notepad window
---@param Title string
---@param QuerySave boolean
---@return number
function CloseNotepad(Title, QuerySave) end

---Converts a named colour to a RGB colour code.
---@param Name string
---@return number
function ColourNameToRGB(Name) end

---Sends a message to the output window in specified colours
---@param TextColour string
---@param BackgroundColour string
---@param Text string
---@return nil
function ColourNote(TextColour, BackgroundColour, Text) end

---Sends a message to the output window in specified colours - not terminated by a newline
---@param TextColour string
---@param BackgroundColour string
---@param Text string
---@return nil
function ColourTell(TextColour, BackgroundColour, Text) end

---Connects the world to the MUD server
---@return number
function Connect() end

---Creates a GUID - Global Unique Identifier
---@return string
function CreateGUID() end

---Sets the RGB value for the background of a custom colour
---@return number
CustomColourBackground = nil

---Sets the RGB value for the text of a custom colour
---@return number
CustomColourText = nil

---Returns a count of the changes to the database by the most recent SQL statement
---@param DbName string
---@return number
function DatabaseChanges(DbName) end

---Closes an SQLite database
---@param DbName string
---@return number
function DatabaseClose(DbName) end

---Find the name of a specified column returned by an SQL statement
---@param DbName string
---@param Column number
---@return string
function DatabaseColumnName(DbName, Column) end

---Return a table of all the columns returned by an SQL statement
---@param DbName string
---@return boolean
---@return string
---@return number
---@return nil
function DatabaseColumnNames(DbName) end

---Find how many columns will be returned by an SQL statement
---@param DbName string
---@return number
function DatabaseColumns(DbName) end

---Returns the contents of an SQL column, as text
---@param DbName string
---@param Column number
---@return string
function DatabaseColumnText(DbName, Column) end

---Returns the type of data in an SQL column
---@param DbName string
---@param Column number
---@return number
function DatabaseColumnType(DbName, Column) end

---Returns the contents of an SQL column, as text, float, integer, or null
---@param DbName string
---@param Column number
---@return boolean
---@return string
---@return number
---@return nil
function DatabaseColumnValue(DbName, Column) end

---Returns the contents of all the SQL columns after a step
---@param DbName string
---@return boolean
---@return string
---@return number
---@return nil
function DatabaseColumnValues(DbName) end

---Returns an English string describing the most recent SQL error
---@param DbName string
---@return string
function DatabaseError(DbName) end

---Executes SQL code against an SQLite database
---@param DbName string
---@param Sql string
---@return number
function DatabaseExec(DbName, Sql) end

---Finalizes (wraps up) a previously-prepared SQL statement
---@param DbName string
---@return number
function DatabaseFinalize(DbName) end

---Returns a single field from an SQL database
---@param Name string
---@param Sql string
---@return boolean
---@return string
---@return number
---@return nil
function DatabaseGetField(Name, Sql) end

---Returns information about a database
---@param DbName string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function DatabaseInfo(DbName, InfoType) end

---Returns the most recently automatically allocated database key
---@param DbName string
---@return string
function DatabaseLastInsertRowid(DbName) end

---Lists all databases
---@return boolean
---@return string
---@return number
---@return nil
function DatabaseList() end

---Opens an SQLite database
---@param DbName string
---@param Filename string
---@param Flags number
---@return number
function DatabaseOpen(DbName, Filename, Flags) end

---Prepares an SQL statement for execution
---@param DbName string
---@param Sql string
---@return number
function DatabasePrepare(DbName, Sql) end

---Resets a previously-prepared SQL statement to the start
---@param DbName string
---@return number
function DatabaseReset(DbName) end

---Executes a previously-prepared SQL statement
---@param DbName string
---@return number
function DatabaseStep(DbName) end

---Returns a count of the total changes to the database
---@param DbName string
---@return number
function DatabaseTotalChanges(DbName) end

---Displays debugging information about the world
---@param Command string
---@return boolean
---@return string
---@return number
---@return nil
function Debug(Command) end

---Deletes an alias
---@param AliasName string
---@return number
function DeleteAlias(AliasName) end

---Deletes a group of aliases
---@param GroupName string
---@return number
function DeleteAliasGroup(GroupName) end

---Deletes the all items from the auto-mapper sequence.
---@return number
function DeleteAllMapItems() end

---Deletes command history list.
---@return nil
function DeleteCommandHistory() end

---Deletes a group of triggers, aliases and timers
---@param GroupName string
---@return number
function DeleteGroup(GroupName) end

---Deletes the most recently-added item from the auto-mapper sequence.
---@return number
function DeleteLastMapItem() end

---Clears some recent lines from the output window.
---@param Count number
---@return nil
function DeleteLines(Count) end

---Clears all output from the output window.
---@return nil
function DeleteOutput() end

---Deletes all temporary aliases
---@return number
function DeleteTemporaryAliases() end

---Deletes all temporary timers
---@return number
function DeleteTemporaryTimers() end

---Deletes all temporary triggers
---@return number
function DeleteTemporaryTriggers() end

---Deletes a timer
---@param TimerName string
---@return number
function DeleteTimer(TimerName) end

---Deletes a group of timers
---@param GroupName string
---@return number
function DeleteTimerGroup(GroupName) end

---Deletes a trigger
---@param TriggerName string
---@return number
function DeleteTrigger(TriggerName) end

---Deletes a group of triggers
---@param GroupName string
---@return number
function DeleteTriggerGroup(GroupName) end

---Deletes a variable
---@param VariableName string
---@return number
function DeleteVariable(VariableName) end

---Discards the speed walk queue
---@return number
function DiscardQueue() end

---Disconnects the world from the MUD server
---@return number
function Disconnect() end

---Adds a one-shot, temporary timer - simplified interface
---@param Seconds nil
---@param SendText string
---@return number
function DoAfter(Seconds, SendText) end

---Adds a one-shot, temporary note timer - simplified interface
---@param Seconds number
---@param NoteText string
---@return number
function DoAfterNote(Seconds, NoteText) end

---Adds a one-shot, temporary, timer to carry out some special action
---@param Seconds number
---@param SendText string
---@param SendTo number
---@return number
function DoAfterSpecial(Seconds, SendText, SendTo) end

---Adds a one-shot, temporary speedwalk timer - simplified interface
---@param Seconds number
---@param SendText string
---@return number
function DoAfterSpeedWalk(Seconds, SendText) end

---Queues a MUSHclient menu command
---@param Command string
---@return number
function DoCommand(Command) end

---A flag to indicate whether we are echoing command input to the output window
---@return boolean
EchoInput = nil

---Returns the Levenshtein Edit Distance between two words
---@param Source string
---@param Target string
---@return number
function EditDistance(Source, Target) end

---Enables or disables an alias
---@param AliasName string
---@param Enabled boolean
---@return number
function EnableAlias(AliasName, Enabled) end

---Enables/disables a group of aliases
---@param GroupName string
---@param Enabled boolean
---@return number
function EnableAliasGroup(GroupName, Enabled) end

---Enables/disables a group of triggers, aliases and timers
---@param GroupName string
---@param Enabled boolean
---@return number
function EnableGroup(GroupName, Enabled) end

---Enables or disables the auto-mapper
---@param Enabled boolean
---@return nil
function EnableMapping(Enabled) end

---Enables or disables the specified plugin
---@param PluginID string
---@param Enabled boolean
---@return number
function EnablePlugin(PluginID, Enabled) end

---Enables or disables an timer
---@param TimerName string
---@param Enabled boolean
---@return number
function EnableTimer(TimerName, Enabled) end

---Enables/disables a group of timers
---@param GroupName string
---@param Enabled boolean
---@return number
function EnableTimerGroup(GroupName, Enabled) end

---Enables or disables a trigger
---@param TriggerName string
---@param Enabled boolean
---@return number
function EnableTrigger(TriggerName, Enabled) end

---Enables/disables a group of triggers
---@param GroupName string
---@param Enabled boolean
---@return number
function EnableTriggerGroup(GroupName, Enabled) end

---Converts a MUSHclient script error code into an human-readable description
---@param Code number
---@return string
function ErrorDesc(Code) end

---Evaluates a speed walk string
---@param SpeedWalkString string
---@return string
function EvaluateSpeedwalk(SpeedWalkString) end

---Executes a command as if you had typed it into the command window
---@param Command string
---@return number
function Execute(Command) end

---Exports a world item in XML format
---@param Type number
---@param Name string
---@return string
function ExportXML(Type, Name) end

---Performs a filtering operation on one pixel
---@param Pixel number
---@param Operation number
---@param Options nil
---@return number
function FilterPixel(Pixel, Operation, Options) end

---Converts "escape sequences" like \t to their equivalent codes.
---@param Source string
---@return string
function FixupEscapeSequences(Source) end

---Fixes up text for writing as HTML
---@param StringToConvert string
---@return string
function FixupHTML(StringToConvert) end

---Flashes the MUSHclient icon on the Windows taskbar
---@return nil
function FlashIcon() end

---Flushes the log file to disk
---@return number
function FlushLog() end

---Generates a random character name
---@return boolean
---@return string
---@return number
---@return nil
function GenerateName() end

---Gets details about an alias
---@param AliasName string
---@param MatchText nil
---@param ResponseText nil
---@param Parameter nil
---@param Flags nil
---@param ScriptName nil
---@return number
function GetAlias(AliasName, MatchText, ResponseText, Parameter, Flags, ScriptName) end

---Gets details about an alias
---@param AliasName string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function GetAliasInfo(AliasName, InfoType) end

---Gets the list of aliases
---@return boolean
---@return string
---@return number
---@return nil
function GetAliasList() end

---Gets the value of a named alias option
---@param AliasName string
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetAliasOption(AliasName, OptionName) end

---Returns the contents of the specified wildcard for the named alias
---@param AliasName string
---@param WildcardName string
---@return boolean
---@return string
---@return number
---@return nil
function GetAliasWildcard(AliasName, WildcardName) end

---Gets the value of an alphanumeric configuration option
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetAlphaOption(OptionName) end

---Gets the list of world alphanumeric options
---@return boolean
---@return string
---@return number
---@return nil
function GetAlphaOptionList() end

---Get information about a chat connection
---@param ChatID number
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function GetChatInfo(ChatID, InfoType) end

---Gets the list of chat sessions
---@return boolean
---@return string
---@return number
---@return nil
function GetChatList() end

---Gets the value of a chat session option
---@param ID number
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetChatOption(ID, OptionName) end

---Gets the clipboard contents
---@return string
function GetClipboard() end

---Gets the current command in the command window
---@return string
function GetCommand() end

---Returns some or all commands from the command history
---@param Count number
---@return boolean
---@return string
---@return number
---@return nil
function GetCommandList(Count) end

---Returns the number of seconds this world has been connected.
---@return number
function GetConnectDuration() end

---Gets the current value of a named world option
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetCurrentValue(OptionName) end

---Gets the name of a custom colour
---@param WhichColour number
---@return string
function GetCustomColourName(WhichColour) end

---Gets the default value of a named world option
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetDefaultValue(OptionName) end

---Gets screen device capabilities
---@param Index number
---@return number
function GetDeviceCaps(Index) end

---Retrieves the value of an MXP server-defined entity
---@param Name string
---@return string
function GetEntity(Name) end

---Returns the address of the main MUSHclient frame window
---@return number
function GetFrame() end

---Gets the value of a global configuration option
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetGlobalOption(OptionName) end

---Gets the list of global options
---@return boolean
---@return string
---@return number
---@return nil
function GetGlobalOptionList() end

---Returns a list of IP addresses that correspond to a host name on the Internet
---@param HostName string
---@return boolean
---@return string
---@return number
---@return nil
function GetHostAddress(HostName) end

---Returns the host name that corresponds to an IP address on the Internet
---@param IPaddress string
---@return string
function GetHostName(IPaddress) end

---Gets information about the current world
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function GetInfo(InfoType) end

---Returns a list of the internal MUSHclient command names
---@return boolean
---@return string
---@return number
---@return nil
function GetInternalCommandsList() end

---Gets count of lines received
---@return number
function GetLineCount() end

---Gets details about a specified line in the output window
---@param LineNumber number
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function GetLineInfo(LineNumber, InfoType) end

---Returns the number of lines in the output window
---@return number
function GetLinesInBufferCount() end

---Gets value of a named world option, as loaded from the world file
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetLoadedValue(OptionName) end

---Returns the position and size of the main MUSHclient window
---@return string
function GetMainWindowPosition() end

---Returns the mapping for how a particular colour will be displayed
---@param Which number
---@return number
function GetMapColour(Which) end

---Gets a count of the number of items in the auto-map sequence
---@return number
function GetMappingCount() end

---Gets one item from the auto-map sequence
---@param Item number
---@return boolean
---@return string
---@return number
---@return nil
function GetMappingItem(Item) end

---Returns the speedwalk string generated by the auto-mapper.
---@return boolean
---@return string
---@return number
---@return nil
function GetMappingString() end

---Gets the length of the text in a notepad window
---@param Title string
---@return number
function GetNotepadLength(Title) end

---Gets the list of open notepads - returning their titles
---@param All boolean
---@return boolean
---@return string
---@return number
---@return nil
function GetNotepadList(All) end

---Gets the text from a notepad window
---@param Title string
---@return string
function GetNotepadText(Title) end

---Returns the position and size of the specified notepad window
---@param Title string
---@return string
function GetNotepadWindowPosition(Title) end

---Gets the world's notes
---@return string
function GetNotes() end

---Gets the style for notes
---@return number
function GetNoteStyle() end

---Gets value of a named world option
---@param OptionName string
---@return number
function GetOption(OptionName) end

---Gets the list of world options
---@return boolean
---@return string
---@return number
---@return nil
function GetOptionList() end

---Gets details about a named alias for a specified plugin
---@param PluginID string
---@param AliasName string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginAliasInfo(PluginID, AliasName, InfoType) end

---Gets the list of aliases in a specified plugin
---@param PluginID string
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginAliasList(PluginID) end

---Gets the value of a named alias option for a specified plugin
---@param PluginID string
---@param AliasName string
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginAliasOption(PluginID, AliasName, OptionName) end

---Returns the 24-character ID of the current plugin
---@return string
function GetPluginID() end

---Gets details about a specified plugin
---@param PluginID string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginInfo(PluginID, InfoType) end

---Gets a list of installed plugins.
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginList() end

---Returns the name of the current plugin
---@return string
function GetPluginName() end

---Gets details about a named timer for a specified plugin
---@param PluginID string
---@param TimerName string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginTimerInfo(PluginID, TimerName, InfoType) end

---Gets the list of timers in a specified plugin
---@param PluginID string
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginTimerList(PluginID) end

---Gets the value of a named timer option for a specified plugin
---@param PluginID string
---@param TimerName string
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginTimerOption(PluginID, TimerName, OptionName) end

---Gets details about a named trigger for a specified plugin
---@param PluginID string
---@param TriggerName string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginTriggerInfo(PluginID, TriggerName, InfoType) end

---Gets the list of triggers in a specified plugin
---@param PluginID string
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginTriggerList(PluginID) end

---Gets the value of a named trigger option for a specified plugin
---@param PluginID string
---@param TriggerName string
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginTriggerOption(PluginID, TriggerName, OptionName) end

---Gets the contents of a variable belonging to a plugin
---@param PluginID string
---@param VariableName string
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginVariable(PluginID, VariableName) end

---Gets the list of variables in a specified plugin
---@param PluginID string
---@return boolean
---@return string
---@return number
---@return nil
function GetPluginVariableList(PluginID) end

---Returns a variant array which is a list of queued commands
---@return boolean
---@return string
---@return number
---@return nil
function GetQueue() end

---Returns the number of bytes received from the world
---@return number
function GetReceivedBytes() end

---Assembles a block of text from recent MUD output
---@param Count number
---@return string
function GetRecentLines(Count) end

---Returns the amount of time spent in script routines
---@return nil
function GetScriptTime() end

---Returns the endling column of the selection in the output window
---@return number
function GetSelectionEndColumn() end

---Returns the last line of the selection in the output window
---@return number
function GetSelectionEndLine() end

---Returns the starting column of the selection in the output window
---@return number
function GetSelectionStartColumn() end

---Returns the starting line of the selection in the output window
---@return number
function GetSelectionStartLine() end

---Returns the number of bytes sent to the world
---@return number
function GetSentBytes() end

---Gets the status of a sound started by PlaySound
---@param Buffer number
---@return number
function GetSoundStatus(Buffer) end

---Gets details about a specified style run for a specified line in the output window
---@param LineNumber number
---@param StyleNumber number
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function GetStyleInfo(LineNumber, StyleNumber, InfoType) end

---Gets the colour of various windows items
---@param Index number
---@return number
function GetSysColor(Index) end

---Returns selected system information from Windows
---@param Index number
---@return number
function GetSystemMetrics(Index) end

---Gets details about a timer
---@param TimerName string
---@param Hour nil
---@param Minute nil
---@param Second nil
---@param ResponseText nil
---@param Flags nil
---@param ScriptName nil
---@return number
function GetTimer(TimerName, Hour, Minute, Second, ResponseText, Flags, ScriptName) end

---Gets details about a timer
---@param TimerName string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function GetTimerInfo(TimerName, InfoType) end

---Gets the list of timers
---@return boolean
---@return string
---@return number
---@return nil
function GetTimerList() end

---Gets the value of a named timer option
---@param TimerName string
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetTimerOption(TimerName, OptionName) end

---Gets details about a named trigger
---@param TriggerName string
---@param MatchText nil
---@param ResponseText nil
---@param Flags nil
---@param Colour nil
---@param Wildcard nil
---@param SoundFileName nil
---@param ScriptName nil
---@return number
function GetTrigger(TriggerName, MatchText, ResponseText, Flags, Colour, Wildcard, SoundFileName, ScriptName) end

---Gets details about a named trigger
---@param TriggerName string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function GetTriggerInfo(TriggerName, InfoType) end

---Gets the list of triggers
---@return boolean
---@return string
---@return number
---@return nil
function GetTriggerList() end

---Gets the value of a named trigger option
---@param TriggerName string
---@param OptionName string
---@return boolean
---@return string
---@return number
---@return nil
function GetTriggerOption(TriggerName, OptionName) end

---Returns the contents of the specified wildcard for the named trigger
---@param TriggerName string
---@param WildcardName string
---@return boolean
---@return string
---@return number
---@return nil
function GetTriggerWildcard(TriggerName, WildcardName) end

---Find a free port for UDP listening
---@param First number
---@param Last number
---@return number
function GetUdpPort(First, Last) end

---Creates a unique ID for general use, or for making Plugin IDs
---@return string
function GetUniqueID() end

---Returns a unique number
---@return number
function GetUniqueNumber() end

---Gets the contents of a variable
---@param VariableName string
---@return boolean
---@return string
---@return number
---@return nil
function GetVariable(VariableName) end

---Gets the list of variables
---@return boolean
---@return string
---@return number
---@return nil
function GetVariableList() end

---Gets an object reference to the named world
---@param WorldName string
---@return nil
function GetWorld(WorldName) end

---Gets an object reference to the world given its unique ID
---@param WorldID string
---@return nil
function GetWorldById(WorldID) end

---Returns the 24-character ID of the current world
---@return string
function GetWorldID() end

---Gets the list of open worlds - returning their world IDs
---@return boolean
---@return string
---@return number
---@return nil
function GetWorldIdList() end

---Gets the list of open worlds - returning their world names
---@return boolean
---@return string
---@return number
---@return nil
function GetWorldList() end

---Returns the position and size of the current world window
---@return string
function GetWorldWindowPosition() end

---Returns the position and size of a specific world window
---@param Which number
---@return string
function GetWorldWindowPositionX(Which) end

---Retrieves the value of a standard entity
---@param Entity string
---@return string
function GetXMLEntity(Entity) end

---Produces a hash (checksum) of a specified piece of text
---@param Text string
---@return string
function Hash(Text) end

---Shows help for a script function, or a list of functions
---@param Name string
---@return nil
function Help(Name) end

---Creates a hyperlink in the output window
---@param Action string
---@param Text string
---@param Hint string
---@param TextColour string
---@param BackColour string
---@param URL boolean
---@return nil
function Hyperlink(Action, Text, Hint, TextColour, BackColour, URL) end

---Imports configuration data in XML format
---@param XML string
---@return number
function ImportXML(XML) end

---Adds text to the "info" tool bar
---@param Message string
---@return nil
function Info(Message) end

---Sets the background colour for the info bar
---@param Name string
---@return nil
function InfoBackground(Name) end

---Clears all text from the info bar
---@return nil
function InfoClear() end

---Sets the colour of the foreground (text color) for the info bar
---@param Name string
---@return nil
function InfoColour(Name) end

---Changes the font, font size and style for text on the info bar
---@param FontName string
---@param Size number
---@param Style number
---@return nil
function InfoFont(FontName, Size, Style) end

---Tests to see if an alias exists
---@param AliasName string
---@return number
function IsAlias(AliasName) end

---Tests to see if the world is connected to the MUD server
---@return boolean
function IsConnected() end

---Tests to see if a log file is open
---@return boolean
function IsLogOpen() end

---Checks to see if a particular plugin is installed
---@param PluginID string
---@return boolean
function IsPluginInstalled(PluginID) end

---Tests to see if a timer exists
---@param TimerName string
---@return number
function IsTimer(TimerName) end

---Tests to see if a trigger exists
---@param TriggerName string
---@return number
function IsTrigger(TriggerName) end

---Loads a plugin from disk
---@param FileName string
---@return number
function LoadPlugin(FileName) end

---The property of whether commands are logged to the log file
---@return number
LogInput = nil

---The property of whether notes are logged to the log file
---@return number
LogNotes = nil

---The property of whether MUD output is logged to the log file
---@return number
LogOutput = nil

---Sends a message to the MUD and logs it
---@param Message string
---@return number
function LogSend(Message) end

---Converts wildcard matching text to a regular expression
---@param Text string
---@return string
function MakeRegularExpression(Text) end

---Changes the colour mapping - the way colours are displayed
---@param Original number
---@param Replacement number
---@return nil
function MapColour(Original, Replacement) end

---Returns an array of all the mapped colours
---@return boolean
---@return string
---@return number
---@return nil
function MapColourList() end

---A flag to indicate whether we are mapping the world
---@return boolean
Mapping = nil

---Creates a pop-up menu inside the command window
---@param Items string
---@param Default string
---@return string
function Menu(Items, Default) end

---Returns the metaphone code for the supplied word
---@param Word string
---@param Length number
---@return string
function Metaphone(Word, Length) end

---Move and resize the main MUSHclient window
---@param Left number
---@param Top number
---@param Width number
---@param Height number
---@return nil
function MoveMainWindow(Left, Top, Width, Height) end

---Move and resize the specified notepad window
---@param Title string
---@param Left number
---@param Top number
---@param Width number
---@param Height number
---@return number
function MoveNotepadWindow(Title, Left, Top, Width, Height) end

---Move and resize a world window
---@param Left number
---@param Top number
---@param Width number
---@param Height number
---@return nil
function MoveWorldWindow(Left, Top, Width, Height) end

---Move and resize a specific world window
---@param Left number
---@param Top number
---@param Width number
---@param Height number
---@param Which number
---@return nil
function MoveWorldWindowX(Left, Top, Width, Height, Which) end

---Returns pseudo-random number using the Mersenne Twister algorithm
---@return nil
function MtRand() end

---Seed the Mersenne Twister pseudo-random number generator
---@param Seed number
---@return nil
function MtSrand(Seed) end

---Gets/sets the RGB colour for one of the 8 ANSI normal colours
---@return number
NormalColour = nil

---Sends a note to the output window
---@param Message string
---@return nil
function Note(Message) end

---Chooses which custom colour will be used for world notes.
---@return number
NoteColour = nil

---Chooses which RGB colour will be used for world notes - background colour
---@return number
NoteColourBack = nil

---Chooses which RGB colour will be used for world notes - text colour
---@return number
NoteColourFore = nil

---Chooses which RGB colour name will be used for world notes - text and background
---@param Foreground string
---@param Background string
---@return nil
function NoteColourName(Foreground, Background) end

---Chooses which RGB colour will be used for world notes - text and background
---@param Foreground number
---@param Background number
---@return nil
function NoteColourRGB(Foreground, Background) end

---Draws a horizontal rule in the output window
---@return nil
function NoteHr() end

---Changes the text and background colour of the selected notepad window
---@param Title string
---@param TextColour string
---@param BackgroundColour string
---@return number
function NotepadColour(Title, TextColour, BackgroundColour) end

---Changes the font and style of the selected notepad window
---@param Title string
---@param FontName string
---@param Size number
---@param Style number
---@param Charset number
---@return number
function NotepadFont(Title, FontName, Size, Style, Charset) end

---Make a selected notepad window read-only
---@param Title string
---@param ReadOnly boolean
---@return number
function NotepadReadOnly(Title, ReadOnly) end

---Changes the save method for this notepad window
---@param Title string
---@param Method number
---@return boolean
function NotepadSaveMethod(Title, Method) end

---Sets the style for notes
---@param Style number
---@return nil
function NoteStyle(Style) end

---Opens a named document
---@param FileName string
---@return nil
function Open(FileName) end

---Opens a supplied URL in your default web browser
---@param URL string
---@return number
function OpenBrowser(URL) end

---Opens a log file.
---@param LogFileName string
---@param Append boolean
---@return number
function OpenLog(LogFileName, Append) end

---Pastes text into the command window, replacing the current selection
---@param Text string
---@return string
function PasteCommand(Text) end

---Turns pause mode on or off
---@param Flag boolean
---@return nil
function Pause(Flag) end

---Invokes the MUSHclient colour picker dialog
---@param Suggested number
---@return number
function PickColour(Suggested) end

---Plays a sound using DirectSound
---@param Buffer number
---@param FileName string
---@param Loop boolean
---@param Volume nil
---@param Pan nil
---@return number
function PlaySound(Buffer, FileName, Loop, Volume, Pan) end

---Checks if a plugin supports a particular routine
---@param PluginID string
---@param Routine string
---@return number
function PluginSupports(PluginID, Routine) end

---Pushes the current command into the command history list
---@return string
function PushCommand() end

---Queues a command for sending at the "speed walk" rate.
---@param Message string
---@param Echo boolean
---@return number
function Queue(Message, Echo) end

---Loads in a file for generating character names
---@param FileName string
---@return number
function ReadNamesFile(FileName) end

---Schedules a redraw for all windows for this world
---@return nil
function Redraw() end

---Reloads an installed plugin
---@param PluginID string
---@return number
function ReloadPlugin(PluginID) end

---Removes backtracks from a speed walk string
---@param Path string
---@return string
function RemoveBacktracks(Path) end

---A flag to indicate whether we backtracks are removed during mapping
---@return boolean
RemoveMapReverses = nil

---Forces an immediate redraw for all windows for this world
---@return nil
function Repaint() end

---Replaces one substring with another
---@param Source string
---@param SearchFor string
---@param ReplaceWith string
---@param Multiple boolean
---@return string
function Replace(Source, SearchFor, ReplaceWith, Multiple) end

---Replaces text in a notepad window
---@param Title string
---@param Contents string
---@return boolean
function ReplaceNotepad(Title, Contents) end

---Resets all outstanding MXP/Pueblo tags
---@return nil
function Reset() end

---Resets the cached IP address of the world and proxy server
---@return nil
function ResetIP() end

---Resets the time elapsed shown on the status bar
---@return nil
function ResetStatusTime() end

---Resets a named timer
---@param TimerName string
---@return number
function ResetTimer(TimerName) end

---Resets all timers
---@return nil
function ResetTimers() end

---Reverses a speed walk string
---@param SpeedWalkString string
---@return string
function ReverseSpeedwalk(SpeedWalkString) end

---Converts an RGB colour code to its equivalent name
---@param Colour number
---@return string
function RGBColourToName(Colour) end

---Saves world configuration.
---@param Name string
---@return boolean
function Save(Name) end

---Saves a notepad window to disk
---@param Title string
---@param FileName string
---@param ReplaceExisting boolean
---@return number
function SaveNotepad(Title, FileName, ReplaceExisting) end

---Saves the state of the current plugin
---@return number
function SaveState() end

---Selects (highlights) the current command in the command window
---@return nil
function SelectCommand() end

---Sends a message to the MUD
---@param Message string
---@return number
function Send(Message) end

---Sends a message to the MUD immediately, bypassing the speedwalk queue
---@param Message string
---@return number
function SendImmediate(Message) end

---Sends a message to the MUD without echoing in the output window
---@param Message string
---@return number
function SendNoEcho(Message) end

---Sends a low-level packet of data to the MUD
---@param Packet string
---@return number
function SendPkt(Packet) end

---Sends a message to the MUD and saves it in the command history buffer
---@param Message string
---@return number
function SendPush(Message) end

---Sends a message to the MUD with various options
---@param Message string
---@param Echo boolean
---@param Queue boolean
---@param Log boolean
---@param History boolean
---@return number
function SendSpecial(Message, Echo, Queue, Log, History) end

---Creates a notepad and sends text to it
---@param Title string
---@param Contents string
---@return boolean
function SendToNotepad(Title, Contents) end

---Sets the value of a named alias option
---@param AliasName string
---@param OptionName string
---@param Value string
---@return number
function SetAliasOption(AliasName, OptionName, Value) end

---Sets value of a named world alphanumeric option
---@param OptionName string
---@param Value string
---@return number
function SetAlphaOption(OptionName, Value) end

---Sets a background colour for the output window
---@param Colour number
---@return number
function SetBackgroundColour(Colour) end

---Sets a background image for the output window
---@param FileName string
---@param Mode number
---@return number
function SetBackgroundImage(FileName, Mode) end

---Sets or clears the "document has changed" flag
---@param ChangedFlag boolean
---@return nil
function SetChanged(ChangedFlag) end

---Sets the value of a chat session option
---@param ID number
---@param OptionName string
---@param Value string
---@return number
function SetChatOption(ID, OptionName, Value) end

---Sets the clipboard contents
---@param Text string
---@return nil
function SetClipboard(Text) end

---Sends text to the command window
---@param Message string
---@return number
function SetCommand(Message) end

---Selects specified columns in the command window
---@param First number
---@param Last number
---@return number
function SetCommandSelection(First, Last) end

---Set the height of the command (input) window
---@param Height number
---@return number
function SetCommandWindowHeight(Height) end

---Changes the shape of the mouse cursor
---@param Cursor number
---@return number
function SetCursor(Cursor) end

---Sets the name of a custom colour
---@param WhichColour number
---@param Name string
---@return number
function SetCustomColourName(WhichColour, Name) end

---Sets the value of an MXP entity
---@param Name string
---@param Contents string
---@return nil
function SetEntity(Name, Contents) end

---Sets a foreground image for the output window
---@param FileName string
---@param Mode number
---@return number
function SetForegroundImage(FileName, Mode) end

---Sets the background colour of the overall MUSHclient frame
---@param Colour number
---@return nil
function SetFrameBackgroundColour(Colour) end

---Sets the font for the input window
---@param FontName string
---@param PointSize number
---@param Weight number
---@param Italic boolean
---@return nil
function SetInputFont(FontName, PointSize, Weight, Italic) end

---Sets the main output window title
---@param Title string
---@return nil
function SetMainTitle(Title) end

---Sets the notes for the world.
---@param Message string
---@return nil
function SetNotes(Message) end

---Sets value of a named world option
---@param OptionName string
---@param Value number
---@return number
function SetOption(OptionName, Value) end

---Sets the font for the output window.
---@param FontName string
---@param PointSize number
---@return nil
function SetOutputFont(FontName, PointSize) end

---Sets the scroll bar position, and hides or shows it
---@param Position number
---@param Visible boolean
---@return number
function SetScroll(Position, Visible) end

---Sets a selection range in the output window
---@param StartLine number
---@param EndLine number
---@param StartColumn number
---@param EndColumn number
---@return nil
function SetSelection(StartLine, EndLine, StartColumn, EndColumn) end

---Sets the status line text
---@param Message string
---@return nil
function SetStatus(Message) end

---Sets the value of a named timer option
---@param TimerName string
---@param OptionName string
---@param Value string
---@return number
function SetTimerOption(TimerName, OptionName, Value) end

---Sets the world window title
---@param Title string
---@return nil
function SetTitle(Title) end

---Sets the position of the game toolbars on the screen.
---@param Which number
---@param Float boolean
---@param Side number
---@param Top number
---@param Left number
---@return number
function SetToolBarPosition(Which, Float, Side, Top, Left) end

---Sets the value of a named trigger option
---@param TriggerName string
---@param OptionName string
---@param Value string
---@return number
function SetTriggerOption(TriggerName, OptionName, Value) end

---Sets the number of "unseen lines" for this world
---@param Counter number
---@return nil
function SetUnseenLines(Counter) end

---Sets the value of a variable
---@param VariableName string
---@param Contents string
---@return number
function SetVariable(VariableName, Contents) end

---Changes the status of the current world window
---@param Parameter number
---@return nil
function SetWorldWindowStatus(Parameter) end

---Adds an item to  the list shown for Shift+Tab completion
---@param Item string
---@return number
function ShiftTabCompleteItem(Item) end

---Shows or hides the "info" tool bar
---@param Visible boolean
---@return nil
function ShowInfoBar(Visible) end

---Simulate input from the MUD, for debugging purposes
---@param Text string
---@return nil
function Simulate(Text) end

---Plays a sound
---@param SoundFileName string
---@return number
function Sound(SoundFileName) end

---The number of milliseconds delay between speed walk commands
---@return number
SpeedWalkDelay = nil

---Spell checks an arbitrary string of text
---@param Text string
---@return boolean
---@return string
---@return number
---@return nil
function SpellCheck(Text) end

---Spell checks the text in the command window
---@param StartCol number
---@param EndCol number
---@return number
function SpellCheckCommand(StartCol, EndCol) end

---Spell checks an arbitrary string of text, invloking the spell-checker dialog
---@param Text string
---@return boolean
---@return string
---@return number
---@return nil
function SpellCheckDlg(Text) end

---Stops trigger evaluation
---@param AllPlugins boolean
---@return nil
function StopEvaluatingTriggers(AllPlugins) end

---Stop playing a sound started by PlaySound
---@param Buffer number
---@return number
function StopSound(Buffer) end

---Strips ANSI colour sequences from a string
---@param Message string
---@return string
function StripANSI(Message) end

---Sends a message to the output window - not terminated by a newline
---@param Message string
---@return nil
function Tell(Message) end

---Specifies the size of the rectangle in which text is displayed in the output window.
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param BorderOffset number
---@param BorderColour number
---@param BorderWidth number
---@param OutsideFillColour number
---@param OutsideFillStyle number
---@return number
function TextRectangle(Left, Top, Right, Bottom, BorderOffset, BorderColour, BorderWidth, OutsideFillColour, OutsideFillStyle) end

---Trace mode property
---@return boolean
Trace = nil

---Outputs the supplied message to the world Trace
---@param Message string
---@return nil
function TraceOut(Message) end

---Sends a debugging message to the localizing translator script
---@param Message string
---@return number
function TranslateDebug(Message) end

---Translate German umluat sequences
---@param Text string
---@return string
function TranslateGerman(Text) end

---Sets the transparency of the main MUSHclient window under Windows XP
---@param Key number
---@param Amount number
---@return boolean
function Transparency(Key, Amount) end

---Trims leading and trailing spaces from a string
---@param Source string
---@return string
function Trim(Source) end

---Listens for incoming packets using the UDP protocol
---@param IP string
---@param Port number
---@param Script string
---@return number
function UdpListen(IP, Port, Script) end

---Returns an array of all the UDP ports in use by this world
---@return boolean
---@return string
---@return number
---@return nil
function UdpPortList() end

---Sends a packet over the network using the UDP protocol
---@param IP string
---@param Port number
---@param Text string
---@return number
function UdpSend(IP, Port, Text) end

---Unloads an installed plugin
---@param PluginID string
---@return number
function UnloadPlugin(PluginID) end

---Gets the MUSHclient version string.
---@return string
function Version() end

---Adds a hotspot  to a miniwindow
---@param WindowName string
---@param HotspotId string
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param MouseOver string
---@param CancelMouseOver string
---@param MouseDown string
---@param CancelMouseDown string
---@param MouseUp string
---@param TooltipText string
---@param Cursor number
---@param Flags number
---@return number
function WindowAddHotspot(WindowName, HotspotId, Left, Top, Right, Bottom, MouseOver, CancelMouseOver, MouseDown, CancelMouseDown, MouseUp, TooltipText, Cursor, Flags) end

---Draws an arc in a miniwindow
---@param WindowName string
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param PenColour number
---@param PenStyle number
---@param PenWidth number
---@return number
function WindowArc(WindowName, Left, Top, Right, Bottom, x1, y1, x2, y2, PenColour, PenStyle, PenWidth) end

---Draws a Bézier curve in a miniwindow
---@param WindowName string
---@param Points string
---@param PenColour number
---@param PenStyle number
---@param PenWidth number
---@return number
function WindowBezier(WindowName, Points, PenColour, PenStyle, PenWidth) end

---Blends an image into a miniwindow, using a specified blending mode
---@param WindowName string
---@param ImageId string
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param Mode number
---@param Opacity nil
---@param SrcLeft number
---@param SrcTop number
---@param SrcRight number
---@param SrcBottom number
---@return number
function WindowBlendImage(WindowName, ImageId, Left, Top, Right, Bottom, Mode, Opacity, SrcLeft, SrcTop, SrcRight, SrcBottom) end

---Draws ellipses, filled rectangles, round rectangles, chords, pies in a miniwindow
---@param WindowName string
---@param Action number
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param PenColour number
---@param PenStyle number
---@param PenWidth number
---@param BrushColour number
---@param BrushStyle number
---@param Extra1 number
---@param Extra2 number
---@param Extra3 number
---@param Extra4 number
---@return number
function WindowCircleOp(WindowName, Action, Left, Top, Right, Bottom, PenColour, PenStyle, PenWidth, BrushColour, BrushStyle, Extra1, Extra2, Extra3, Extra4) end

---Creates a miniwindow
---@param WindowName string
---@param Left number
---@param Top number
---@param Width number
---@param Height number
---@param Position number
---@param Flags number
---@param BackgroundColour number
---@return number
function WindowCreate(WindowName, Left, Top, Width, Height, Position, Flags, BackgroundColour) end

---Creates an image in a miniwindow
---@param WindowName string
---@param ImageId string
---@param Row8 number
---@param Row7 number
---@param Row6 number
---@param Row5 number
---@param Row4 number
---@param Row3 number
---@param Row2 number
---@param Row1 number
---@return number
function WindowCreateImage(WindowName, ImageId, Row8, Row7, Row6, Row5, Row4, Row3, Row2, Row1) end

---Deletes a miniwindow
---@param WindowName string
---@return number
function WindowDelete(WindowName) end

---Deletes all hotspots from a miniwindow
---@param WindowName string
---@return number
function WindowDeleteAllHotspots(WindowName) end

---Deletes a hotspot from a miniwindow
---@param WindowName string
---@param HotspotId string
---@return number
function WindowDeleteHotspot(WindowName, HotspotId) end

---Adds a drag handler to a miniwindow hotspot
---@param WindowName string
---@param HotspotId string
---@param MoveCallback string
---@param ReleaseCallback string
---@param Flags number
---@return number
function WindowDragHandler(WindowName, HotspotId, MoveCallback, ReleaseCallback, Flags) end

---Draws an image into a miniwindow
---@param WindowName string
---@param ImageId string
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param Mode number
---@param SrcLeft number
---@param SrcTop number
---@param SrcRight number
---@param SrcBottom number
---@return number
function WindowDrawImage(WindowName, ImageId, Left, Top, Right, Bottom, Mode, SrcLeft, SrcTop, SrcRight, SrcBottom) end

---Draws an image into a miniwindow respecting the alpha channel
---@param WindowName string
---@param ImageId string
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param Opacity nil
---@param SrcLeft number
---@param SrcTop number
---@return number
function WindowDrawImageAlpha(WindowName, ImageId, Left, Top, Right, Bottom, Opacity, SrcLeft, SrcTop) end

---Performs a filtering operation over part of the miniwindow.
---@param WindowName string
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param Operation number
---@param Options nil
---@return number
function WindowFilter(WindowName, Left, Top, Right, Bottom, Operation, Options) end

---Loads a font into a miniwindow
---@param WindowName string
---@param FontId string
---@param FontName string
---@param Size nil
---@param Bold boolean
---@param Italic boolean
---@param Underline boolean
---@param Strikeout boolean
---@param Charset number
---@param PitchAndFamily number
---@return number
function WindowFont(WindowName, FontId, FontName, Size, Bold, Italic, Underline, Strikeout, Charset, PitchAndFamily) end

---Returns information about a font
---@param WindowName string
---@param FontId string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function WindowFontInfo(WindowName, FontId, InfoType) end

---Lists all fonts loaded into a miniwindow
---@param WindowName string
---@return boolean
---@return string
---@return number
---@return nil
function WindowFontList(WindowName) end

---Draws the alpha channel of an image into a miniwindow
---@param WindowName string
---@param ImageId string
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param SrcLeft number
---@param SrcTop number
---@return number
function WindowGetImageAlpha(WindowName, ImageId, Left, Top, Right, Bottom, SrcLeft, SrcTop) end

---Gets the colour of a single pixel in a miniwindow
---@param WindowName string
---@param x number
---@param y number
---@return number
function WindowGetPixel(WindowName, x, y) end

---Draws a gradient in a rectangle
---@param WindowName string
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param StartColour number
---@param EndColour number
---@param Mode number
---@return number
function WindowGradient(WindowName, Left, Top, Right, Bottom, StartColour, EndColour, Mode) end

---Returns information about a hotspot
---@param WindowName string
---@param HotspotId string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function WindowHotspotInfo(WindowName, HotspotId, InfoType) end

---Lists all hotspots installed into a miniwindow
---@param WindowName string
---@return boolean
---@return string
---@return number
---@return nil
function WindowHotspotList(WindowName) end

---Changes the tooltip text for a hotspot in a miniwindow
---@param WindowName string
---@param HotspotId string
---@param TooltipText string
---@return number
function WindowHotspotTooltip(WindowName, HotspotId, TooltipText) end

---Creates an image from another miniwindow
---@param WindowName string
---@param ImageId string
---@param SourceWindow string
---@return number
function WindowImageFromWindow(WindowName, ImageId, SourceWindow) end

---Returns information about an image
---@param WindowName string
---@param ImageId string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function WindowImageInfo(WindowName, ImageId, InfoType) end

---Lists all images installed into a miniwindow
---@param WindowName string
---@return boolean
---@return string
---@return number
---@return nil
function WindowImageList(WindowName) end

---Draws an ellipse, rectangle or round rectangle, filled with an image
---@param WindowName string
---@param Action number
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param PenColour number
---@param PenStyle number
---@param PenWidth number
---@param BrushColour number
---@param ImageId string
---@param EllipseWidth number
---@param EllipseHeight number
---@return number
function WindowImageOp(WindowName, Action, Left, Top, Right, Bottom, PenColour, PenStyle, PenWidth, BrushColour, ImageId, EllipseWidth, EllipseHeight) end

---Returns information about a miniwindow
---@param WindowName string
---@param InfoType number
---@return boolean
---@return string
---@return number
---@return nil
function WindowInfo(WindowName, InfoType) end

---Draws a line in a miniwindow
---@param WindowName string
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param PenColour number
---@param PenStyle number
---@param PenWidth number
---@return number
function WindowLine(WindowName, x1, y1, x2, y2, PenColour, PenStyle, PenWidth) end

---Lists all miniwindows
---@return boolean
---@return string
---@return number
---@return nil
function WindowList() end

---Loads an image into a miniwindow from a disk file
---@param WindowName string
---@param ImageId string
---@param FileName string
---@return number
function WindowLoadImage(WindowName, ImageId, FileName) end

---Creates a pop-up menu inside a miniwindow
---@param WindowName string
---@param Left number
---@param Top number
---@param Items string
---@return string
function WindowMenu(WindowName, Left, Top, Items) end

---Merges an image into a miniwindow based on an alpha mask
---@param WindowName string
---@param ImageId string
---@param MaskId string
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param Mode number
---@param Opacity nil
---@param SrcLeft number
---@param SrcTop number
---@param SrcRight number
---@param SrcBottom number
---@return number
function WindowMergeImageAlpha(WindowName, ImageId, MaskId, Left, Top, Right, Bottom, Mode, Opacity, SrcLeft, SrcTop, SrcRight, SrcBottom) end

---Moves a hotspot in a miniwindow
---@param WindowName string
---@param HotspotId string
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@return number
function WindowMoveHotspot(WindowName, HotspotId, Left, Top, Right, Bottom) end

---Draws a polygon in a miniwindow
---@param WindowName string
---@param Points string
---@param PenColour number
---@param PenStyle number
---@param PenWidth number
---@param BrushColour number
---@param BrushStyle number
---@param Close boolean
---@param Winding boolean
---@return number
function WindowPolygon(WindowName, Points, PenColour, PenStyle, PenWidth, BrushColour, BrushStyle, Close, Winding) end

---Moves a miniwindow
---@param WindowName string
---@param Left number
---@param Top number
---@param Position number
---@param Flags number
---@return number
function WindowPosition(WindowName, Left, Top, Position, Flags) end

---Draws a rectangle in a miniwindow
---@param WindowName string
---@param Action number
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param Colour1 number
---@param Colour2 number
---@return number
function WindowRectOp(WindowName, Action, Left, Top, Right, Bottom, Colour1, Colour2) end

---Resizes a miniwindow
---@param WindowName string
---@param Width number
---@param Height number
---@param BackgroundColour number
---@return number
function WindowResize(WindowName, Width, Height, BackgroundColour) end

---Adds a scroll-wheel handler to a miniwindow hotspot
---@param WindowName string
---@param HotspotId string
---@param MoveCallback string
---@return number
function WindowScrollwheelHandler(WindowName, HotspotId, MoveCallback) end

---Sets a single pixel in a miniwindow to the specified colour
---@param WindowName string
---@param x number
---@param y number
---@param Colour number
---@return number
function WindowSetPixel(WindowName, x, y, Colour) end

---Sets the Z-Order for a miniwindow
---@param WindowName string
---@param Order number
---@return number
function WindowSetZOrder(WindowName, Order) end

---Shows or hides a miniwindow
---@param WindowName string
---@param Show boolean
---@return number
function WindowShow(WindowName, Show) end

---Draws text into a miniwindow
---@param WindowName string
---@param FontId string
---@param Text string
---@param Left number
---@param Top number
---@param Right number
---@param Bottom number
---@param Colour number
---@param Unicode boolean
---@return number
function WindowText(WindowName, FontId, Text, Left, Top, Right, Bottom, Colour, Unicode) end

---Calculates the width of text in a miniwindow
---@param WindowName string
---@param FontId string
---@param Text string
---@param Unicode boolean
---@return number
function WindowTextWidth(WindowName, FontId, Text, Unicode) end

---Draws an image into a miniwindow with optional rotation, scaling, reflection and shearing
---@param WindowName string
---@param ImageId string
---@param Left nil
---@param Top nil
---@param Mode number
---@param Mxx nil
---@param Mxy nil
---@param Myx nil
---@param Myy nil
---@return number
function WindowTransformImage(WindowName, ImageId, Left, Top, Mode, Mxx, Mxy, Myx, Myy) end

---Writes the contents of a miniwindow to disk as a graphics file
---@param WindowName string
---@param FileName string
---@return number
function WindowWrite(WindowName, FileName) end

---Returns the TCP/IP address of the current world.
---@return string
function WorldAddress() end

---Gets the world's name
---@return string
function WorldName() end

---Returns the port number of the current world.
---@return number
function WorldPort() end

---Writes to the log file
---@param Message string
---@return number
function WriteLog(Message) end
