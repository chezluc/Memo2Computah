#!/usr/bin/env python3
"""Capture a tmux-backed assistant response for MobileRecorder text mode."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def capture_worker(target: str, start: int = -500) -> str:
    result = subprocess.run(
        ["tmux", "capture-pane", "-t", target, "-p", "-S", str(start)],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def filter_output(raw: str) -> str:
    lines = raw.splitlines()
    all_responses: list[str] = []
    current_response: list[str] = []
    in_response = False
    in_tool = False
    skip_block = False

    for line in lines:
        stripped = line.strip()

        if stripped.startswith("❯"):
            if current_response:
                all_responses.append("\n".join(current_response).strip())
                current_response = []
            in_response = False
            in_tool = False
            skip_block = False
            continue

        if "⏺" in stripped:
            in_response = True
            in_tool = False
            after = re.sub(r".*⏺\s*", "", stripped)
            if after:
                if re.match(r"^(Bash|Read|Write|Edit|Glob|Grep|Agent|Skill|Todo)\(", after):
                    in_tool = True
                else:
                    current_response.append(after)
            continue

        if not in_response:
            continue

        if re.match(r"^(Bash|Read|Write|Edit|Glob|Grep|Agent|Skill|Todo)\(", stripped):
            in_tool = True
            continue

        if in_tool:
            continue

        if "⎿" in stripped:
            continue

        if re.match(r"^[─│├└╭╰┴┬┼⎿⏺▪▫◾◽\s]+$", stripped):
            continue

        if stripped.startswith("```"):
            skip_block = not skip_block
            continue
        if skip_block:
            continue

        if re.match(r"^(Cost|Tokens|Duration|Total|Opus|Claude|Update|⚠|✻)", stripped):
            continue

        if re.match(r"^(⏵|⏵⏵|don.t ask|bypass|Tool loaded|Resume this|claude --resume|Context left|\d+ MCP)", stripped):
            continue

        if not stripped:
            if current_response and current_response[-1] != "":
                current_response.append("")
            continue

        current_response.append(stripped)

    if current_response:
        all_responses.append("\n".join(current_response).strip())

    return all_responses[-1] if all_responses else ""


def longest_common_prefix_length(a: str, b: str) -> int:
    limit = min(len(a), len(b))
    for index in range(limit):
        if a[index] != b[index]:
            return index
    return limit


def changed_portion(before: str, after: str) -> str:
    prefix_length = longest_common_prefix_length(before, after)
    return after[prefix_length:].strip()


def write_response(
    output: Path,
    *,
    job_id: str,
    status: str,
    route_target: str,
    route_label: str,
    transcript: str,
    response_text: str = "",
    message: str = "",
    source: str = "tmux",
    tmux_target: str = "",
    audio_filename: str = "",
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    now = utc_now()
    payload = {
        "version": 1,
        "job_id": job_id,
        "status": status,
        "route_target": route_target,
        "route_label": route_label,
        "transcript": transcript,
        "response_text": response_text,
        "message": message,
        "source": source,
        "tmux_target": tmux_target,
        "audio_filename": audio_filename,
        "created_at": now,
        "updated_at": now,
    }
    tmp = output.with_suffix(output.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, output)


def wait_for_response(target: str, before: str, stable_secs: float, timeout: float) -> tuple[str, str]:
    last = ""
    last_delta = ""
    stable = 0.0
    elapsed = 0.0
    poll = 1.0

    while elapsed < timeout:
        current = capture_worker(target)
        if current != before:
            raw_delta = changed_portion(before, current)
            if current == last:
                stable += poll
                if stable >= stable_secs:
                    response_text = filter_output(raw_delta)
                    if response_text:
                        return response_text, raw_delta
            else:
                last = current
                last_delta = raw_delta
                stable = 0.0
        time.sleep(poll)
        elapsed += poll

    if last_delta:
        return filter_output(last_delta), last_delta
    return "", ""


def cmd_snapshot(args: argparse.Namespace) -> int:
    try:
        snapshot = capture_worker(args.target)
    except subprocess.CalledProcessError as exc:
        print(exc.stderr.strip() or exc.stdout.strip() or str(exc), file=sys.stderr)
        return 1
    Path(args.output).write_text(snapshot, encoding="utf-8")
    return 0


def cmd_wait(args: argparse.Namespace) -> int:
    output = Path(args.output)
    transcript = Path(args.transcript_file).read_text(encoding="utf-8").strip()
    before = Path(args.before_file).read_text(encoding="utf-8")

    try:
        response_text, _ = wait_for_response(args.target, before, args.stable_secs, args.timeout)
    except subprocess.CalledProcessError as exc:
        write_response(
            output,
            job_id=args.job_id,
            status="error",
            route_target=args.route_target,
            route_label=args.route_label,
            transcript=transcript,
            message=exc.stderr.strip() or exc.stdout.strip() or "Could not capture tmux response.",
            tmux_target=args.target,
            audio_filename=args.audio_filename,
        )
        return 1

    if not response_text:
        write_response(
            output,
            job_id=args.job_id,
            status="timeout",
            route_target=args.route_target,
            route_label=args.route_label,
            transcript=transcript,
            message="No text response was captured before timeout.",
            tmux_target=args.target,
            audio_filename=args.audio_filename,
        )
        return 2

    write_response(
        output,
        job_id=args.job_id,
        status="complete",
        route_target=args.route_target,
        route_label=args.route_label,
        transcript=transcript,
        response_text=response_text,
        message="Response captured.",
        tmux_target=args.target,
        audio_filename=args.audio_filename,
    )
    return 0


def cmd_write(args: argparse.Namespace) -> int:
    transcript = ""
    if args.transcript_file:
        transcript = Path(args.transcript_file).read_text(encoding="utf-8").strip()
    write_response(
        Path(args.output),
        job_id=args.job_id,
        status=args.status,
        route_target=args.route_target,
        route_label=args.route_label,
        transcript=transcript,
        response_text=args.response_text,
        message=args.message,
        source=args.source,
        tmux_target=args.target,
        audio_filename=args.audio_filename,
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="MobileRecorder tmux response bridge")
    subparsers = parser.add_subparsers(dest="command", required=True)

    snapshot = subparsers.add_parser("snapshot")
    snapshot.add_argument("--target", default="voice_return")
    snapshot.add_argument("--output", required=True)
    snapshot.set_defaults(func=cmd_snapshot)

    wait = subparsers.add_parser("wait")
    wait.add_argument("--target", default="voice_return")
    wait.add_argument("--before-file", required=True)
    wait.add_argument("--output", required=True)
    wait.add_argument("--job-id", required=True)
    wait.add_argument("--audio-filename", default="")
    wait.add_argument("--route-target", default="")
    wait.add_argument("--route-label", default="")
    wait.add_argument("--transcript-file", required=True)
    wait.add_argument("--stable-secs", type=float, default=4.0)
    wait.add_argument("--timeout", type=float, default=120.0)
    wait.set_defaults(func=cmd_wait)

    write = subparsers.add_parser("write")
    write.add_argument("--output", required=True)
    write.add_argument("--job-id", required=True)
    write.add_argument("--audio-filename", default="")
    write.add_argument("--route-target", default="")
    write.add_argument("--route-label", default="")
    write.add_argument("--transcript-file")
    write.add_argument("--response-text", default="")
    write.add_argument("--message", default="")
    write.add_argument("--status", default="waiting")
    write.add_argument("--source", default="tmux")
    write.add_argument("--target", default="")
    write.set_defaults(func=cmd_write)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
