#!/bin/zsh
# Packages ~/Applications/Convertify.app into Convertify.dmg next to this script.
set -euo pipefail
cd "$(dirname "$0")"
APP="/Applications/Convertify.app"
STAGE="build/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Resources/Manual.html "$STAGE/Convertify Manual.html"
cp "Resources/Original Windows SendTo readme.txt" "$STAGE/"
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
Andre Louis and arfy; their original readme is included too.
T
rm -f Convertify.dmg
hdiutil create -volname Convertify -srcfolder "$STAGE" -ov -format UDZO Convertify.dmg >/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/$STAGE/Convertify.app" >/dev/null 2>&1 || true
rm -rf "$STAGE"
ls -la Convertify.dmg
