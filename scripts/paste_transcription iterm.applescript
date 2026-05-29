on run argv
	set delayOne to 0.2
	set routeSlot to ""

	if (count of argv) > 0 then
		set routeSlot to item 1 of argv
	end if

	tell application "iTerm2" to activate
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
