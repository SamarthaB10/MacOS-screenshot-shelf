# Use Rust with a small AppKit adapter

Rust owns screenshot state and file operations. A small Objective-C adapter calls AppKit, ImageIO, Dispatch, and ServiceManagement directly for native controls, bounded image previews, event-driven capture notifications, and optional start at login. This avoids a webview and external packages while keeping native macOS API details outside the core state logic.
