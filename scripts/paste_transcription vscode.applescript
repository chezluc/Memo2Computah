set delayOne to 0.2

tell application "Visual Studio Code" to activate
delay delayOne

tell application "System Events"
	keystroke "v" using command down
	delay delayOne
end tell
