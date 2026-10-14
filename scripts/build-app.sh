#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=26.0
cargo build --release
shelf_stage=$(mktemp -d /private/tmp/screenshot-shelf.XXXXXX)
trap 'rm -r "$shelf_stage"' EXIT HUP INT TERM
app="$shelf_stage/Screenshot Shelf.app"
mkdir -p "$app/Contents/MacOS" dist
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
# Sign outside synced folders, where Finder metadata can invalidate a bundle.
xattr -cr "$app"
codesign --force --sign "${SHELF_SIGNING_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
ditto --norsrc --noextattr --noqtn -c -k --keepParent "$app" dist/Screenshot-Shelf-macos-arm64.zip
# Replace the generated bundle by rename. Never rewrite the executable of a
# running app in place; macOS can terminate it when its signed pages change.
shelf_next="dist/.shelf-next-$$.app"
shelf_previous="dist/.shelf-previous-$$.app"
ditto --norsrc --noextattr --noqtn "$app" "$shelf_next"
if [ -d 'dist/Screenshot Shelf.app' ]; then
    mv 'dist/Screenshot Shelf.app' "$shelf_previous"
fi
mv "$shelf_next" 'dist/Screenshot Shelf.app'
if [ -d "$shelf_previous" ]; then rm -r "$shelf_previous"; fi
printf 'Built: dist/Screenshot Shelf.app\nDownload: dist/Screenshot-Shelf-macos-arm64.zip\n'
