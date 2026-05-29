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


@dataclass
class CompanionConfig:
    watch_folder: str
    whisper_command: str
    auto_paste: bool
    press_enter_after_paste: bool
    poll_seconds: float

    @staticmethod
    def defaults() -> "CompanionConfig":
        return CompanionConfig(
            watch_folder=str(default_watch_folder()),
            whisper_command='whisper "{input}" --model base --task transcribe --output_format txt --output_dir "{output_dir}"',
            auto_paste=True,
            press_enter_after_paste=False,
            poll_seconds=2.0,
        )


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
            if path.suffix.lower() in AUDIO_EXTENSIONS:
                text = self.transcribe_audio(path, config)
            else:
                text = self.read_text_job(path)
            if not text.strip():
                self.log(f"No text produced for {path.name}")
                return
            self.write_transcript(path, config, text)
            self.deliver_text(text, config)
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

    def read_text_job(self, path: Path) -> str:
        content = path.read_text(encoding="utf-8", errors="replace")
        if path.suffix.lower() != ".json":
            return content.strip()
        try:
            payload = json.loads(content)
        except json.JSONDecodeError:
            return content.strip()
        for key in ("transcript", "message", "text", "body"):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        return content.strip()

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

    def deliver_text(self, text: str, config: CompanionConfig) -> None:
        self.copy_to_clipboard(text)
        if config.auto_paste:
            self.send_keys(config.press_enter_after_paste)

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


class Memo2App:
    def __init__(self) -> None:
        self.root = Tk()
        self.root.title(APP_NAME)
        self.root.geometry("760x520")
        self.store = ConfigStore()
        self.config = self.store.load()
        self.log_queue: queue.Queue[str] = queue.Queue()
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None

        self.watch_folder = StringVar(value=self.config.watch_folder)
        self.whisper_command = StringVar(value=self.config.whisper_command)
        self.auto_paste = BooleanVar(value=self.config.auto_paste)
        self.press_enter = BooleanVar(value=self.config.press_enter_after_paste)

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
            poll_seconds=2.0,
        )

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
