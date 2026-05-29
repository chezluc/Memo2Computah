# Memo2Computah PC

Memo2Computah PC is the Windows companion for a simple Google Drive workflow.

The app watches a local Google Drive synced folder, reads new text or audio files, writes transcripts, then copies or pastes the result into the active Windows app.

## Folder

Use Google Drive for desktop and create/select:

```text
My Drive/auto.transcribe
```

The app includes a folder picker, so the folder can be changed without rebuilding.

## Audio Transcription

The first Windows build uses an external Whisper command instead of bundling a large model into the app.

Default command:

```powershell
whisper "{input}" --model base --task transcribe --output_format txt --output_dir "{output_dir}"
```

The command intentionally uses `--task transcribe`, not translation, so Portuguese stays Portuguese and English stays English.

If Whisper is not installed on the PC yet, text files still work, but audio files will show a clear error in the app log.

## Routing

The Windows app can route jobs before pasting by reading `route_target` from a `.text.json` job or from an audio sidecar named like:

```text
recording.m4a.route.json
```

Supported routes in this build:

```json
{ "route_target": "codex" }
{ "route_target": "claude" }
```

The app focuses a matching window title before sending paste. Defaults are `Codex` and `Claude`, and both can be changed in the Routes section of the app.

## Build Locally

```powershell
py -3.12 -m pip install pyinstaller
py -3.12 -m PyInstaller --noconsole --onefile --name Memo2ComputahPC windows/memo2computah_pc.py
```

The EXE will be at:

```text
dist/Memo2ComputahPC.exe
```
