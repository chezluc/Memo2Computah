#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import subprocess
import socket
import ssl
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from uuid import uuid4

from flask import Flask, jsonify, render_template, request
from werkzeug.utils import secure_filename


APP_ROOT = Path(os.environ.get("MOBILE_RECORDER_APP_ROOT", "/Users/garnetuniverse/Dropbox/auto.transcribe.agent"))
WATCH_FOLDER = Path(os.environ.get("MOBILE_RECORDER_WATCH_FOLDER", str(APP_ROOT)))
UPLOAD_STAGING_DIR = Path(os.environ.get("MOBILE_RECORDER_STAGING_DIR", str(WATCH_FOLDER / "uploads_staging")))
TEMPLATE_DIR = APP_ROOT / "web" / "templates"
STATIC_DIR = APP_ROOT / "web" / "static"
API_TOKEN = os.environ.get("MOBILE_RECORDER_API_TOKEN", "").strip()
JOB_ID_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{1,160}$")

ALLOWED_MIME_TYPES = {
    "audio/webm": ".webm",
    "video/webm": ".webm",
    "audio/mp4": ".m4a",
    "video/mp4": ".mp4",
    "audio/mpeg": ".mp3",
    "audio/mp3": ".mp3",
    "audio/wav": ".wav",
    "audio/x-wav": ".wav",
    "audio/aac": ".aac",
    "audio/ogg": ".ogg",
    "audio/x-m4a": ".m4a",
    "audio/m4a": ".m4a",
}


app = Flask(__name__, template_folder=str(TEMPLATE_DIR), static_folder=str(STATIC_DIR))


def build_recording_name(extension: str) -> str:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return f"Mobile Recording {timestamp}_{uuid4().hex[:8]}{extension}"


def build_control_name() -> str:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return f"Mobile Recorder Control {timestamp}_{uuid4().hex[:8]}.control.json"


def build_text_job_id() -> str:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return f"ios_text_{timestamp}_{uuid4().hex[:8]}"


def validate_job_id(job_id: str) -> bool:
    return bool(JOB_ID_PATTERN.fullmatch(job_id))


@app.before_request
def require_api_token():
    if not request.path.startswith("/api/") or not API_TOKEN:
        return None

    expected = f"Bearer {API_TOKEN}"
    incoming = request.headers.get("Authorization", "")
    if secrets.compare_digest(incoming, expected):
        return None

    return jsonify({"error": "Unauthorized."}), 401


def route_target_to_activation(route_target: str) -> tuple[str | None, str | None]:
    normalized = route_target.strip().lower()
    if normalized == "codex":
        return "Codex", None
    if normalized == "plexi":
        return "Plexi", None
    if normalized == "chrome":
        return "Google Chrome", None
    if normalized == "iawriter":
        return "iA Writer", None
    if normalized == "terminal":
        return "Terminal", None
    if normalized == "iterm":
        return "iTerm2", None
    if normalized == "iterm:1":
        return "iTerm2", "1"
    if normalized == "iterm:2":
        return "iTerm2", "2"
    if normalized == "iterm:3":
        return "iTerm2", "3"
    if normalized == "iterm:4":
        return "iTerm2", "4"
    if normalized == "wezterm":
        return "WezTerm", None
    if normalized == "kitty":
        return "kitty", None
    if normalized == "tabby":
        return "Tabby", None
    return None, None


def choose_extension(content_type: str | None, original_name: str | None) -> str:
    if content_type:
        normalized_type = content_type.split(";")[0].strip().lower()
        if normalized_type in ALLOWED_MIME_TYPES:
            return ALLOWED_MIME_TYPES[normalized_type]

    if original_name:
        suffix = Path(secure_filename(original_name)).suffix.lower()
        if suffix in {".webm", ".m4a", ".mp4", ".mp3", ".wav", ".aac", ".ogg", ".caf"}:
            return suffix

    return ".webm"


def get_local_ips() -> list[str]:
    ips: set[str] = {"127.0.0.1"}
    hostname = socket.gethostname()

    try:
        for result in socket.getaddrinfo(hostname, None, family=socket.AF_INET):
            address = result[4][0]
            if not address.startswith("127."):
                ips.add(address)
    except socket.gaierror:
        pass

    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 80))
        address = probe.getsockname()[0]
        if address:
            ips.add(address)
    except OSError:
        pass
    finally:
        probe.close()

    return sorted(ips)


@app.get("/")
def index():
    return render_template("index.html")


@app.get("/health")
def health():
    return jsonify(
        {
            "ok": True,
            "service": "Memo2Computah receiver",
            "api_auth_required": bool(API_TOKEN),
            "watch_folder": str(WATCH_FOLDER),
            "staging_folder": str(UPLOAD_STAGING_DIR),
            "local_ips": get_local_ips(),
            "accepted_audio_types": sorted(ALLOWED_MIME_TYPES.keys()),
        }
    )


@app.get("/api/ping")
def api_ping():
    return jsonify({"ok": True, "service": "Memo2Computah receiver"})


