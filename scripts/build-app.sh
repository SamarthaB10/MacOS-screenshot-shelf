#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=26.0
cargo build --release
app="dist/Screenshot Shelf.app"
mkdir -p "$app/Contents/MacOS"
cp -X target/release/screenshot-shelf "$app/Contents/MacOS/Screenshot Shelf"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.samarthab.screenshot-shelf</string>
<key>CFBundleName</key><string>Screenshot Shelf</string>
<key>CFBundleExecutable</key><string>Screenshot Shelf</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Clear Finder metadata only from this generated app bundle before signing.
xattr -cr "$app"
codesign --force --sign - "$app"
printf 'Built: %s\n' "$app"
