# Delete after an accepted drop without recovery

Delete the app-owned source immediately after an accepted drop. The user chose this behavior over a 24-hour recovery copy to minimize disk use and remove used images. macOS reports the end of the drag but does not confirm that a receiving app has finished reading or uploading the file, so this choice can cause transfer failures with some targets.

Delete all pending screenshots after 10 minutes without action. Suspend deletion during an active drag. Cleanup resumes when the app is running; it cannot execute after Quit.

Reference: https://developer.apple.com/documentation/appkit/nsdraggingsource/draggingsession(_:endedat:operation:)
