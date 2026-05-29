on run argv
	set delayOne to 0.25
	set targetAppName to "Codex"

	if (count of argv) > 0 then
		set targetAppName to item 1 of argv
	end if

	try
		tell application id "com.openai.codex" to activate
	on error
		tell application targetAppName to activate
	end try

	delay 0.45

	tell application "System Events"
		if exists process "Codex" then
			set frontmost of process "Codex" to true
		end if
		delay delayOne
		keystroke "v" using command down
		delay delayOne
		key code 36
	end tell
end run
