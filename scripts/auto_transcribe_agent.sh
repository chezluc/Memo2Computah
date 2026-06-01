#!/usr/bin/env bash

# Auto-transcribe agent script
set +e +u
set +o pipefail 2>/dev/null || true
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

base_path="${AUTO_TRANSCRIBE_BASE_PATH:-$HOME/Dropbox/auto.transcribe.agent}"
watch_folder="${AUTO_TRANSCRIBE_WATCH_FOLDER:-$base_path}"
downloads_backup_folder="${DOWNLOADS_BACKUP_FOLDER:-}"
downloads_backup_min_age="${DOWNLOADS_BACKUP_MIN_AGE:-10}"
processed_folder="$watch_folder/processed"
transcriptions_folder="$watch_folder/transcriptions"
temp_transcriptions_folder="$watch_folder/transcriptions_tmp"
responses_folder="$watch_folder/responses"
routes_config_file="$base_path/config/routes.json"
transcription_config_file="$base_path/config/transcription.env"
app_support_dir="${WATCHER_APP_SUPPORT_DIR:-$HOME/Library/Application Support/auto.transcribe.agent}"
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-$app_support_dir/pycache}"
log_dir="${WATCHER_LOG_DIR:-$app_support_dir/logs}"
log_file="$log_dir/processed_files.log"
default_applescript_path="$base_path/scripts/paste_transcription pasteboard.applescript"
tmux_response_target="${VOICE_RETURN_TMUX_TARGET:-voice_return}"
state_dir="${WATCHER_STATE_DIR:-$app_support_dir/state}"
status_file="$state_dir/watcher_status.json"
pid_file="$state_dir/watcher.pid"
skip_file="$state_dir/skip_current.flag"

if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    C_RESET=$'\033[0m'
    C_PANEL=$'\033[38;5;45m'
    C_LABEL=$'\033[38;5;117m'
    C_VALUE=$'\033[38;5;195m'
    C_OK=$'\033[38;5;83m'
    C_WARN=$'\033[38;5;214m'
    C_ERR=$'\033[38;5;203m'
else
    C_RESET=""
    C_PANEL=""
    C_LABEL=""
    C_VALUE=""
    C_OK=""
    C_WARN=""
    C_ERR=""
fi

# Map spoken trigger word to AppleScript filename
get_app_script() {
    case "$1" in
        *claude*|*clawed*) echo "paste_transcription.applescript" ;;
        *codex*|*code\ x*) echo "paste_transcription codex.applescript" ;;
        *google\ chrome*|*chrome*) echo "paste_transcription chrome.applescript" ;;
        *iterm*|*i\ term*|*i\ turn*|main*|may*) echo "paste_transcription iterm.applescript" ;;
        *terminal*) echo "paste_transcription term.applescript" ;;
        *kitty*) echo "paste_transcription-kitty.applescript" ;;
        *tabby*|*taby*) echo "paste_transcription-tabby.applescript" ;;
        *termius*) echo "paste_transcription-termius.applescript" ;;
        *wezterm*|*western*|*wez*) echo "paste_transcription-wez.applescript" ;;
        *iawriter*|*ia\ writer*|*i\ a\ writer*|*writer*|*compose*) echo "paste_transcription iawriter.applescript" ;;
        *chatgpt*|*chat\ gpt*|*chat\ g\ p\ t*|gpt) echo "paste_transcription chatgpt.applescript" ;;
        *messages*|*message*) echo "paste_transcription messages.applescript" ;;
        *whatsapp*|*whats\ app*) echo "paste_transcription whatsapp.applescript" ;;
        *mail*|*email*) echo "paste_transcription mail.applescript" ;;
        *cursor*) echo "paste_transcription cursor.applescript" ;;
        *textedit*|*text\ edit*|text) echo "paste_transcription textedit.applescript" ;;
        *vscode*|*vs\ code*|*visual\ studio*|code) echo "paste_transcription vscode.applescript" ;;
        *pasteboard*|*clipboard*|paste|copy) echo "paste_transcription pasteboard.applescript" ;;
        *) echo "" ;;
    esac
}

get_app_target() {
    case "$1" in
        *claude*|*clawed*) echo "Claude" ;;
        *codex*|*code\ x*) echo "Codex" ;;
        *google\ chrome*|*chrome*) echo "Google Chrome" ;;
        *iterm*|*i\ term*|*i\ turn*|main*|may*) echo "iTerm2" ;;
        *terminal*) echo "Terminal" ;;
        *kitty*) echo "kitty" ;;
        *tabby*|*taby*) echo "Tabby" ;;
        *termius*) echo "Termius" ;;
        *wezterm*|*western*|*wez*) echo "WezTerm" ;;
        *iawriter*|*ia\ writer*|*i\ a\ writer*|*writer*|*compose*) echo "iA Writer" ;;
        *chatgpt*|*chat\ gpt*|*chat\ g\ p\ t*|gpt) echo "ChatGPT" ;;
        *messages*|*message*) echo "Messages" ;;
        *whatsapp*|*whats\ app*) echo "WhatsApp" ;;
        *mail*|*email*) echo "Mail" ;;
        *cursor*) echo "Cursor" ;;
        *textedit*|*text\ edit*|text) echo "TextEdit" ;;
        *vscode*|*vs\ code*|*visual\ studio*|code) echo "Visual Studio Code" ;;
        *pasteboard*|*clipboard*|paste|copy) echo "" ;;
        *) echo "" ;;
    esac
}

get_config_route_field() {
    local route_id="$1"
    local field="$2"
    python3 - "$routes_config_file" "$route_id" "$field" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
route_id = sys.argv[2].strip().lower()
field = sys.argv[3]

try:
    data = json.loads(config_path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(0)

for route in data.get("routes", []):
    if str(route.get("id", "")).strip().lower() == route_id:
        value = route.get(field)
        if value is not None:
            print(str(value).strip())
        break
PY
}

get_route_override_script() {
    case "$1" in
        clipboard) echo "paste_transcription pasteboard.applescript" ;;
        codex) echo "paste_transcription codex.applescript" ;;
        plexi) echo "paste_transcription generic.applescript" ;;
        chrome) echo "paste_transcription chrome.applescript" ;;
        iawriter) echo "paste_transcription iawriter.applescript" ;;
        textedit) echo "paste_transcription textedit.applescript" ;;
        iterm|iterm:1|iterm:2|iterm:3|iterm:4) echo "paste_transcription iterm.applescript" ;;
        wezterm) echo "paste_transcription-wez.applescript" ;;
        kitty) echo "paste_transcription-kitty.applescript" ;;
        tabby) echo "paste_transcription-tabby.applescript" ;;
        termius) echo "paste_transcription-termius.applescript" ;;
        *)
            local configured_target configured_kind
            configured_target=$(get_config_route_field "$1" "target")
            configured_kind=$(get_config_route_field "$1" "kind")
            if [[ "$configured_kind" == "clipboard" ]]; then
                echo "paste_transcription pasteboard.applescript"
            elif [[ "$configured_kind" == "app" && -n "$configured_target" ]]; then
                echo "paste_transcription generic.applescript"
            else
                echo ""
            fi
            ;;
    esac
}

get_route_override_target() {
    case "$1" in
        clipboard) echo "" ;;
        codex) echo "Codex" ;;
        plexi) echo "Plexi" ;;
        chrome) echo "Google Chrome" ;;
        iawriter) echo "iA Writer" ;;
        textedit) echo "TextEdit" ;;
        iterm|iterm:1|iterm:2|iterm:3|iterm:4) echo "iTerm2" ;;
        wezterm) echo "WezTerm" ;;
        kitty) echo "kitty" ;;
        tabby) echo "Tabby" ;;
        termius) echo "Termius" ;;
        *)
            if [[ "$(get_config_route_field "$1" "kind")" == "app" ]]; then
                get_config_route_field "$1" "target"
            else
                echo ""
            fi
            ;;
    esac
}

