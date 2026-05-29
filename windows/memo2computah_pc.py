from __future__ import annotations

import json
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from tkinter import BooleanVar, StringVar, Tk, filedialog, messagebox
from tkinter import ttk


APP_NAME = "Memo2Computah PC"
AUDIO_EXTENSIONS = {".aac", ".aiff", ".flac", ".m4a", ".mp3", ".mp4", ".ogg", ".wav", ".webm"}
TEXT_EXTENSIONS = {".json", ".txt"}
IGNORED_EXTENSIONS = {".crdownload", ".part", ".tmp"}


def app_data_dir() -> Path:
    base = os.environ.get("APPDATA")
    if base:
        return Path(base) / "Memo2ComputahPC"
    return Path.home() / ".memo2computah_pc"


def default_watch_folder() -> Path:
    home = Path.home()
    candidates = [
        home / "Google Drive" / "My Drive" / "auto.transcribe",
        home / "Google Drive" / "auto.transcribe",
        home / "My Drive" / "auto.transcribe",
        home / "Google Drive" / "My Drive" / "Memo2Computah",
        home / "Google Drive" / "Memo2Computah",
        home / "Documents" / "auto.transcribe",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return home / "Documents" / "auto.transcribe"


def timestamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def unique_path(path: Path) -> Path:
    if not path.exists():
        return path
    stem = path.stem
    suffix = path.suffix
    parent = path.parent
    for index in range(1, 1000):
        candidate = parent / f"{stem}-{index}{suffix}"
        if not candidate.exists():
            return candidate
    return parent / f"{stem}-{timestamp()}{suffix}"


def powershell_single_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


@dataclass
class CompanionConfig:
    watch_folder: str
    whisper_command: str
    auto_paste: bool
    press_enter_after_paste: bool
    codex_window_title: str
    codex_exe_path: str
    claude_window_title: str
    claude_exe_path: str
    poll_seconds: float

    @staticmethod
    def defaults() -> "CompanionConfig":
        return CompanionConfig(
            watch_folder=str(default_watch_folder()),
            whisper_command='whisper "{input}" --model base --task transcribe --output_format txt --output_dir "{output_dir}"',
            auto_paste=True,
            press_enter_after_paste=False,
            codex_window_title="Codex",
            codex_exe_path="",
            claude_window_title="Claude",
            claude_exe_path="",
            poll_seconds=2.0,
        )


@dataclass
class ProcessedJob:
    text: str
    route_target: str | None = None
    submit_after_paste: bool | None = None


class ConfigStore:
    def __init__(self) -> None:
        self.folder = app_data_dir()
        self.path = self.folder / "config.json"

    def load(self) -> CompanionConfig:
        defaults = CompanionConfig.defaults()
        if not self.path.exists():
            return defaults
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except Exception:
            return defaults
        return CompanionConfig(
            watch_folder=str(raw.get("watch_folder") or defaults.watch_folder),
            whisper_command=str(raw.get("whisper_command") or defaults.whisper_command),
            auto_paste=bool(raw.get("auto_paste", defaults.auto_paste)),
            press_enter_after_paste=bool(raw.get("press_enter_after_paste", defaults.press_enter_after_paste)),
            codex_window_title=str(raw.get("codex_window_title") or defaults.codex_window_title),
            codex_exe_path=str(raw.get("codex_exe_path") or defaults.codex_exe_path),
            claude_window_title=str(raw.get("claude_window_title") or defaults.claude_window_title),
            claude_exe_path=str(raw.get("claude_exe_path") or defaults.claude_exe_path),
            poll_seconds=float(raw.get("poll_seconds", defaults.poll_seconds)),
        )

    def save(self, config: CompanionConfig) -> None:
        self.folder.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(config.__dict__, indent=2), encoding="utf-8")


