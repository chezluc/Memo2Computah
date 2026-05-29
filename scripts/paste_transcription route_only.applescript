on run argv
	set delayOne to 0.25

	if (count of argv) is 0 then
		error "Missing target application name."
	end if

	set targetApp to item 1 of argv
	set routeSlot to ""
	if (count of argv) > 1 then
		set routeSlot to item 2 of argv
	end if

	if targetApp is "Codex" then
		try
			tell application id "com.openai.codex" to activate
		on error
			tell application targetApp to activate
		end try
	else
		tell application targetApp to activate
	end if
	repeat 10 times
		tell application "System Events"
			if exists application process targetApp then
				if frontmost of application process targetApp then exit repeat
			end if
		end tell
		delay 0.1
	end repeat
	delay delayOne

	tell application "System Events"
		if targetApp is "Codex" then
			if exists process "Codex" then
				set frontmost of process "Codex" to true
				delay delayOne
			end if
		end if

		if routeSlot is not "" then
			keystroke routeSlot using command down
			delay delayOne
		end if

		keystroke "v" using command down
		delay delayOne
	end tell
end run
