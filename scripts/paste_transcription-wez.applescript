set delayOne to 0.25
set focusDelay to 0.35

tell application "WezTerm" to activate
delay delayOne

tell application "System Events"
	repeat 15 times
		if exists application process "WezTerm" then
			if frontmost of application process "WezTerm" then exit repeat
		end if
		delay 0.1
	end repeat
	delay focusDelay

	keystroke "v" using command down
	delay focusDelay

	key code 36
	delay delayOne
end tell