@app.post("/api/upload")
def upload():
    incoming = request.files.get("audio")
    if incoming is None:
        return jsonify({"error": "Missing audio file."}), 400

    submit_after_paste = request.form.get("submit_after_paste", "1").strip().lower() not in {"0", "false", "no", "off"}
    route_target = request.form.get("route_target", "").strip() or None
    response_mode = request.form.get("response_mode", "").strip() or None
    call_session = request.form.get("call_session", "0").strip().lower() in {"1", "true", "yes", "on"}

    extension = choose_extension(incoming.mimetype, incoming.filename)
    final_name = build_recording_name(extension)
    UPLOAD_STAGING_DIR.mkdir(parents=True, exist_ok=True)

    temp_fd, temp_path = tempfile.mkstemp(prefix="upload_", suffix=extension, dir=UPLOAD_STAGING_DIR)
    os.close(temp_fd)

    try:
        incoming.save(temp_path)
        WATCH_FOLDER.mkdir(parents=True, exist_ok=True)
        final_path = WATCH_FOLDER / final_name
        os.replace(temp_path, final_path)
        metadata_path = final_path.with_suffix(final_path.suffix + ".route.json")
        metadata_path.write_text(
            json.dumps(
                {
                    "submit_after_paste": submit_after_paste,
                    "route_target": route_target,
                    "response_mode": response_mode,
                    "call_session": call_session,
                },
                indent=2,
            ),
            encoding="utf-8",
        )
    except Exception:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        raise

    return jsonify(
        {
            "ok": True,
            "filename": final_name,
            "watch_folder": str(WATCH_FOLDER),
            "submit_after_paste": submit_after_paste,
            "route_target": route_target,
            "response_mode": response_mode,
            "call_session": call_session,
        }
    )


@app.post("/api/text")
def text_job():
    payload = request.get_json(silent=True) or {}
    message = str(payload.get("message", "")).strip()
    if not message:
        return jsonify({"error": "Missing message."}), 400

    requested_job_id = str(payload.get("job_id", "")).strip()
    job_id = requested_job_id or build_text_job_id()
    if not validate_job_id(job_id):
        return jsonify({"error": "Invalid job_id."}), 400

    submit_after_paste = bool(payload.get("submit_after_paste", True))
    route_target = str(payload.get("route_target", "")).strip() or None
    response_mode = str(payload.get("response_mode", "")).strip() or None
    call_session = bool(payload.get("call_session", False))
    WATCH_FOLDER.mkdir(parents=True, exist_ok=True)
    final_path = WATCH_FOLDER / f"{job_id}.text.json"
    UPLOAD_STAGING_DIR.mkdir(parents=True, exist_ok=True)

    temp_fd, temp_path = tempfile.mkstemp(prefix="text_job_", suffix=".json", dir=UPLOAD_STAGING_DIR)
    os.close(temp_fd)

    try:
        Path(temp_path).write_text(
            json.dumps(
                {
                    "job_id": job_id,
                    "message": message,
                    "submit_after_paste": submit_after_paste,
                    "route_target": route_target,
                    "response_mode": response_mode,
                    "call_session": call_session,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        os.replace(temp_path, final_path)
    except Exception:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        raise

    return jsonify(
        {
            "ok": True,
            "job_id": job_id,
            "filename": final_path.name,
            "watch_folder": str(WATCH_FOLDER),
            "route_target": route_target,
            "response_mode": response_mode,
            "call_session": call_session,
        }
    )


@app.get("/api/text/<job_id>/response")
def text_response(job_id: str):
    if not validate_job_id(job_id):
        return jsonify({"error": "Invalid job_id."}), 400

    response_path = WATCH_FOLDER / "responses" / f"{job_id}.response.json"
    if not response_path.exists():
        return jsonify({"status": "waiting", "job_id": job_id}), 202

    try:
        payload = json.loads(response_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return jsonify({"error": "Response file is not valid JSON."}), 500

    return jsonify(payload)


@app.post("/api/control")
def control():
    payload = request.get_json(silent=True) or {}
    route_target = str(payload.get("route_target", "")).strip()
    if not route_target:
        return jsonify({"error": "Missing route_target."}), 400

    target_app, shortcut = route_target_to_activation(route_target)
    if target_app:
        command = ["/usr/bin/osascript", str(APP_ROOT / "scripts" / "activate_target.applescript"), target_app]
        if shortcut:
            command.append(shortcut)
        try:
            subprocess.run(command, check=True, capture_output=True, text=True)
            return jsonify({"ok": True, "route_target": route_target, "activated": target_app, "shortcut": shortcut})
        except subprocess.CalledProcessError as exc:
            return jsonify({"error": exc.stderr.strip() or exc.stdout.strip() or "Activation failed."}), 500

    control_name = build_control_name()
    WATCH_FOLDER.mkdir(parents=True, exist_ok=True)
    control_path = WATCH_FOLDER / control_name
    control_path.write_text(
        json.dumps({"action": "activate", "route_target": route_target}, indent=2),
        encoding="utf-8",
    )

    return jsonify({"ok": True, "filename": control_name, "route_target": route_target})


def build_ssl_context(cert_file: Path, key_file: Path) -> ssl.SSLContext:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=str(cert_file), keyfile=str(key_file))
    return context


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Mobile recorder web server for auto.transcribe.agent")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8943)
    parser.add_argument("--cert-file")
    parser.add_argument("--key-file")
    parser.add_argument("--debug", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    ssl_context = None

    if bool(args.cert_file) != bool(args.key_file):
        print("If you set one of --cert-file or --key-file, set both.", file=sys.stderr)
        return 2

    if args.cert_file and args.key_file:
        ssl_context = build_ssl_context(Path(args.cert_file), Path(args.key_file))

    protocol = "https" if ssl_context else "http"
    print(f"Starting mobile recorder server on {protocol}://{args.host}:{args.port}")
    print("Open one of these URLs on your iPhone:")
    for ip in get_local_ips():
        print(f"  {protocol}://{ip}:{args.port}")

    if not ssl_context:
        print("Note: plain HTTP may not allow microphone access on iPhone Safari.")
        print("Generate a local certificate and restart with HTTPS if the mic button does nothing.")

    app.run(host=args.host, port=args.port, debug=args.debug, ssl_context=ssl_context)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
