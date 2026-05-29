on run argv
	set delayOne to 0.2

	if (count of argv) is 0 then
		error "Missing target application name."
	end if

	set targetApp to item 1 of argv
	set routeSlot to ""
	if (count of argv) > 1 then
		set routeSlot to item 2 of argv
	end if

	tell application targetApp to activate
	delay delayOne

	tell application "System Events"
		if routeSlot is not "" then
			keystroke routeSlot using command down
			delay delayOne
		end if
	end tell
end run