process_control_file() {
    local control_file="$1"
    local timestamp control_action route_override target_app route_shortcut

    timestamp=$(date "+%Y%m%d_%H%M%S")
    route_override=$(python3 - "$control_file" <<'PY'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    print((data.get("route_target") or "").strip())
except Exception:
    print("")
PY
)

    if [[ -z "$route_override" || "$route_override" == "clipboard" ]]; then
        mv "$control_file" "$processed_folder/${timestamp}_$(basename "$control_file")"
        echo "${C_WARN}⚠️ Ignored control file:${C_RESET} $(basename "$control_file")"
        return
    fi

    target_app=$(get_route_override_target "$route_override")
    route_shortcut=$(get_route_override_shortcut "$route_override")

    if [[ -z "$target_app" ]]; then
        mv "$control_file" "$processed_folder/${timestamp}_$(basename "$control_file")"
        echo "${C_WARN}⚠️ Unknown control target:${C_RESET} ${route_override}"
        return
    fi

    echo "${C_OK}⚡ Activating target:${C_RESET} ${target_app}${route_shortcut:+ (${route_shortcut})}"
    if [[ -n "$route_shortcut" ]]; then
        osascript "$base_path/scripts/activate_target.applescript" "$target_app" "$route_shortcut"
    else
        osascript "$base_path/scripts/activate_target.applescript" "$target_app"
    fi

    mv "$control_file" "$processed_folder/${timestamp}_$(basename "$control_file")"
}

get_route_override_shortcut() {
    case "$1" in
        iterm:1) echo "1" ;;
        iterm:2) echo "2" ;;
        iterm:3) echo "3" ;;
        iterm:4) echo "4" ;;
        *) get_config_route_field "$1" "shortcut" ;;
    esac
}

is_main_route() {
    case "$1" in
        *iterm*|*i\ term*|*i\ turn*|main*|may*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

extract_route_shortcut() {
    local normalized="$1"
    case "$normalized" in
        *" number 1 "*|*" window 1 "*|*" tab 1 "*|*" number one "*|*" window one "*|*" tab one "*|*" number one"|*" window one"|*" tab one"|*" number 1"|*" window 1"|*" tab 1"|one|1)
            echo "1"
            ;;
        *" number 2 "*|*" window 2 "*|*" tab 2 "*|*" number two "*|*" window two "*|*" tab two "*|*" number two"|*" window two"|*" tab two"|*" number 2"|*" window 2"|*" tab 2"|two|2)
            echo "2"
            ;;
        *" number 3 "*|*" window 3 "*|*" tab 3 "*|*" number three "*|*" window three "*|*" tab three "*|*" number three"|*" window three"|*" tab three"|*" number 3"|*" window 3"|*" tab 3"|three|3)
            echo "3"
            ;;
        *" number 4 "*|*" window 4 "*|*" tab 4 "*|*" number four "*|*" window four "*|*" tab four "*|*" number for "*|*" window for "*|*" tab for "*|*" number four"|*" window four"|*" tab four"|*" number for"|*" window for"|*" tab for"|*" number 4"|*" window 4"|*" tab 4"|four|for|4)
            echo "4"
            ;;
        *" number 5 "*|*" window 5 "*|*" tab 5 "*|*" number five "*|*" window five "*|*" tab five "*|*" number five"|*" window five"|*" tab five"|*" number 5"|*" window 5"|*" tab 5"|five|5)
            echo "5"
            ;;
        *" number 6 "*|*" window 6 "*|*" tab 6 "*|*" number six "*|*" window six "*|*" tab six "*|*" number six"|*" window six"|*" tab six"|*" number 6"|*" window 6"|*" tab 6"|six|6)
            echo "6"
            ;;
        *" number 7 "*|*" window 7 "*|*" tab 7 "*|*" number seven "*|*" window seven "*|*" tab seven "*|*" number seven"|*" window seven"|*" tab seven"|*" number 7"|*" window 7"|*" tab 7"|seven|7)
            echo "7"
            ;;
        *" number 8 "*|*" window 8 "*|*" tab 8 "*|*" number eight "*|*" window eight "*|*" tab eight "*|*" number eight"|*" window eight"|*" tab eight"|*" number 8"|*" window 8"|*" tab 8"|eight|8)
            echo "8"
            ;;
        *" number 9 "*|*" window 9 "*|*" tab 9 "*|*" number nine "*|*" window nine "*|*" tab nine "*|*" number nine"|*" window nine"|*" tab nine"|*" number 9"|*" window 9"|*" tab 9"|nine|9)
            echo "9"
            ;;
        *)
            echo ""
            ;;
    esac
}

normalize_text() {
    printf '%s' "$1" \
        | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cd '[:alnum:] ' \
        | tr -s ' ' \
        | sed -E 's/^ +| +$//g'
}

contains_route_marker() {
    local normalized="$1"
    case "$normalized" in
        *" thank you "*|thank\ you*|*" thank you"|\
        *" gracias "*|gracias*|*" gracias"|\
        *" obrigado "*|obrigado*|*" obrigado"|\
        *" obrigada "*|obrigada*|*" obrigada"|\
        *" merci "*|merci*|*" merci"|\
        *" danke "*|danke*|*" danke"|\
        *" grazie "*|grazie*|*" grazie"|\
        *" arigato "*|arigato*|*" arigato"|\
        *" arigatou "*|arigatou*|*" arigatou"|\
        *" xie xie "*|xie\ xie*|*" xie xie")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

