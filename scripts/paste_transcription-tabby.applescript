set delayOne to 0.25
set focusDelay to 0.35

tell application "Tabby" to activate
delay delayOne

tell application "System Events"
	repeat 15 times
		if exists application process "Tabby" then
			if frontmost of application process "Tabby" then exit repeat
		end if
		delay 0.1
	end repeat
	delay focusDelay

	keystroke "v" using command down
	delay focusDelay

	key code 36
	delay delayOne
end tell
