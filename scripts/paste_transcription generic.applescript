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

	tell application targetApp to activate
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
		if routeSlot is not "" then
			keystroke routeSlot using command down
			delay delayOne
		end if

		keystroke "v" using command down
		delay delayOne

		key code 36
		delay delayOne
	end tell
end run