class FolderWatcher:
    def __init__(self, get_config, log, stop_event: threading.Event) -> None:
        self.get_config = get_config
        self.log = log
        self.stop_event = stop_event
        self.in_progress: set[Path] = set()

    def run(self) -> None:
        self.log("Watcher started.")
        while not self.stop_event.is_set():
            config = self.get_config()
            watch_folder = Path(config.watch_folder).expanduser()
            try:
                watch_folder.mkdir(parents=True, exist_ok=True)
                for path in sorted(watch_folder.iterdir(), key=lambda item: item.stat().st_mtime):
                    if self.stop_event.is_set():
                        break
                    if self.should_process(path):
                        self.process(path, config)
            except Exception as exc:
                self.log(f"Watcher error: {exc}")
            self.stop_event.wait(max(0.5, config.poll_seconds))
        self.log("Watcher stopped.")

    def should_process(self, path: Path) -> bool:
        if path in self.in_progress:
            return False
        if not path.is_file():
            return False
        suffix = path.suffix.lower()
        if suffix in IGNORED_EXTENSIONS:
            return False
        if path.name.endswith(".route.json"):
            return False
        if suffix not in AUDIO_EXTENSIONS and suffix not in TEXT_EXTENSIONS:
            return False
        lower_parts = {part.lower() for part in path.parts}
        if "processed" in lower_parts or "transcriptions" in lower_parts:
            return False
        return True

    def process(self, path: Path, config: CompanionConfig) -> None:
        self.in_progress.add(path)
        try:
            if not self.wait_until_stable(path):
                self.log(f"Skipped unstable file: {path.name}")
                return
            job = self.read_job(path, config)
            if not job.text.strip():
                self.log(f"No text produced for {path.name}")
                return
            self.write_transcript(path, config, job.text)
            self.deliver_text(job, config)
            self.move_to_processed(path, config)
            self.log(f"Delivered {path.name}")
        except Exception as exc:
            self.log(f"Failed {path.name}: {exc}")
        finally:
            self.in_progress.discard(path)

    def wait_until_stable(self, path: Path) -> bool:
        previous = None
        stable_count = 0
        for _ in range(12):
            if self.stop_event.is_set() or not path.exists():
                return False
            stat = path.stat()
            current = (stat.st_size, stat.st_mtime_ns)
            if current == previous:
                stable_count += 1
                if stable_count >= 2:
                    return True
            else:
                stable_count = 0
                previous = current
            time.sleep(0.5)
        return False

    def read_job(self, path: Path, config: CompanionConfig) -> ProcessedJob:
        metadata = self.read_sidecar_metadata(path)
        if path.suffix.lower() in AUDIO_EXTENSIONS:
            text = self.transcribe_audio(path, config)
            return ProcessedJob(
                text=text,
                route_target=self.string_value(metadata.get("route_target")),
                submit_after_paste=self.bool_value(metadata.get("submit_after_paste")),
            )
        return self.read_text_job(path, metadata)

    def read_text_job(self, path: Path, sidecar_metadata: dict) -> ProcessedJob:
        content = path.read_text(encoding="utf-8", errors="replace")
        if path.suffix.lower() != ".json":
            return ProcessedJob(
                text=content.strip(),
                route_target=self.string_value(sidecar_metadata.get("route_target")),
                submit_after_paste=self.bool_value(sidecar_metadata.get("submit_after_paste")),
            )
        try:
            payload = json.loads(content)
        except json.JSONDecodeError:
            return ProcessedJob(text=content.strip())

        route_target = self.string_value(payload.get("route_target") or sidecar_metadata.get("route_target"))
        submit_after_paste = self.bool_value(payload.get("submit_after_paste", sidecar_metadata.get("submit_after_paste")))
        for key in ("transcript", "message", "text", "body"):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return ProcessedJob(
                    text=value.strip(),
                    route_target=route_target,
                    submit_after_paste=submit_after_paste,
                )
        return ProcessedJob(text=content.strip(), route_target=route_target, submit_after_paste=submit_after_paste)

    def read_sidecar_metadata(self, path: Path) -> dict:
        sidecar = path.with_name(path.name + ".route.json")
        if not sidecar.exists():
            return {}
        try:
            payload = json.loads(sidecar.read_text(encoding="utf-8", errors="replace"))
            return payload if isinstance(payload, dict) else {}
        except Exception:
            return {}

    def string_value(self, value) -> str | None:
        if isinstance(value, str) and value.strip():
            return value.strip()
        return None

    def bool_value(self, value) -> bool | None:
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            lowered = value.strip().lower()
            if lowered in {"1", "true", "yes", "y"}:
                return True
            if lowered in {"0", "false", "no", "n"}:
                return False
        if isinstance(value, int):
            return value != 0
        return None

    def transcribe_audio(self, path: Path, config: CompanionConfig) -> str:
        command_template = config.whisper_command.strip()
        if not command_template:
            raise RuntimeError("Whisper command is empty. Set it in the app before sending audio.")
        output_dir = Path(tempfile.mkdtemp(prefix="memo2-whisper-"))
        command = self.build_whisper_command(command_template, path, output_dir)
        self.log(f"Transcribing {path.name}")
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=None)
        if result.returncode != 0:
            stderr = (result.stderr or result.stdout or "").strip()
            raise RuntimeError(f"Whisper failed with exit {result.returncode}: {stderr[:500]}")
        transcript_file = output_dir / f"{path.stem}.txt"
        if not transcript_file.exists():
            text_files = sorted(output_dir.glob("*.txt"), key=lambda item: item.stat().st_mtime, reverse=True)
            if text_files:
                transcript_file = text_files[0]
        if not transcript_file.exists():
            stdout = (result.stdout or "").strip()
            if stdout:
                return stdout
            raise RuntimeError("Whisper did not create a transcript file.")
        return transcript_file.read_text(encoding="utf-8", errors="replace").strip()

    def build_whisper_command(self, template: str, input_path: Path, output_dir: Path) -> str:
        replacements = {
            "input": str(input_path),
            "output_dir": str(output_dir),
            "stem": input_path.stem,
        }
        if "{" in template and "}" in template:
            return template.format(**replacements)
        return f'{template} "{input_path}"'

    def write_transcript(self, source: Path, config: CompanionConfig, text: str) -> None:
        folder = Path(config.watch_folder) / "transcriptions"
        folder.mkdir(parents=True, exist_ok=True)
        transcript_path = unique_path(folder / f"{source.stem}.txt")
        transcript_path.write_text(text + "\n", encoding="utf-8")

    def move_to_processed(self, source: Path, config: CompanionConfig) -> None:
        folder = Path(config.watch_folder) / "processed"
        folder.mkdir(parents=True, exist_ok=True)
        destination = unique_path(folder / source.name)
        shutil.move(str(source), str(destination))
        sidecar = source.with_name(source.name + ".route.json")
        if sidecar.exists():
            shutil.move(str(sidecar), str(unique_path(folder / sidecar.name)))

    def deliver_text(self, job: ProcessedJob, config: CompanionConfig) -> None:
        self.copy_to_clipboard(job.text)
        if config.auto_paste:
            self.focus_route_target(job.route_target, config)
            self.send_keys(job.submit_after_paste if job.submit_after_paste is not None else config.press_enter_after_paste)

    def copy_to_clipboard(self, text: str) -> None:
        if sys.platform == "win32":
            subprocess.run(["clip"], input=text, text=True, check=True, timeout=20)
            return
        try:
            subprocess.run(["pbcopy"], input=text, text=True, check=True, timeout=20)
        except Exception:
            self.log("Clipboard copy is only automated on Windows and macOS.")

    def send_keys(self, press_enter: bool) -> None:
        if sys.platform != "win32":
            return
        enter = "; Start-Sleep -Milliseconds 100; $wshell.SendKeys('{ENTER}')" if press_enter else ""
        script = (
            "$wshell = New-Object -ComObject wscript.shell; "
            "Start-Sleep -Milliseconds 150; "
            "$wshell.SendKeys('^v')"
            + enter
        )
        subprocess.run(["powershell", "-NoProfile", "-Command", script], check=False, timeout=10)

    def focus_route_target(self, route_target: str | None, config: CompanionConfig) -> None:
        if sys.platform != "win32" or not route_target:
            return
        normalized = route_target.strip().lower().split(":", 1)[0]
        title = None
        exe_path = None
        if normalized == "codex":
            title = config.codex_window_title
            exe_path = config.codex_exe_path
        elif normalized == "claude":
            title = config.claude_window_title
            exe_path = config.claude_exe_path
        if not title:
            return

        quoted_title = powershell_single_quote(title)
        quoted_exe_path = powershell_single_quote(exe_path or "")
        script = (
            "$wshell = New-Object -ComObject wscript.shell; "
            f"$activated = $wshell.AppActivate({quoted_title}); "
            f"$exePath = {quoted_exe_path}; "
            "if (-not $activated -and $exePath -and (Test-Path -LiteralPath $exePath)) { "
            "Start-Process -FilePath $exePath; "
            "Start-Sleep -Milliseconds 1500; "
            f"$wshell.AppActivate({quoted_title}) | Out-Null; "
            "} "
            "Start-Sleep -Milliseconds 250"
        )
        subprocess.run(["powershell", "-NoProfile", "-Command", script], check=False, timeout=10)


