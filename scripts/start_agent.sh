#!/bin/bash

# Start script for auto-transcribe agent
cd "$(dirname "$0")"

watch_path="${AUTO_TRANSCRIBE_BASE_PATH:-$HOME/Dropbox/auto.transcribe.agent}"

if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
  C_RESET=$'\033[0m'
  C_PANEL=$'\033[38;5;45m'
  C_LABEL=$'\033[38;5;117m'
  C_VALUE=$'\033[38;5;195m'
else
  C_RESET=""
  C_PANEL=""
  C_LABEL=""
  C_VALUE=""
fi

cat <<EOF
${C_PANEL}+--------------------------------------------------------------+${C_RESET}
${C_PANEL}|${C_RESET} ${C_LABEL}AUTO.TRANSCRIBE.AGENT :: BOOTSTRAP${C_RESET}                           ${C_PANEL}|${C_RESET}
${C_PANEL}+--------------------------------------------------------------+${C_RESET}
${C_PANEL}|${C_RESET} ${C_LABEL}STATUS${C_RESET}   ${C_PANEL}|${C_RESET} ${C_VALUE}INIT${C_RESET}                                               ${C_PANEL}|${C_RESET}
${C_PANEL}|${C_RESET} ${C_LABEL}WATCH${C_RESET}    ${C_PANEL}|${C_RESET} ${C_VALUE}$watch_path${C_RESET} ${C_PANEL}|${C_RESET}
${C_PANEL}|${C_RESET} ${C_LABEL}MODE${C_RESET}     ${C_PANEL}|${C_RESET} ${C_VALUE}FOREGROUND ROUTER${C_RESET}                                  ${C_PANEL}|${C_RESET}
${C_PANEL}|${C_RESET} ${C_LABEL}CONTROL${C_RESET}  ${C_PANEL}|${C_RESET} ${C_VALUE}CTRL+C TO STOP${C_RESET}                                     ${C_PANEL}|${C_RESET}
${C_PANEL}+--------------------------------------------------------------+${C_RESET}
${C_PANEL}|${C_RESET} ${C_LABEL}CHANNELS${C_RESET} ${C_PANEL}|${C_RESET} ${C_VALUE}DROPBOX / CLIPBOARD / APPLEScript ROUTING${C_RESET}          ${C_PANEL}|${C_RESET}
${C_PANEL}+--------------------------------------------------------------+${C_RESET}

EOF

# Run the agent script
AUTO_TRANSCRIBE_BASE_PATH="$watch_path" ./auto_transcribe_agent.sh
