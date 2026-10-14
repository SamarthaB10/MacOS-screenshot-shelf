# Capture directly into temporary app storage

The folder watcher delayed the widget until macOS finished its floating-thumbnail flow. The user approved Accessibility and Screen Recording permissions to keep Command–Shift–4 while capturing directly into app-owned temporary storage. A native event tap starts the region selection tool, and capture-process completion sends the image to Rust without a Desktop-file or folder-watch wait. The watcher remains as a fallback.

This supersedes ADR-0001 as the primary capture path. PNG creation still precedes preview display; exact latency must be measured.