get_route_marker_prefix() {
    local text="$1"
    local audio_path="${2:-}"
    python3 - "$text" "$audio_path" "$ROUTE_MARKER_MAX_SECONDS" "$ROUTE_MARKER_FALLBACK_MAX_WORDS" <<'PY'
import re
import subprocess
import sys
import unicodedata

text, audio_path, max_seconds, fallback_max_words = sys.argv[1:]
try:
    max_seconds = float(max_seconds)
except ValueError:
    max_seconds = 10.0
try:
    fallback_max_words = int(fallback_max_words)
except ValueError:
    fallback_max_words = 35

markers = [
    "thank you",
    "gracias",
    "obrigado",
    "obrigada",
    "merci",
    "danke",
    "grazie",
    "arigato",
    "arigatou",
    "xie xie",
]

def normalize(value):
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    value = re.sub(r"[^A-Za-z0-9 ]+", " ", value).lower()
    return re.sub(r"\s+", " ", value).strip()

def audio_duration_seconds(path):
    if not path:
        return None
    try:
        output = subprocess.check_output(["afinfo", path], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return None
    match = re.search(r"estimated duration:\s*([0-9.]+)\s*sec", output)
    if not match:
        return None
    try:
        return float(match.group(1))
    except ValueError:
        return None

normalized = normalize(text)
if not normalized:
    sys.exit(1)

pattern = re.compile(r"\b(" + "|".join(re.escape(marker) for marker in markers) + r")\b")
match = pattern.search(normalized)
if not match:
    sys.exit(1)

prefix = normalized[:match.start()].strip()
words_before = len(re.findall(r"\b\w+\b", prefix))
duration = audio_duration_seconds(audio_path)

if duration and duration > 0:
    total_words = max(1, len(re.findall(r"\b\w+\b", normalized)))
    estimated_marker_seconds = (words_before / total_words) * duration
    if estimated_marker_seconds > max_seconds:
        sys.exit(1)
elif words_before > fallback_max_words:
    sys.exit(1)

print(prefix)
PY
}

strip_to_route_content() {
    python3 - "$1" <<'PY'
import re
import sys
import unicodedata

markers = [
    "thank you",
    "gracias",
    "obrigado",
    "obrigada",
    "merci",
    "danke",
    "grazie",
    "arigato",
    "arigatou",
    "xie xie",
]

text = sys.argv[1]
normalized = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii").lower()
for marker in markers:
    pattern = re.compile(rf".*?\b{re.escape(marker)}\b[.,:;!?-]*\s*", re.IGNORECASE | re.DOTALL)
    if pattern.search(normalized):
        prefix_match = pattern.match(normalized)
        if prefix_match:
            print(text[prefix_match.end():].lstrip())
            raise SystemExit(0)
print(text)
PY
}

strip_main_route_content() {
    python3 - "$1" <<'PY'
import re
import sys

text = sys.argv[1]
pattern = re.compile(
    r"^\s*(main|may|iterm|i term|i turn)"
    r"(?:\s+(?:number|window|tab)\s+(?:one|two|three|four|for|five|six|seven|eight|nine|[1-9]))?"
    r"[.,:;!?-]*\s*",
    re.IGNORECASE,
)
match = pattern.match(text)
if match:
    print(text[match.end():].lstrip())
else:
    print(text)
PY
}

# Model selection.
# The live watcher only accepts tiny or base. No hidden base.en fallback.
WHISPER_MODEL="${WHISPER_MODEL:-}"
WHISPER_LANGUAGE="${WHISPER_LANGUAGE:-auto}"
WHISPER_BEAM_SIZE="${WHISPER_BEAM_SIZE:-5}"
WHISPER_TEMPERATURE="${WHISPER_TEMPERATURE:-0}"
WHISPER_CONDITION_ON_PREVIOUS_TEXT="${WHISPER_CONDITION_ON_PREVIOUS_TEXT:-False}"
WHISPER_INITIAL_PROMPT="${WHISPER_INITIAL_PROMPT:-Voice command dictation. Preserve the original spoken language; do not translate. Preserve names, app names, and spelled-out letters exactly when possible. Routing terms include Codex, Claude Code, iA Writer, iTerm, WezTerm, Kitty, Tabby, Google Chrome, TextEdit, Messages, WhatsApp, Mail, Cursor, clipboard. Common phrases include thank you, main thank you, main number one, main number two, main number three, compose thank you.}"
WHISPER_TIMEOUT_SECONDS="${WHISPER_TIMEOUT_SECONDS:-180}"
ROUTE_MARKER_MAX_SECONDS="${ROUTE_MARKER_MAX_SECONDS:-10}"
ROUTE_MARKER_FALLBACK_MAX_WORDS="${ROUTE_MARKER_FALLBACK_MAX_WORDS:-35}"

load_transcription_settings() {
    local configured_model
    configured_model=""

    if [[ -f "$transcription_config_file" ]]; then
        configured_model=$(awk -F= '
            $1 == "WHISPER_MODEL" {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                gsub(/^"|"$/, "", $2)
                print $2
                exit
            }
        ' "$transcription_config_file" 2>/dev/null)
    fi

    if [[ -n "$configured_model" ]]; then
        WHISPER_MODEL="$configured_model"
    fi

    case "$WHISPER_MODEL" in
        tiny|base)
            ;;
        "")
            echo "${C_ERR}❌ WHISPER_MODEL is not set. Choose tiny or base in config/transcription.env.${C_RESET}"
            exit 64
            ;;
        *)
            echo "${C_ERR}❌ Invalid WHISPER_MODEL '$WHISPER_MODEL'. Allowed values: tiny, base.${C_RESET}"
            exit 64
            ;;
    esac
}

load_transcription_settings

# Create folders if they don't exist
mkdir -p "$processed_folder" "$transcriptions_folder" "$temp_transcriptions_folder" "$responses_folder" "$log_dir" "$state_dir"
touch "$log_file"
echo "$$" > "$pid_file"
rm -f "$skip_file"

shell_json_escape() {
    python3 - "$1" <<'PY'
import json, sys
print(json.dumps(sys.argv[1]))
PY
}

