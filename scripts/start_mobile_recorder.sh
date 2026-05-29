#!/usr/bin/env bash

set -euo pipefail

base_path="${MOBILE_RECORDER_APP_ROOT:-/Users/garnetuniverse/Dropbox/auto.transcribe.agent}"
watch_folder="${MOBILE_RECORDER_WATCH_FOLDER:-$base_path}"
app_support_dir="${WATCHER_APP_SUPPORT_DIR:-$HOME/Library/Application Support/auto.transcribe.agent}"
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-$app_support_dir/pycache}"
venv_path="${MOBILE_RECORDER_VENV:-$app_support_dir/.venv-mobile-recorder}"
cert_dir="$base_path/certs"
cert_file="$cert_dir/mobile-recorder.crt"
key_file="$cert_dir/mobile-recorder.key"
port="${PORT:-8943}"

cd "$base_path"
mkdir -p "$watch_folder"

if [ ! -d "$venv_path" ]; then
    python3 -m venv "$venv_path"
fi

source "$venv_path/bin/activate"
pip install --upgrade pip >/dev/null
pip install -r "$base_path/project/requirements.txt" >/dev/null

if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
    exec python3 "$base_path/scripts/mobile_recorder_server.py" \
        --host 0.0.0.0 \
        --port "$port" \
        --cert-file "$cert_file" \
        --key-file "$key_file"
fi

echo "No HTTPS certificate found. Starting in HTTP mode."
echo "If microphone access fails on iPhone, run:"
echo "  $base_path/scripts/generate_mobile_recorder_cert.sh"

exec python3 "$base_path/scripts/mobile_recorder_server.py" \
    --host 0.0.0.0 \
    --port "$port"
