set delayOne to 0.2
set pageDelay to 2

tell application "Mail" to activate
delay delayOne

tell application "System Events"
	keystroke "v" using command down
	delay delayOne
end tell