class Memo2App:
    def __init__(self) -> None:
        self.root = Tk()
        self.root.title(APP_NAME)
        self.root.geometry("860x620")
        self.store = ConfigStore()
        self.config = self.store.load()
        self.log_queue: queue.Queue[str] = queue.Queue()
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None

        self.watch_folder = StringVar(value=self.config.watch_folder)
        self.whisper_command = StringVar(value=self.config.whisper_command)
        self.auto_paste = BooleanVar(value=self.config.auto_paste)
        self.press_enter = BooleanVar(value=self.config.press_enter_after_paste)
        self.codex_window_title = StringVar(value=self.config.codex_window_title)
        self.codex_exe_path = StringVar(value=self.config.codex_exe_path)
        self.claude_window_title = StringVar(value=self.config.claude_window_title)
        self.claude_exe_path = StringVar(value=self.config.claude_exe_path)

        self.build_ui()
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.root.after(150, self.drain_logs)

    def build_ui(self) -> None:
        outer = ttk.Frame(self.root, padding=18)
        outer.pack(fill="both", expand=True)

        title = ttk.Label(outer, text=APP_NAME, font=("Segoe UI", 18, "bold"))
        title.pack(anchor="w")
        subtitle = ttk.Label(
            outer,
            text="Watches a Google Drive folder, transcribes audio with your Whisper command, then copies or pastes the result.",
        )
        subtitle.pack(anchor="w", pady=(2, 16))

        folder_row = ttk.Frame(outer)
        folder_row.pack(fill="x", pady=(0, 10))
        ttk.Label(folder_row, text="Google Drive folder").pack(anchor="w")
        entry_row = ttk.Frame(folder_row)
        entry_row.pack(fill="x", pady=(4, 0))
        ttk.Entry(entry_row, textvariable=self.watch_folder).pack(side="left", fill="x", expand=True)
        ttk.Button(entry_row, text="Choose...", command=self.choose_folder).pack(side="left", padx=(8, 0))

        command_row = ttk.Frame(outer)
        command_row.pack(fill="x", pady=(0, 10))
        ttk.Label(command_row, text="Whisper command").pack(anchor="w")
        ttk.Entry(command_row, textvariable=self.whisper_command).pack(fill="x", pady=(4, 0))
        ttk.Label(
            command_row,
            text='Placeholders: "{input}", "{output_dir}", "{stem}". Default expects the whisper CLI to be installed on the PC.',
        ).pack(anchor="w", pady=(3, 0))

        options = ttk.Frame(outer)
        options.pack(fill="x", pady=(0, 12))
        ttk.Checkbutton(options, text="Paste into the active window after transcription", variable=self.auto_paste).pack(
            anchor="w"
        )
        ttk.Checkbutton(options, text="Press Enter after paste", variable=self.press_enter).pack(anchor="w")

        routes = ttk.LabelFrame(outer, text="Routes")
        routes.pack(fill="x", pady=(0, 12))
        self.add_route_picker(routes, 0, "Codex", self.codex_window_title, self.codex_exe_path)
        self.add_route_picker(routes, 2, "Claude", self.claude_window_title, self.claude_exe_path)
        routes.columnconfigure(1, weight=1)

        controls = ttk.Frame(outer)
        controls.pack(fill="x", pady=(0, 12))
        self.start_button = ttk.Button(controls, text="Start Watcher", command=self.start)
        self.start_button.pack(side="left")
        self.stop_button = ttk.Button(controls, text="Stop", command=self.stop, state="disabled")
        self.stop_button.pack(side="left", padx=(8, 0))
        ttk.Button(controls, text="Save Settings", command=self.save_settings).pack(side="left", padx=(8, 0))
        ttk.Button(controls, text="Open Folder", command=self.open_folder).pack(side="left", padx=(8, 0))

        log_frame = ttk.LabelFrame(outer, text="Status")
        log_frame.pack(fill="both", expand=True)
        self.log_text = self.create_log_widget(log_frame)
        self.log(f"Config: {self.store.path}")
        self.log(f"Watching folder: {self.watch_folder.get()}")

    def create_log_widget(self, parent):
        import tkinter.scrolledtext

        widget = tkinter.scrolledtext.ScrolledText(parent, height=12, wrap="word", state="disabled")
        widget.pack(fill="both", expand=True, padx=8, pady=8)
        return widget

    def current_config(self) -> CompanionConfig:
        return CompanionConfig(
            watch_folder=self.watch_folder.get().strip(),
            whisper_command=self.whisper_command.get().strip(),
            auto_paste=bool(self.auto_paste.get()),
            press_enter_after_paste=bool(self.press_enter.get()),
            codex_window_title=self.codex_window_title.get().strip() or "Codex",
            codex_exe_path=self.codex_exe_path.get().strip(),
            claude_window_title=self.claude_window_title.get().strip() or "Claude",
            claude_exe_path=self.claude_exe_path.get().strip(),
            poll_seconds=2.0,
        )

    def add_route_picker(self, parent, row: int, label: str, title_var: StringVar, path_var: StringVar) -> None:
        ttk.Label(parent, text=f"{label} window title").grid(row=row, column=0, sticky="w", padx=8, pady=(8, 2))
        ttk.Entry(parent, textvariable=title_var).grid(row=row, column=1, columnspan=2, sticky="ew", padx=8, pady=(8, 2))
        ttk.Label(parent, text=f"{label} app").grid(row=row + 1, column=0, sticky="w", padx=8, pady=(2, 8))
        ttk.Entry(parent, textvariable=path_var).grid(row=row + 1, column=1, sticky="ew", padx=8, pady=(2, 8))
        ttk.Button(
            parent,
            text="Browse...",
            command=lambda: self.choose_route_app(path_var),
        ).grid(row=row + 1, column=2, sticky="e", padx=8, pady=(2, 8))

    def choose_route_app(self, path_var: StringVar) -> None:
        selected = filedialog.askopenfilename(
            title="Choose route app",
            filetypes=[("Windows apps", "*.exe"), ("All files", "*.*")],
        )
        if selected:
            path_var.set(selected)
            self.save_settings()

    def choose_folder(self) -> None:
        selected = filedialog.askdirectory(initialdir=self.watch_folder.get() or str(Path.home()))
        if selected:
            self.watch_folder.set(selected)
            self.save_settings()

    def save_settings(self) -> None:
        config = self.current_config()
        self.store.save(config)
        self.config = config
        self.log("Settings saved.")

    def open_folder(self) -> None:
        folder = Path(self.watch_folder.get()).expanduser()
        folder.mkdir(parents=True, exist_ok=True)
        if sys.platform == "win32":
            os.startfile(str(folder))
        elif sys.platform == "darwin":
            subprocess.run(["open", str(folder)], check=False)
        else:
            subprocess.run(["xdg-open", str(folder)], check=False)

    def start(self) -> None:
        if self.thread and self.thread.is_alive():
            return
        self.save_settings()
        self.stop_event.clear()
        watcher = FolderWatcher(self.current_config, self.log, self.stop_event)
        self.thread = threading.Thread(target=watcher.run, daemon=True)
        self.thread.start()
        self.start_button.configure(state="disabled")
        self.stop_button.configure(state="normal")

    def stop(self) -> None:
        self.stop_event.set()
        self.start_button.configure(state="normal")
        self.stop_button.configure(state="disabled")

    def on_close(self) -> None:
        self.stop()
        self.root.destroy()

    def log(self, message: str) -> None:
        self.log_queue.put(f"[{datetime.now().strftime('%H:%M:%S')}] {message}")

    def drain_logs(self) -> None:
        while True:
            try:
                message = self.log_queue.get_nowait()
            except queue.Empty:
                break
            self.log_text.configure(state="normal")
            self.log_text.insert("end", message + "\n")
            self.log_text.see("end")
            self.log_text.configure(state="disabled")
        self.root.after(150, self.drain_logs)

    def run(self) -> None:
        try:
            self.root.mainloop()
        except KeyboardInterrupt:
            self.on_close()


if __name__ == "__main__":
    try:
        Memo2App().run()
    except Exception as exc:
        messagebox.showerror(APP_NAME, str(exc))
