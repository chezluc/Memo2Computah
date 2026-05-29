set delayOne to 0.2

tell application "Google Chrome" to activate
delay delayOne

tell application "System Events"
	keystroke "v" using command down
	delay delayOne
	key code 36
	delay delayOne
end tell
