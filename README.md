# Memo2Computah / LukeMobile

Source for the iPhone recorders, macOS companion apps, and transcription routing scripts.

## Current Apps

- `Memo2Computah`: iPhone recorder with Dropbox, LAN HTTP, and Cloudflare HTTP delivery.
- `LukeMobileRecoder`: existing iPhone recorder workflow.
- `Memo2ComputahDesktop`: macOS menu/receiver companion.
- `AutoTranscribeCompanion`: macOS Dropbox watcher/transcription companion.

## Google Drive Simple Plan

For the first PC version, use Google Drive for Desktop rather than the Google Drive API:

1. Install Google Drive for Desktop on Windows.
2. Sync a dedicated folder, for example `Google Drive/Memo2Computah`.
3. Build a Windows companion that watches that folder for new audio/text jobs.
4. Keep iPhone upload behavior as folder-based transport first; add direct Google API only if Drive for Desktop is not reliable enough.

## Local Runtime Data

This repository intentionally excludes processed audio, transcriptions, temp crash reports, and local staging folders. Those are runtime data, not source.

## Security Note

The local receiver token is currently embedded for self-built testing so the iPhone apps do not require manual token pasting. Keep this repo private while that test token remains in source.
