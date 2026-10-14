# Screenshot Shelf

A small native macOS screenshot widget with Liquid Glass. Rust owns screenshot storage and lifetime. A small Objective-C adapter uses AppKit for native controls and drag-and-drop. No webview and no third-party packages.

## Build

Requires Apple silicon, macOS 26, Rust, and Apple command-line tools with the macOS 26 SDK.

```sh
./scripts/build-app.sh
open "dist/Screenshot Shelf.app"
```

The script creates an app bundle with an ad-hoc signature for local use. Copy it to Applications before enabling Start at login. Distribution to other Macs needs a Developer ID signature and notarization.

## Setup

1. Open the app and choose a save folder.
2. Press Shift–Command–5. Select **Options → Other Location** and choose `~/Pictures/Screenshot Shelf/Capture`.
3. Turn off **Show Floating Thumbnail** for faster capture. The app does not change this setting for you.
4. Take a screenshot with the normal macOS shortcuts.

The app watches only its capture folder. It ignores images already in that folder when it starts. Clipboard-only captures are not supported.

## Use

The widget appears only when a screenshot is waiting. It stays above normal windows and follows desktop spaces. Drag its background to move it.

- Use the arrows to select an image.
- Press the large green check to save that image in your chosen folder.
- Press × to delete that image.
- A failed save keeps the image and shows an error.
- After 10 minutes without a new capture or widget action, all pending images are deleted and the widget closes.

There is no recovery copy. Quitting stops cleanup; expired pending images are deleted when you reopen the app. Saved images are never part of timeout cleanup. The original capture file moves into the app's pending folder after it is ready.

Native drag-and-drop is delivered in the next pull request. The final flow deletes the source immediately after an accepted drop. macOS does not confirm that a website has finished reading or uploading the file; some receiving apps can therefore fail after immediate source deletion.

## Checks

```sh
cargo fmt --check
MACOSX_DEPLOYMENT_TARGET=26.0 cargo check
cargo clippy --all-targets -- -D warnings
./scripts/build-app.sh
```

No unit or integration tests are included, as requested. See [requirements](docs/REQUIREMENTS.md) and [design decisions](docs/adr/).
