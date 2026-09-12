#!/bin/zsh
# Packages ~/Applications/Convertify.app into Convertify.dmg next to this script.
set -euo pipefail
cd "$(dirname "$0")"
APP="/Applications/Convertify.app"
STAGE="build/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Resources/Manual.html "$STAGE/Convertify Manual.html"
cat > "$STAGE/Read me first.txt" <<'T'
Convertify

1. Drag Convertify to the Applications folder.
2. Open it once. macOS will say it cannot verify the developer.
   Go to System Settings, Privacy and Security, scroll down, and choose Open Anyway.
3. After that, right-click any audio or video file in Finder, open the Services submenu,
   and pick a conversion such as MP3 Encode. A window shows the progress.

Everything needed is inside the app. Nothing else has to be installed.

The full manual is in this disk image as "Convertify Manual.html" and also inside the app,
under the Help menu. Convertify descends from the Windows "SendTo encoders" project by
Andre Louis (https://github.com/OnjLouis) and arfy.
Source and updates: https://github.com/jakobrosin/convertify
T
rm -f Convertify.dmg
hdiutil create -volname Convertify -srcfolder "$STAGE" -ov -format UDZO Convertify.dmg >/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/$STAGE/Convertify.app" >/dev/null 2>&1 || true
rm -rf "$STAGE"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
setopt null_glob; rm -f Convertify-macos-*.zip; unsetopt null_glob
ditto -c -k --keepParent "$APP" "Convertify-macos-$VERSION.zip"     # the in-app updater downloads this one
echo "zip for the updater: Convertify-macos-$VERSION.zip"
SHA=$(shasum -a 256 Convertify.dmg | cut -d' ' -f1); SIZE=$(stat -f %z Convertify.dmg)
cat > convertify-update.json <<J
{"version": "$VERSION", "url": "${CONVERTIFY_DOWNLOAD_URL:-https://github.com/jakobrosin/convertify/releases/latest/download/Convertify.dmg}", "sha256": "$SHA", "size": $SIZE,
 "notes": ["See the manual in the Help menu for what is new."]}
J
echo "update manifest: convertify-update.json (only still needed so Convertify 1.3 can find this release)"
ls -la Convertify.dmg
