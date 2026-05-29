set delayOne to 0.2
set pageDelay to 2

set projectPath to "/Users/garnetuniverse/Dropbox/auto.transcribe.agent"
set launchCommand to "cd " & quoted form of projectPath & " && ./scripts/start_mobile_recorder_tmux.sh && tmux attach -t mobile-recorder"

set the clipboard to launchCommand

-- bring "Terminal" to the front
tell application "Terminal" to activate
delay delayOne

tell application "System Events"
	keystroke "n" using command down
	delay delayOne
	keystroke "v" using command down
	delay delayOne
	key code 36
	delay pageDelay
end tell