write_status() {
    local status="${1:-idle}"
    local current_file="${2:-}"
    local message="${3:-}"
    local last_route="${4:-}"
    local last_transcript="${5:-}"
    local queue_count="${6:-0}"
    local progress="${7:-0}"

    python3 - "$status_file" \
        "$status" "$current_file" "$message" "$last_route" "$last_transcript" "$queue_count" "$progress" \
        "$files_processed" "$watch_folder" "$$" "$WHISPER_MODEL" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

status_path, status, current_file, message, last_route, last_transcript, queue_count, progress, files_processed, watch_folder, pid, whisper_model = sys.argv[1:]
data = {
    "status": status,
    "currentFile": current_file,
    "message": message,
    "lastRoute": last_route,
    "lastTranscriptPreview": last_transcript,
    "queueCount": int(queue_count or 0),
    "progress": max(0.0, min(1.0, float(progress or 0))),
    "filesProcessed": int(files_processed or 0),
    "watchFolder": watch_folder,
    "pid": int(pid or 0),
    "whisperModel": whisper_model,
    "updatedAt": datetime.now(timezone.utc).isoformat(),
}
os.makedirs(os.path.dirname(status_path), exist_ok=True)
with open(status_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY
}

cleanup_status() {
    local exit_status=$?
    echo "${C_WARN}🛑 Watcher exiting:${C_RESET} status=${exit_status} at $(date '+%Y-%m-%d %H:%M:%S')"
    write_status "stopped" "" "Watcher stopped (exit ${exit_status})" "" "" "0"
    rm -f "$pid_file"
}

trap cleanup_status EXIT
trap 'echo "${C_WARN}🛑 Signal received:${C_RESET} INT"; exit 130' INT
trap 'echo "${C_WARN}🛑 Signal received:${C_RESET} TERM"; exit 143' TERM
trap 'echo "${C_WARN}🛑 Signal received:${C_RESET} HUP"; exit 129' HUP

sweep_downloads_backup() {
    [[ -n "$downloads_backup_folder" ]] || return 0
    [[ -d "$downloads_backup_folder" ]] || return 0
    local cutoff f target base ext stamp
    cutoff=$(date -v-"${downloads_backup_min_age}"S -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || return 0
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        base=$(basename "$f")
        ext="${base##*.}"
        target="$watch_folder/$base"
        if [[ -e "$target" ]]; then
            stamp=$(date "+%Y%m%d_%H%M%S")
            target="$watch_folder/${base%.*}_${stamp}.${ext}"
        fi
        if mv "$f" "$target" 2>/dev/null; then
            echo "${C_OK}📥 Imported from Downloads:${C_RESET} $(basename "$target")"
        fi
    done < <(find "$downloads_backup_folder" -maxdepth 1 -type f \
        -iname '*.m4a' \
        ! -newermt "$cutoff" \
        2>/dev/null)
}

# Function to check if file is stable
is_file_stable() {
    local file="$1"
    local size1 size2
    size1=$(stat -f%z "$file")
    sleep "${FILE_STABLE_WAIT:-0.5}"
    size2=$(stat -f%z "$file")
    [[ "$size1" -eq "$size2" ]]
}

send_to_tmux_response_target() {
    local text="$1"

    if ! tmux has-session -t "$tmux_response_target" 2>/dev/null; then
        return 1
    fi

    # Mirror voice-to-tmux: send literal text directly into tmux, then submit.
    tmux send-keys -t "$tmux_response_target" -l "$text"
    tmux send-keys -t "$tmux_response_target" Enter
}

read_text_job_field() {
    local text_file="$1"
    local field="$2"
    python3 - "$text_file" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1:3]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    value = data.get(field, "")
    if isinstance(value, bool):
        print("true" if value else "false")
    elif value is None:
        print("")
    else:
        print(str(value))
except Exception:
    print("")
PY
}

process_text_job_file() {
    local text_file="$1"
    local filename timestamp job_id base_name job_output_dir transcript_file transcript_content
    local applescript_path should_route target_app submit_after_paste route_override response_mode
    local response_json_path response_before_file capture_text_response normalized_transcript pre_thank_you
    local route_marker_prefix
    local matched_script route_shortcut has_thank_you allow_without_thank_you spoken_matched_script
    local spoken_target_app spoken_route_shortcut routed_transcript_file final_transcript_file transcript_preview

    while ! is_file_stable "$text_file"; do
        echo "${C_WARN}⏳ Text job still uploading:${C_RESET} $(basename "$text_file")"
        sleep 1
    done

    filename=$(basename "$text_file")
    timestamp=$(date "+%Y%m%d_%H%M%S")
    job_id=$(read_text_job_field "$text_file" "job_id")
    if [[ -z "$job_id" ]]; then
        job_id="${filename%.text.json}"
    fi
    base_name="$job_id"
    transcript_content=$(read_text_job_field "$text_file" "message")

    if [[ -z "$(printf '%s' "$transcript_content" | tr -d '[:space:]')" ]]; then
        echo "${C_ERR}❌ Empty typed message:${C_RESET} $filename"
        mv "$text_file" "$processed_folder/${timestamp}_${filename}"
        write_status "error" "$filename" "Typed message was empty" "" "" "$queue_count"
        return
    fi

    job_output_dir="$temp_transcriptions_folder/${base_name}_${timestamp}"
    mkdir -p "$job_output_dir"
    transcript_file="$job_output_dir/${base_name}.txt"
    printf '%s' "$transcript_content" > "$transcript_file"

    echo "${C_LABEL}⌨️ Processing typed message:${C_RESET} ${C_VALUE}$filename${C_RESET}"
    write_status "routing" "$filename" "Routing typed message" "" "" "$queue_count"

    applescript_path="$default_applescript_path"
    should_route=false
    target_app=""
    submit_after_paste=true
    route_override="$(read_text_job_field "$text_file" "route_target")"
    response_mode="$(read_text_job_field "$text_file" "response_mode" | tr '[:upper:]' '[:lower:]')"
    response_json_path=""
    response_before_file=""
    capture_text_response=false

    if [[ "$(read_text_job_field "$text_file" "submit_after_paste")" == "false" ]]; then
        submit_after_paste=false
    fi

    normalized_transcript=$(normalize_text "$transcript_content")
    pre_thank_you="$normalized_transcript"
    matched_script=""
    target_app=""
    route_shortcut=""
    has_thank_you=false
    allow_without_thank_you=false
    spoken_matched_script=$(get_app_script "$pre_thank_you")
    spoken_target_app=$(get_app_target "$pre_thank_you")
    spoken_route_shortcut=""

    if [[ "$spoken_target_app" == "iTerm2" ]]; then
        spoken_route_shortcut=$(extract_route_shortcut "$pre_thank_you")
    fi
    if route_marker_prefix=$(get_route_marker_prefix "$transcript_content"); then
        has_thank_you=true
        pre_thank_you="$route_marker_prefix"
        spoken_matched_script=$(get_app_script "$pre_thank_you")
        spoken_target_app=$(get_app_target "$pre_thank_you")
        spoken_route_shortcut=""
        if [[ "$spoken_target_app" == "iTerm2" ]]; then
            spoken_route_shortcut=$(extract_route_shortcut "$pre_thank_you")
        fi
    fi
    if is_main_route "$pre_thank_you" && [[ -n "$spoken_route_shortcut" ]]; then
        allow_without_thank_you=true
    fi

    if [[ -n "$route_override" ]]; then
        matched_script=$(get_route_override_script "$route_override")
        target_app=$(get_route_override_target "$route_override")
        route_shortcut=$(get_route_override_shortcut "$route_override")
        if [[ -n "$matched_script" ]]; then
            if [[ "$route_override" == "clipboard" ]]; then
                should_route=false
                applescript_path="$default_applescript_path"
            elif $submit_after_paste; then
                applescript_path="$base_path/scripts/$matched_script"
            else
                applescript_path="$base_path/scripts/paste_transcription route_only.applescript"
            fi
            echo "${C_OK}🎯 Typed route override:${C_RESET} '${route_override}' ${C_LABEL}→${C_RESET} $(basename "$applescript_path")"
            if [[ "$route_override" != "clipboard" ]]; then
                should_route=true
            fi
        fi
    elif [[ -n "$spoken_matched_script" ]] && { $has_thank_you || $allow_without_thank_you; }; then
        matched_script="$spoken_matched_script"
        target_app="$spoken_target_app"
        route_shortcut="$spoken_route_shortcut"
        echo "${C_OK}🗣️ Typed route phrase:${C_RESET} '${pre_thank_you}'"
    else
        matched_script="$spoken_matched_script"
        target_app="$spoken_target_app"
        route_shortcut="$spoken_route_shortcut"
    fi

    if ! $should_route && { $has_thank_you || $allow_without_thank_you; } && [[ -n "$matched_script" ]]; then
        if $submit_after_paste; then
            applescript_path="$base_path/scripts/$matched_script"
        else
            applescript_path="$base_path/scripts/paste_transcription route_only.applescript"
        fi
        should_route=true
        echo "${C_OK}🎯 Detected typed app trigger phrase:${C_RESET} '${pre_thank_you}' ${C_LABEL}→${C_RESET} $(basename "$applescript_path")"
        if $has_thank_you; then
            transcript_content=$(strip_to_route_content "$transcript_content")
        elif $allow_without_thank_you; then
            transcript_content=$(strip_main_route_content "$transcript_content")
        fi
    elif ! $should_route && $has_thank_you; then
        transcript_content=$(strip_to_route_content "$transcript_content")
        echo "${C_WARN}📋 Route marker detected without a recognized app trigger phrase${C_RESET} ('${pre_thank_you}'). Leaving typed message on clipboard only."
    elif ! $should_route; then
        echo "${C_WARN}📋 No typed route marker detected.${C_RESET} Leaving typed message on clipboard only."
    fi

    routed_transcript_file="$job_output_dir/${base_name}.routed.txt"
    printf '%s' "$transcript_content" > "$routed_transcript_file"

    if [[ "$response_mode" == "text" ]]; then
        response_json_path="$responses_folder/${base_name}.response.json"
        python3 "$base_path/scripts/tmux_response_bridge.py" write \
            --output "$response_json_path" \
            --job-id "$base_name" \
            --audio-filename "$filename" \
            --route-target "${route_override:-$pre_thank_you}" \
            --route-label "${target_app:-clipboard}" \
            --transcript-file "$routed_transcript_file" \
            --status "waiting" \
            --message "Waiting for routed app response." \
            --source "tmux" \
            --target "$tmux_response_target" \
            >/dev/null 2>&1 || true
        echo "${C_LABEL}💬 Text response requested:${C_RESET} $(basename "$response_json_path")"
    fi

    echo "$transcript_content" | pbcopy
    echo "${C_OK}✅ Typed message copied to clipboard!${C_RESET}"
    transcript_preview=$(printf '%s' "$transcript_content" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | cut -c1-180)

    if $should_route; then
        echo "${C_LABEL}📋 Preparing routed send...${C_RESET}"
        write_status "routing" "$filename" "Routing typed message" "${target_app:-clipboard}" "$transcript_preview" "$queue_count"
        if [[ "$response_mode" == "text" && "$target_app" == "WezTerm" ]]; then
            response_before_file="$job_output_dir/${base_name}.tmux.before.txt"
            if python3 "$base_path/scripts/tmux_response_bridge.py" snapshot \
                --target "$tmux_response_target" \
                --output "$response_before_file" \
                >/dev/null 2>&1; then
                capture_text_response=true
            else
                python3 "$base_path/scripts/tmux_response_bridge.py" write \
                    --output "$response_json_path" \
                    --job-id "$base_name" \
                    --audio-filename "$filename" \
                    --route-target "${route_override:-wezterm}" \
                    --route-label "${target_app:-WezTerm}" \
                    --transcript-file "$routed_transcript_file" \
                    --status "error" \
                    --message "Could not capture tmux session '$tmux_response_target' before routing." \
                    --source "tmux" \
                    --target "$tmux_response_target" \
                    >/dev/null 2>&1 || true
            fi
        fi

        if [[ "$response_mode" == "text" && "$target_app" == "WezTerm" ]]; then
            echo "${C_LABEL}💬 Sending directly to tmux target:${C_RESET} ${tmux_response_target}"
            if ! send_to_tmux_response_target "$transcript_content"; then
                capture_text_response=false
                python3 "$base_path/scripts/tmux_response_bridge.py" write \
                    --output "$response_json_path" \
                    --job-id "$base_name" \
                    --audio-filename "$filename" \
                    --route-target "${route_override:-wezterm}" \
                    --route-label "${target_app:-WezTerm}" \
                    --transcript-file "$routed_transcript_file" \
                    --status "error" \
                    --message "Could not send text to tmux session '$tmux_response_target'." \
                    --source "tmux" \
                    --target "$tmux_response_target" \
                    >/dev/null 2>&1 || true
            fi
        elif $submit_after_paste; then
            if [[ -n "$target_app" && -n "$route_shortcut" ]]; then
                osascript "$base_path/scripts/paste_transcription submit.applescript" "$target_app" "$route_shortcut"
            elif [[ -n "$target_app" ]]; then
                osascript "$base_path/scripts/paste_transcription submit.applescript" "$target_app"
            elif [[ -n "$route_shortcut" ]]; then
                osascript "$applescript_path" "$route_shortcut"
            else
                osascript "$applescript_path"
            fi
        else
            if [[ -n "$route_shortcut" ]]; then
                osascript "$applescript_path" "$target_app" "$route_shortcut"
            else
                osascript "$applescript_path" "$target_app"
            fi
        fi

        if [[ "$response_mode" == "text" && "$capture_text_response" == true ]]; then
            echo "${C_LABEL}💬 Waiting for tmux response:${C_RESET} ${tmux_response_target}"
            python3 "$base_path/scripts/tmux_response_bridge.py" wait \
                --target "$tmux_response_target" \
                --before-file "$response_before_file" \
                --output "$response_json_path" \
                --job-id "$base_name" \
                --audio-filename "$filename" \
                --route-target "${route_override:-wezterm}" \
                --route-label "${target_app:-WezTerm}" \
                --transcript-file "$routed_transcript_file" \
                --stable-secs "${VOICE_RETURN_STABLE_SECS:-4}" \
                --timeout "${VOICE_RETURN_TIMEOUT:-120}" \
                >/dev/null 2>&1 || true
        elif [[ "$response_mode" == "text" && -n "$response_json_path" && "$target_app" != "WezTerm" ]]; then
            python3 "$base_path/scripts/tmux_response_bridge.py" write \
                --output "$response_json_path" \
                --job-id "$base_name" \
                --audio-filename "$filename" \
                --route-target "${route_override:-$pre_thank_you}" \
                --route-label "${target_app:-clipboard}" \
                --transcript-file "$routed_transcript_file" \
                --status "complete" \
                --message "Text responses are currently wired for WezTerm/tmux routes." \
                --source "tmux" \
                --target "$tmux_response_target" \
                >/dev/null 2>&1 || true
        fi
    else
        echo "${C_WARN}📋 Clipboard only. No routing step performed.${C_RESET}"
        if [[ "$response_mode" == "text" && -n "$response_json_path" ]]; then
            python3 "$base_path/scripts/tmux_response_bridge.py" write \
                --output "$response_json_path" \
                --job-id "$base_name" \
                --audio-filename "$filename" \
                --route-target "clipboard" \
                --route-label "Clipboard" \
                --transcript-file "$routed_transcript_file" \
                --status "complete" \
                --message "No route was selected, so no app response was captured." \
                --source "clipboard" \
                >/dev/null 2>&1 || true
        fi
    fi

    final_transcript_file="$transcriptions_folder/${base_name}_${timestamp}.txt"
    mv "$transcript_file" "$final_transcript_file"
    rmdir "$job_output_dir" 2>/dev/null || true
    mv "$text_file" "$processed_folder/${timestamp}_${filename}"
    echo "$timestamp: Processed typed message $filename -> ${base_name}_${timestamp}.txt" >> "$log_file"

    echo "${C_OK}📝 Saved typed message to:${C_RESET} ${final_transcript_file}"
    ((files_processed++))
    write_status "listening" "" "Last typed message processed" "${target_app:-clipboard}" "$transcript_preview" "$queue_count"
}

echo "${C_PANEL}+------------------------------------------------------------------+${C_RESET}"
echo "${C_PANEL}|${C_RESET} ${C_LABEL}AUTO.TRANSCRIBE.AGENT :: ACTIVE${C_RESET}                                  ${C_PANEL}|${C_RESET}"
echo "${C_PANEL}+------------------------------------------------------------------+${C_RESET}"
printf "${C_PANEL}|${C_RESET} ${C_LABEL}%-8s${C_RESET} ${C_PANEL}|${C_RESET} ${C_VALUE}%-54s${C_RESET} ${C_PANEL}|${C_RESET}\n" "WATCH" "$watch_folder"
if [[ "$WHISPER_LANGUAGE" == "auto" ]]; then
    printf "${C_PANEL}|${C_RESET} ${C_LABEL}%-8s${C_RESET} ${C_PANEL}|${C_RESET} ${C_VALUE}%-54s${C_RESET} ${C_PANEL}|${C_RESET}\n" "MODEL" "$WHISPER_MODEL / multilingual auto-detect"
else
    printf "${C_PANEL}|${C_RESET} ${C_LABEL}%-8s${C_RESET} ${C_PANEL}|${C_RESET} ${C_VALUE}%-54s${C_RESET} ${C_PANEL}|${C_RESET}\n" "MODEL" "$WHISPER_MODEL / language=$WHISPER_LANGUAGE"
fi
printf "${C_PANEL}|${C_RESET} ${C_LABEL}%-8s${C_RESET} ${C_PANEL}|${C_RESET} ${C_VALUE}%-54s${C_RESET} ${C_PANEL}|${C_RESET}\n" "ROUTING" "clipboard default / trigger phrases route to apps"
printf "${C_PANEL}|${C_RESET} ${C_LABEL}%-8s${C_RESET} ${C_PANEL}|${C_RESET} ${C_VALUE}%-54s${C_RESET} ${C_PANEL}|${C_RESET}\n" "CONTROL" "Ctrl+C to stop"
echo "${C_PANEL}+------------------------------------------------------------------+${C_RESET}"
write_status "starting" "" "Watcher starting" "" "" "0"

# Heartbeat settings
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-30}"
last_heartbeat=$(date +%s)
last_idle_status_write=0
files_processed=0
heartbeat_index=0
heartbeat_frames=("SCAN" "SYNC" "LISTEN" "ROUTE")
heartbeat_glyphs=("◢◣◤◥" "▚▞▚▞" "◐◓◑◒" "◇◆◇◆")

