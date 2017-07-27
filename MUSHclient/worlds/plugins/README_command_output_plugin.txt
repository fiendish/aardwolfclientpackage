Documentation for the Aardwolf VI Command Output plugin (file name aard_VI_command_output.xml).

This plugin creates a special command prefix that, when used in front of a normal game command, will (to the best of its ability) capture the output from the server associated with the command you gave.
The command prefix is "MC command" or "mc command" (not case sensitive). A way to remember this is that M and C stand for "Mush Capture", and "command" for "send the following command".
So, for example, if you type "MC command worth", it will send "worth" to the game which sends back to you a report of your current gold, quest points, and trivia points. The entire output of the worth command will get captured, kept away from the main output area, and sent over to a MUSHclient notepad.
Having the command output printed into a MUSHclient notepad allows you to navigate the information the same way you would if it were a plain text file.
Once done, just press Ctrl+W to close the notepad and go back to the game.

Additional Notes:
For technical reasons, because the plugin signals the start and end of your command output to itself using multiple consecutive server commands, it is possible that random game output can accidentally insert itself at the beginning or end of your captured result. This is, as far as Fiendish knows, unavoidable at the time of writing this. It should also probably be pretty rare and have insignificant impact.
