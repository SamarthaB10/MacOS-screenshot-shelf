# Screenshot Shelf requirements

## Agreed design

- Native macOS app. Rust owns state, file operations, and screenshot lifetime. A small AppKit adapter owns native controls and drag sessions. No webview or third-party dependencies.
- First version targets Apple silicon with macOS 26 and native Liquid Glass.
- Keep normal macOS screenshot shortcuts. Watch a separate capture folder. Setup tells the user how to select that folder in the Screenshot app. Do not change macOS settings automatically.
- Ignore files already in the capture folder at app launch. Clipboard-only captures are outside the first version.
- Show a widget only when pending screenshots exist. Show the newest screenshot, a count, and previous and next controls. Keep older pending screenshots available.
- Use native Liquid Glass. Start in the lower-right corner. Let the user move the widget. Keep it above normal windows, across spaces and beside full-screen apps, without taking keyboard focus.
- Drag the selected screenshot using a native file transfer. Keep it on a cancelled or rejected drop. Delete the source immediately after an accepted drop. No recovery period or hidden recovery copy. A drag completion does not confirm that a website upload is complete.
- Use one large green check to save the selected screenshot to the chosen folder. Remove it from the widget after saving. Retain it and show an error if saving fails. Do not overwrite existing saved files.
- Use a small × button to delete only the selected screenshot.
- After 10 minutes without widget action, delete all pending screenshots and close the widget. New captures and widget actions restart the timer. Do not delete a file during an active drag.
- Restore pending screenshots after an app restart only if the 10-minute limit has not passed. Delete expired pending screenshots on the next launch. The app cannot run cleanup while it is not running.
- Use a menu-bar icon for setup, folder controls, optional start at login, and Quit.
- Choose a save destination during setup. Keep it separate from the capture and pending folders.
- Show a storage notice above 1 GB of pending image data. The 10-minute deletion rule applies to these images too.

## Initial performance targets

- Idle memory: 30 MB.
- Memory with widget open: 80 MB.
- Installed app: below 20 MB, excluding screenshots.
- Preview: within 300 ms after a capture file is ready.

These are targets to measure, not guarantees. Native framework memory and receiving-app behavior can vary.