while true; do
    found_files=false
    sweep_downloads_backup
    queue_count=$(find "$watch_folder" -maxdepth 1 -type f \( \
        -name '*.mp3' -o -name '*.wav' -o -name '*.m4a' -o -name '*.flac' -o -name '*.ogg' -o -name '*.wma' -o \
        -name '*.aac' -o -name '*.aiff' -o -name '*.mp4' -o -name '*.mov' -o -name '*.avi' -o -name '*.mkv' -o \
        -name '*.webm' -o -name '*.caf' -o -name '*.control.json' -o -name '*.text.json' -o -name '*.route.json' \) | wc -l | tr -d ' ')

    # Heartbeat
    now=$(date +%s)
    if (( now - last_heartbeat >= HEARTBEAT_INTERVAL )); then
        frame="${heartbeat_frames[$heartbeat_index]}"
        glyph="${heartbeat_glyphs[$heartbeat_index]}"
        echo "${C_PANEL}[$(date '+%Y-%m-%d %H:%M:%S')]${C_RESET} ${C_LABEL}${glyph} HEARTBEAT ${glyph}${C_RESET} ${C_OK}node=${frame}${C_RESET} ${C_VALUE}processed=$files_processed${C_RESET} ${C_LABEL}watch=${C_RESET}${watch_folder}"
        heartbeat_index=$(((heartbeat_index + 1) % ${#heartbeat_frames[@]}))
        last_heartbeat=$now
        write_status "listening" "" "Heartbeat ${frame}" "" "" "$queue_count"
    fi

    for control_file in "$watch_folder"/*.control.json; do
        [ -e "$control_file" ] || continue
        while ! is_file_stable "$control_file"; do
            sleep 1
        done
        found_files=true
        write_status "activating" "$(basename "$control_file")" "Applying control action" "" "" "$queue_count"
        process_control_file "$control_file"
        write_status "listening" "" "Control action complete" "" "" "$queue_count"
    done

    for text_job_file in "$watch_folder"/*.text.json; do
        [ -e "$text_job_file" ] || continue
        found_files=true
        process_text_job_file "$text_job_file"
    done

    for audio_file in "$watch_folder"/*.{mp3,wav,m4a,flac,ogg,wma,aac,aiff,mp4,mov,avi,mkv,webm,caf,MP3,WAV,M4A,FLAC,OGG,WMA,AAC,AIFF,MP4,MOV,AVI,MKV,WEBM,CAF}; do
        [ -e "$audio_file" ] || continue

        # Wait until file is stable
        while ! is_file_stable "$audio_file"; do
            echo "${C_WARN}⏳ File still uploading:${C_RESET} $(basename "$audio_file")"
            sleep "${AUDIO_UPLOADING_SLEEP:-1}"
        done

        found_files=true
        filename=$(basename "$audio_file")
        timestamp=$(date "+%Y%m%d_%H%M%S")
        base_name="${filename%.*}"
        job_output_dir="$temp_transcriptions_folder/${base_name}_${timestamp}"
        mkdir -p "$job_output_dir"
        load_transcription_settings
        rm -f "$skip_file"

        echo "${C_LABEL}🎵 Processing:${C_RESET} ${C_VALUE}$filename${C_RESET} ${C_LABEL}model=${C_RESET}${WHISPER_MODEL}"
        write_status "transcribing" "$filename" "Transcribing audio with ${WHISPER_MODEL}" "" "" "$queue_count"
        route_metadata_file="${audio_file}.${filename##*.}"

        # Run whisper in background and capture PID
        whisper_args=(
            "$audio_file"
            --model "$WHISPER_MODEL"
            --task transcribe
            --temperature "$WHISPER_TEMPERATURE"
            --beam_size "$WHISPER_BEAM_SIZE"
            --condition_on_previous_text "$WHISPER_CONDITION_ON_PREVIOUS_TEXT"
            --fp16 False
            --threads 4
            --output_format txt
            --output_dir "$job_output_dir"
        )
        if [[ "$WHISPER_LANGUAGE" != "auto" ]]; then
            whisper_args+=(--language "$WHISPER_LANGUAGE")
        fi
        if [[ -n "${WHISPER_INITIAL_PROMPT:-}" ]]; then
            whisper_args+=(--initial_prompt "$WHISPER_INITIAL_PROMPT")
        fi

        whisper "${whisper_args[@]}" > /tmp/whisper_output.txt 2>&1 &
        whisper_pid=$!

        # Progress bar animation
        progress_chars="/-\|"
        char_index=0
        bar_filled=0
        total_width=30
        skip_requested=false
        timeout_requested=false
        whisper_start_epoch=$(date +%s)

        while kill -0 $whisper_pid 2>/dev/null; do
            if [[ -f "$skip_file" ]]; then
                skip_current_file=$(python3 - "$skip_file" <<'PY'
import json, sys
try:
    print((json.load(open(sys.argv[1], encoding="utf-8")).get("currentFile") or "").strip())
except Exception:
    print("")
PY
)
                if [[ "$skip_current_file" == "$filename" || -z "$skip_current_file" ]]; then
                    skip_requested=true
                    rm -f "$skip_file"
                    echo ""
                    echo "${C_WARN}⏭️ Skip requested:${C_RESET} stopping transcription for $filename"
                    kill "$whisper_pid" 2>/dev/null || true
                    sleep 0.2
                    kill -9 "$whisper_pid" 2>/dev/null || true
                    break
                else
                    echo "${C_WARN}⚠️ Ignoring stale skip request:${C_RESET} ${skip_current_file}"
                    rm -f "$skip_file"
                fi
            fi

            if [[ "$WHISPER_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] && (( WHISPER_TIMEOUT_SECONDS > 0 )); then
                elapsed_seconds=$(($(date +%s) - whisper_start_epoch))
                if (( elapsed_seconds >= WHISPER_TIMEOUT_SECONDS )); then
                    timeout_requested=true
                    echo ""
                    echo "${C_WARN}⏱️ Whisper timeout:${C_RESET} stopping transcription for $filename after ${elapsed_seconds}s"
                    kill "$whisper_pid" 2>/dev/null || true
                    sleep 0.2
                    kill -9 "$whisper_pid" 2>/dev/null || true
                    break
                fi
            fi

            progress_value=$(python3 - "$bar_filled" <<'PY'
import math
import sys
ticks = max(0, int(sys.argv[1]))
elapsed_seconds = ticks / 10.0
progress = 0.05 + 0.89 * (1 - math.exp(-elapsed_seconds / 8.0))
print(f"{min(0.94, max(0.05, progress)):.2f}")
PY
)
            filled=$(python3 - "$progress_value" "$total_width" <<'PY'
import sys
progress = float(sys.argv[1])
total = max(1, int(sys.argv[2]))
print(max(1, min(total, round(progress * total))))
PY
)
            empty=$((total_width - filled))
            if (( bar_filled % 10 == 0 )); then
                write_status "transcribing" "$filename" "Transcribing audio" "" "" "$queue_count" "$progress_value"
            fi

            printf "\r🔄 Transcribing: ["
            printf "%${filled}s" | tr ' ' '='
            printf "%${empty}s" | tr ' ' '-'
            printf "] %s " "${progress_chars:char_index:1}"

            char_index=$(((char_index + 1) % 4))
            bar_filled=$((bar_filled + 1))
            sleep 0.1
        done

        if $skip_requested || $timeout_requested; then
            wait "$whisper_pid" 2>/dev/null || true
            rm -rf "$job_output_dir"

            mv "$audio_file" "$processed_folder/${timestamp}_${filename}" 2>/dev/null || true

            base_path_no_ext="${audio_file%.*}"
            for associated_file in "$base_path_no_ext".*; do
                if [ -f "$associated_file" ] && [ "$associated_file" != "$audio_file" ]; then
                    mv "$associated_file" "$processed_folder/${timestamp}_$(basename "$associated_file")"
                fi
            done

            if $timeout_requested; then
                echo "$timestamp: Timed out $filename" >> "$log_file"
                echo "${C_WARN}⏱️ Timed out:${C_RESET} $filename moved to processed without clipboard/routing"
                status_message="Timed out current transcription"
                status_route="timeout"
            else
                echo "$timestamp: Skipped $filename" >> "$log_file"
                echo "${C_WARN}⏭️ Skipped:${C_RESET} $filename moved to processed without clipboard/routing"
                status_message="Skipped current transcription"
                status_route="skipped"
            fi
            ((files_processed++))
            write_status "listening" "" "$status_message" "$status_route" "" "$queue_count" "0"
            continue
        fi

        printf "\r🔄 Transcribing: ["
        printf "%${total_width}s" | tr ' ' '='
        printf "] ✓\n"
        write_status "transcribing" "$filename" "Transcription finishing" "" "" "$queue_count" "0.98"

        wait $whisper_pid
        transcription_status=$?

        transcript_file="$job_output_dir/${base_name}.txt"

        if [ $transcription_status -eq 0 ] && [ -f "$transcript_file" ]; then
            write_status "transcribing" "$filename" "Transcription complete" "" "" "$queue_count" "1.0"
            sleep "${TRANSCRIPTION_COMPLETE_DISPLAY_SLEEP:-0.45}"

            transcript_content=$(cat "$transcript_file")
            applescript_path="$default_applescript_path"
            should_route=false
            target_app=""
            submit_after_paste=true
            route_override=""
            response_mode=""
            response_json_path=""
            response_before_file=""
            capture_text_response=false

            route_metadata_file="${audio_file}.route.json"
            if [ -f "$route_metadata_file" ]; then
                if grep -q '"submit_after_paste"[[:space:]]*:[[:space:]]*false' "$route_metadata_file"; then
                    submit_after_paste=false
                fi
                route_override=$(python3 - "$route_metadata_file" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    print((data.get("route_target") or "").strip())
except Exception:
    print("")
PY
)
                response_mode=$(python3 - "$route_metadata_file" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    print((data.get("response_mode") or "").strip().lower())
except Exception:
    print("")
PY
)
            fi

            normalized_transcript=$(normalize_text "$transcript_content")
            pre_thank_you="$normalized_transcript"
            matched_script=""
            target_app=""
            route_shortcut=""
            has_thank_you=false
            allow_without_thank_you=false
            route_marker_prefix=""
            spoken_matched_script=$(get_app_script "$pre_thank_you")
            spoken_target_app=$(get_app_target "$pre_thank_you")
            spoken_route_shortcut=""

            if [[ "$spoken_target_app" == "iTerm2" ]]; then
                spoken_route_shortcut=$(extract_route_shortcut "$pre_thank_you")
            fi
            if route_marker_prefix=$(get_route_marker_prefix "$transcript_content" "$audio_file"); then
                has_thank_you=true
                pre_thank_you="$route_marker_prefix"
                spoken_matched_script=$(get_app_script "$pre_thank_you")
                spoken_target_app=$(get_app_target "$pre_thank_you")
                spoken_route_shortcut=""
                if [[ "$spoken_target_app" == "iTerm2" ]]; then
                    spoken_route_shortcut=$(extract_route_shortcut "$pre_thank_you")
                fi
            fi
            if is_main_route "$pre_thank_you" && [[ -n "$spoken_route_shortcut" ]]; then
                allow_without_thank_you=true
            fi

            if [[ -n "$route_override" ]]; then
                matched_script=$(get_route_override_script "$route_override")
                target_app=$(get_route_override_target "$route_override")
                route_shortcut=$(get_route_override_shortcut "$route_override")
                if [[ -n "$matched_script" ]]; then
                    if [[ "$route_override" == "clipboard" ]]; then
                        should_route=false
                        applescript_path="$default_applescript_path"
                    elif $submit_after_paste; then
                        applescript_path="$base_path/scripts/$matched_script"
                    else
                        applescript_path="$base_path/scripts/paste_transcription route_only.applescript"
                    fi
                    echo "${C_OK}🎯 Route override:${C_RESET} '${route_override}' ${C_LABEL}→${C_RESET} $(basename "$applescript_path")"
                    if [[ "$route_override" != "clipboard" ]]; then
                        should_route=true
                    fi
                fi
            elif [[ -n "$spoken_matched_script" ]] && { $has_thank_you || $allow_without_thank_you; }; then
                matched_script="$spoken_matched_script"
                target_app="$spoken_target_app"
                route_shortcut="$spoken_route_shortcut"
                echo "${C_OK}🗣️ Spoken route override:${C_RESET} '${pre_thank_you}'"
            else
                matched_script="$spoken_matched_script"
                target_app="$spoken_target_app"
                route_shortcut="$spoken_route_shortcut"
            fi

            if ! $should_route && { $has_thank_you || $allow_without_thank_you; } && [[ -n "$matched_script" ]]; then
                if $submit_after_paste; then
                    applescript_path="$base_path/scripts/$matched_script"
                else
                    applescript_path="$base_path/scripts/paste_transcription route_only.applescript"
                fi
                should_route=true
                echo "${C_OK}🎯 Detected app trigger phrase:${C_RESET} '${pre_thank_you}' ${C_LABEL}→${C_RESET} $(basename "$applescript_path")"
                if $has_thank_you; then
                    transcript_content=$(strip_to_route_content "$transcript_content")
                elif $allow_without_thank_you; then
                    transcript_content=$(strip_main_route_content "$transcript_content")
                fi
            elif ! $should_route && $has_thank_you; then
                transcript_content=$(strip_to_route_content "$transcript_content")
                echo "${C_WARN}📋 Route marker detected without a recognized app trigger phrase${C_RESET} ('${pre_thank_you}'). Leaving transcript on clipboard only."
            elif ! $should_route; then
                echo "${C_WARN}📋 No route marker detected.${C_RESET} Leaving transcript on clipboard only."
            fi

            routed_transcript_file="$job_output_dir/${base_name}.routed.txt"
            printf '%s' "$transcript_content" > "$routed_transcript_file"

            if [[ "$response_mode" == "text" ]]; then
                response_json_path="$responses_folder/${base_name}.response.json"
                python3 "$base_path/scripts/tmux_response_bridge.py" write \
                    --output "$response_json_path" \
                    --job-id "$base_name" \
                    --audio-filename "$filename" \
                    --route-target "${route_override:-$pre_thank_you}" \
                    --route-label "${target_app:-clipboard}" \
                    --transcript-file "$routed_transcript_file" \
                    --status "waiting" \
                    --message "Waiting for routed app response." \
                    --source "tmux" \
                    --target "$tmux_response_target" \
                    >/dev/null 2>&1 || true
                echo "${C_LABEL}💬 Text response requested:${C_RESET} $(basename "$response_json_path")"
            fi

            echo "$transcript_content" | pbcopy
            echo "${C_OK}✅ Transcription copied to clipboard!${C_RESET}"
            transcript_preview=$(printf '%s' "$transcript_content" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | cut -c1-180)

            # Only route when both a spoken trigger and the thank-you marker were detected.
            if $should_route; then
                echo "${C_LABEL}📋 Preparing routed send...${C_RESET}"
                write_status "routing" "$filename" "Routing transcript" "${target_app:-clipboard}" "$transcript_preview" "$queue_count"
                if [[ "$response_mode" == "text" && "$target_app" == "WezTerm" ]]; then
                    response_before_file="$job_output_dir/${base_name}.tmux.before.txt"
                    if python3 "$base_path/scripts/tmux_response_bridge.py" snapshot \
                        --target "$tmux_response_target" \
                        --output "$response_before_file" \
                        >/dev/null 2>&1; then
                        capture_text_response=true
                    else
                        python3 "$base_path/scripts/tmux_response_bridge.py" write \
                            --output "$response_json_path" \
                            --job-id "$base_name" \
                            --audio-filename "$filename" \
                            --route-target "${route_override:-wezterm}" \
                            --route-label "${target_app:-WezTerm}" \
                            --transcript-file "$routed_transcript_file" \
                            --status "error" \
                            --message "Could not capture tmux session '$tmux_response_target' before routing." \
                            --source "tmux" \
                            --target "$tmux_response_target" \
                            >/dev/null 2>&1 || true
                    fi
                fi
                if [[ "$response_mode" == "text" && "$target_app" == "WezTerm" ]]; then
                    echo "${C_LABEL}💬 Sending directly to tmux target:${C_RESET} ${tmux_response_target}"
                    if ! send_to_tmux_response_target "$transcript_content"; then
                        capture_text_response=false
                        python3 "$base_path/scripts/tmux_response_bridge.py" write \
                            --output "$response_json_path" \
                            --job-id "$base_name" \
                            --audio-filename "$filename" \
                            --route-target "${route_override:-wezterm}" \
                            --route-label "${target_app:-WezTerm}" \
                            --transcript-file "$routed_transcript_file" \
                            --status "error" \
                            --message "Could not send text to tmux session '$tmux_response_target'." \
                            --source "tmux" \
                            --target "$tmux_response_target" \
                            >/dev/null 2>&1 || true
                    fi
                elif $submit_after_paste; then
                    if [[ -n "$target_app" && -n "$route_shortcut" ]]; then
                        osascript "$base_path/scripts/paste_transcription submit.applescript" "$target_app" "$route_shortcut"
                    elif [[ -n "$target_app" ]]; then
                        osascript "$base_path/scripts/paste_transcription submit.applescript" "$target_app"
                    elif [[ -n "$route_shortcut" ]]; then
                        osascript "$applescript_path" "$route_shortcut"
                    else
                        osascript "$applescript_path"
                    fi
                else
                    if [[ -n "$route_shortcut" ]]; then
                        osascript "$applescript_path" "$target_app" "$route_shortcut"
                    else
                        osascript "$applescript_path" "$target_app"
                    fi
                fi
                if [[ "$response_mode" == "text" && "$capture_text_response" == true ]]; then
                    echo "${C_LABEL}💬 Waiting for tmux response:${C_RESET} ${tmux_response_target}"
                    python3 "$base_path/scripts/tmux_response_bridge.py" wait \
                        --target "$tmux_response_target" \
                        --before-file "$response_before_file" \
                        --output "$response_json_path" \
                        --job-id "$base_name" \
                        --audio-filename "$filename" \
                        --route-target "${route_override:-wezterm}" \
                        --route-label "${target_app:-WezTerm}" \
                        --transcript-file "$routed_transcript_file" \
                        --stable-secs "${VOICE_RETURN_STABLE_SECS:-4}" \
                        --timeout "${VOICE_RETURN_TIMEOUT:-120}" \
                        >/dev/null 2>&1 || true
                elif [[ "$response_mode" == "text" && -n "$response_json_path" && "$target_app" != "WezTerm" ]]; then
                    python3 "$base_path/scripts/tmux_response_bridge.py" write \
                        --output "$response_json_path" \
                        --job-id "$base_name" \
                        --audio-filename "$filename" \
                        --route-target "${route_override:-$pre_thank_you}" \
                        --route-label "${target_app:-clipboard}" \
                        --transcript-file "$routed_transcript_file" \
                        --status "complete" \
                        --message "Text responses are currently wired for WezTerm/tmux routes." \
                        --source "tmux" \
                        --target "$tmux_response_target" \
                        >/dev/null 2>&1 || true
                fi
            else
                echo "${C_WARN}📋 Clipboard only. No routing step performed.${C_RESET}"
                if [[ "$response_mode" == "text" && -n "$response_json_path" ]]; then
                    python3 "$base_path/scripts/tmux_response_bridge.py" write \
                        --output "$response_json_path" \
                        --job-id "$base_name" \
                        --audio-filename "$filename" \
                        --route-target "clipboard" \
                        --route-label "Clipboard" \
                        --transcript-file "$routed_transcript_file" \
                        --status "complete" \
                        --message "No route was selected, so no app response was captured." \
                        --source "clipboard" \
                        >/dev/null 2>&1 || true
                fi
            fi

            final_transcript_file="$transcriptions_folder/${base_name}_${timestamp}.txt"
            mv "$transcript_file" "$final_transcript_file"
            rmdir "$job_output_dir" 2>/dev/null || true

            # Move audio file to processed
            mv "$audio_file" "$processed_folder/${timestamp}_${filename}"

            # Move any associated files
            base_path_no_ext="${audio_file%.*}"
            for associated_file in "$base_path_no_ext".*; do
                if [ -f "$associated_file" ] && [ "$associated_file" != "$audio_file" ]; then
                    mv "$associated_file" "$processed_folder/${timestamp}_$(basename "$associated_file")"
                fi
            done

            echo "$timestamp: Processed $filename -> ${base_name}_${timestamp}.txt" >> "$log_file"

            echo "${C_OK}📝 Saved to:${C_RESET} ${final_transcript_file}"
            if ! $should_route || [[ "$applescript_path" == *"pasteboard.applescript" ]]; then
                echo "${C_LABEL}📋 Transcription routed to:${C_RESET} clipboard"
            else
                if $submit_after_paste; then
                    echo "${C_LABEL}📋 Transcription routed to:${C_RESET} ${pre_thank_you:-clipboard} ${C_OK}(submit)${C_RESET}"
                else
                    echo "${C_LABEL}📋 Transcription routed to:${C_RESET} ${pre_thank_you:-clipboard} ${C_WARN}(paste only)${C_RESET}"
                fi
            fi
            ((files_processed++))
            write_status "listening" "" "Last file processed" "${target_app:-clipboard}" "$transcript_preview" "$queue_count"
        else
            echo "${C_ERR}❌ Transcription failed for:${C_RESET} $filename"
            rm -rf "$job_output_dir"
            write_status "error" "$filename" "Transcription failed" "" "" "$queue_count"
        fi
    done

    if ! $found_files; then
        echo -ne "\r⏰ Checking for new files...                    "
        if (( now - last_idle_status_write >= 10 )); then
            write_status "listening" "" "Waiting for files" "" "" "$queue_count"
            last_idle_status_write=$now
        fi
    fi
    sleep "${WATCHER_LOOP_SLEEP:-2}"
done
