#!/bin/zsh
# Builds Convertify.app into ~/Applications and registers its Finder services.
set -euo pipefail
cd "$(dirname "$0")"
APP="/Applications/Convertify.app"
BUILD="build"
rm -rf "$BUILD"; mkdir -p "$BUILD/Convertify.app/Contents/MacOS" "$BUILD/Convertify.app/Contents/Resources"

echo "compiling..."
swiftc -O -swift-version 5 -target arm64-apple-macos14 -o "$BUILD/Convertify.app/Contents/MacOS/Convertify" Sources/main.swift Sources/app.swift 2>&1 | grep -v '^$' || true
[[ -x "$BUILD/Convertify.app/Contents/MacOS/Convertify" ]] || { echo "compile failed"; exit 1; }

# One service entry per preset. Keep in sync with Preset.all in main.swift.
svc() { # svc <id> <title> <uti>...
  local id="$1" title="$2"; shift 2; local types=""
  for u in "$@"; do types="$types
        <string>$u</string>"; done
  cat <<S
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>$title</string></dict>
      <key>NSMessage</key><string>svc_$id</string>
      <key>NSPortName</key><string>Convertify</string>
      <key>NSRequiredContext</key><dict><key>NSServiceCategory</key><string>Files and Folders</string></dict>
      <key>NSSendFileTypes</key><array>$types
      </array>
      <key>NSTimeout</key><string>10000</string>
    </dict>
S
}
AV=(public.audio public.movie)
{
cat <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Convertify</string>
  <key>CFBundleDisplayName</key><string>Convertify</string>
  <key>CFBundleIdentifier</key><string>com.jakobrosin.convertify</string>
  <key>CFBundleVersion</key><string>1.3</string>
  <key>CFBundleShortVersionString</key><string>1.3</string>
  <key>CFBundleExecutable</key><string>Convertify</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Jakob Rosin</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Media</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>None</string>
      <key>LSItemContentTypes</key><array><string>public.audio</string><string>public.movie</string><string>public.image</string></array>
    </dict>
  </array>
  <key>NSServices</key>
  <array>
P
svc mp3 "MP3 Encode" $AV
svc mp3low "MP3 Encode (Low Quality)" $AV
svc aac "AAC Encode" $AV
svc opus "Opus Encode" $AV
svc ogg "OGG Encode" $AV
svc wav "File to Wav" $AV
svc flac2wav "Flac to Wav and Delete" public.audio
svc wav2flac "Wav to Flac and Delete" public.audio
svc mp4 "File to MP4" public.movie
svc mov "File to MOV" public.movie
svc imagevideo "Image + Audio to Video" public.audio public.image
svc mkv "File to MKV" public.movie public.audio
svc extractaudio "Extract Audio" public.movie public.audio
svc jpeg "Image to JPEG" public.image
svc png "Image to PNG" public.image
svc mediainfo "Media Info" public.audio public.movie public.image
cat <<P
  </array>
</dict>
</plist>
P
} > "$BUILD/Convertify.app/Contents/Info.plist"
plutil -lint "$BUILD/Convertify.app/Contents/Info.plist"
echo "APPL????" > "$BUILD/Convertify.app/Contents/PkgInfo"
cp Resources/Manual.html "$BUILD/Convertify.app/Contents/Resources/"

echo "bundling ffmpeg, ffprobe, oggenc, flac and their libraries..."
python3 tools/bundle_tools.py "$BUILD/Convertify.app" ffmpeg ffprobe oggenc flac
codesign --force --sign - --identifier com.jakobrosin.convertify "$BUILD/Convertify.app"
pkill -x Convertify 2>/dev/null || true

LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
$LSR -u "$PWD/$BUILD/Convertify.app" >/dev/null 2>&1 || true
rm -rf "$APP"; cp -R "$BUILD/Convertify.app" "$APP"
rm -rf "$BUILD/Convertify.app"          # never leave a second copy around: LaunchServices may pick it and the services vanish
$LSR -f "$APP"
/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
echo "installed: $APP"
