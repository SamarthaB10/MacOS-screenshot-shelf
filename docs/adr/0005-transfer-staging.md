# Keep a short transfer file after a drop

Immediate pending-file deletion caused observed “File not found” in Zen and “Upload failed” in ChatGPT. Supply image bytes and a separate transfer file, using an APFS clone when available. Delete the pending source immediately after an accepted drop, but keep transfer staging for 60 seconds before deletion. This is a transfer lease, not a recovery archive; a target that reads after that limit can still fail.

This updates ADR-0002. Discard and idle expiry still delete pending images directly.
