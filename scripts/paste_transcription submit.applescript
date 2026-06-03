on run argv
	set focusDelay to 0.15
	set pasteDelay to 0.65

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

	tell application "System Events"
		repeat 20 times
			if exists application process targetApp then
				if frontmost of application process targetApp then exit repeat
			end if
			delay focusDelay
		end repeat

		if targetApp is "Codex" then
			if exists process "Codex" then
				set frontmost of process "Codex" to true
				delay focusDelay
			end if
		end if

		if routeSlot is not "" then
			my performRouteShortcut(routeSlot)
			delay 0.35
		end if

		keystroke "v" using command down
		delay pasteDelay

		if exists application process targetApp then
			set frontmost of application process targetApp to true
			delay focusDelay
		end if

		key code 36
		delay focusDelay
	end tell
end run

on performRouteShortcut(routeSlot)
	tell application "System Events"
		if routeSlot is "option-command-left" then
			key code 123 using {option down, command down}
		else if routeSlot is "option-command-right" then
			key code 124 using {option down, command down}
		else
			keystroke routeSlot using command down
		end if
	end tell
end performRouteShortcut
