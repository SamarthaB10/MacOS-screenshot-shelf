# Screenshot Shelf requirements

## Agreed design

- Native macOS app. Rust owns pending state, files, and lifetime. A small AppKit adapter owns native controls, capture, and drag sessions. No webview or third-party runtime packages.
- First version targets Apple silicon with macOS 26 and native Liquid Glass.
- Primary capture intercepts Command–Shift–4 after Accessibility and Screen Recording approval. Use native region selection and capture directly into temporary app storage. Bypass the floating-thumbnail and Desktop-file flow.
- Retain a folder watcher for other normal macOS screenshot files after fast capture is enabled. Do not silently use the slower watcher while fast-capture permissions are missing. Detect the configured screenshot folder automatically, ignore old files, and take only files marked as screenshots. Clipboard-only capture is outside the first version.
- Show a widget only when screenshots are pending. Show the newest image, a count, and previous/next controls. Keep older pending images available.
- Show the widget on the capture display. Use screenshot rectangle metadata, with the pointer display as a fallback. A new capture can move the widget to a different display.
- Use native Liquid Glass. Start in the lower-right corner. Let the user move it. Keep it above normal windows and available across spaces and beside full-screen apps. Do not take keyboard focus when it appears.
- Use native drag-and-drop with image data and a stable transfer file. Retain a pending image after a cancelled or rejected drop. Delete the pending source immediately after an accepted drop. Keep the separate transfer file for 60 seconds for the receiving app to read it, then delete it. No recovery archive.
- Use one large green check to save the selected image. Remove it after a successful save. Keep it and show an error if saving fails. Do not overwrite saved files.
- Use a small × button to delete only the selected pending image.
- After 10 minutes without capture or widget action, delete all pending images and close the widget. Do not delete during an active drag.
- Restore pending images after restart only if the 10-minute limit has not passed. Delete expired pending images and expired transfer files on the next launch. Cleanup cannot run while the app is closed.
- Use a menu-bar icon for capture, permissions, setup, folder controls, optional start at login, and Quit.
- Offer a save-folder choice in settings, with a usable default. Show a storage notice above 1 GB of pending images; normal timeout cleanup still applies.
- Provide a downloadable zipped app through GitHub builds. Put download and permission steps first in the README.

## Initial performance targets

Idle memory: 30 MB. Widget-open memory: 80 MB. Installed app: below 20 MB, excluding screenshots. Preview: within 300 ms after a capture image is ready.

These are targets to measure, not guarantees. Native framework memory and receiving-app behavior can vary. Direct capture is detected through process completion, so PNG creation must complete before the preview can appear.

## Installed app stability

Use one installed app in Applications. Enable Start at login through the native service. Do not request permissions automatically on every launch. Show whether fast capture is ready in the menu. A local build can use the user's existing Apple signing identity; public CI downloads remain ad-hoc signed.
