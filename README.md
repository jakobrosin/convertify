# Convertify

Finder Services that convert audio and video on the Mac, with a live progress window built for VoiceOver.
Right-click a file, pick "MP3 Encode", "File to Wav", "Extract Audio" and so on from the Services menu.

Convertify is the Mac descendant of **SendTo encoders**, the Windows project by
[Andre Louis](https://github.com/OnjLouis) (Onj) and arfy, started in 2012 and still maintained by Andre.
The conversion names, quality settings and several 2026 features (remux before re-encoding, lossless
audio extraction, MKV and image conversions, media reports, the output naming scheme) come from there.
The Mac version was written by Jakob Rosin in 2026 together with Claude (Anthropic).

Download: the latest `Convertify.dmg` under [Releases](https://github.com/jakobrosin/convertify/releases).
Apple Silicon, macOS 14 or newer. Not notarized: after the first launch, allow it under
System Settings, Privacy and Security, Open Anyway. The full user manual is in the DMG and in the app's Help menu.

## Licence

Convertify's own code is MIT licensed (see LICENSE). The DMG bundles unmodified builds of FFmpeg
(GPL, because x264 is included), LAME (LGPL), Opus (BSD), x264 (GPL), FLAC (BSD/GPL) and vorbis-tools
(GPL), obtained through Homebrew; they keep their own licences and their sources are available from
their projects. Convertify runs them as separate programs.

## Building

Installed at /Applications/Convertify.app. Rebuild and reinstall with `./build.sh`.

- Presets are defined in `Sources/main.swift` (`Preset.all`) and mirrored as service
  entries in `build.sh` (`svc ...`). Keep both lists in sync.
- Tools come from Homebrew: ffmpeg (with libmp3lame, libopus, aac_at), oggenc, flac.
- Log: ~/Library/Logs/Convertify.log (auto-trimmed at 1 MB).
- Test from the command line: `open -a /Applications/Convertify.app --args --preset mp3 /path/file.flac`
- Behaviour: window opens in front when a job starts, quits by itself 6 s after the last
  successful job, stays open on failure. Never overwrites: clashes get " 2", same-format
  conversions get " converted". Sources are deleted only by the two "and Delete" presets,
  after the flac tool has verified the result.

## Window

One table named "Files", one row per file, newest first, columns in this order:
File, Status, Progress (percent and time left, or "took N seconds"), Started, Action, Result
(output name or error). Keyboard focus lands in the table when the window opens.
Arrow keys, Home, End, Page Up, Page Down move through rows. Return opens the output,
Delete removes a finished row. Finished rows persist in
~/Library/Application Support/Convertify/history.json, pruned by the preferences.

## Menus and shortcuts

- File: Open Files (Cmd O, then choose the conversion), Reveal Output (Cmd R), Open Output
  (Cmd Down), Reveal Source (Cmd Shift R), Retry This File (Cmd T), Close Window (Cmd W).
- Edit: Copy (Cmd C copies the selected row as a sentence), Remove from History (Delete),
  Clear History (Cmd Shift Delete, asks first unless turned off in Preferences).
- Convert: one item per preset; opens a file chooser and starts the job.
- Job: Cancel This File (Cmd Period), Cancel All (Cmd Shift Period).
- Convertify: Preferences (Cmd Comma), About (shows tool paths and file locations).
- Help: Convertify Help, Open Log File, Show History File in Finder.
- Right-click on a row gives the same row actions as a context menu.
- Dropping files on the Dock icon asks which conversion to run.

## Preferences (UserDefaults, domain com.jakobrosin.convertify)

keepWindowOpen (false), quitDelay seconds (6), bringToFront (true), notifyOnFinish (true),
soundOnFinish (true), historyLimit (50, 0 = unlimited), historyDays (0 = never), confirmClear (true).
The window stays open on any failure regardless of keepWindowOpen.

## Notifications

macOS refuses UserNotifications permission for this locally signed app, so the finish message
is sent with `osascript display notification`. It appears under the Script Editor icon with the
title of the action. Sounds are played by the app itself.

## Gotcha

Do not bind Escape to a button in this app: AppKit also routes Cmd Period to an Escape-bound
button, which used to quit the app during a running job.

## Service registration gotchas (learned the hard way)

- Every NSServices entry needs `NSRequiredContext` with `NSServiceCategory` = "Files and Folders",
  otherwise Finder's Services menu silently drops it even though `pbs -dump` lists it.
- Never leave a second copy of the app bundle around (e.g. in build/): LaunchServices may
  register that copy instead and the services disappear. build.sh removes the build copy after
  installing and unregisters it.
- After changing services: `pbs -flush; pbs -update` and relaunch Finder (`killall Finder`).

## Self-contained build and sharing

`build.sh` copies ffmpeg, ffprobe, oggenc and flac from Homebrew into Contents/MacOS and every
library they need into Contents/Frameworks (tools/bundle_tools.py rewrites the load paths and
re-signs). The app looks for tools inside itself first, then Homebrew. About 38 MB, Apple Silicon only
(built on this Mac; an Intel build would need the same done on an Intel Mac or a universal ffmpeg).

`make_dmg.sh` produces Convertify.dmg (about 18 MB) with the app, an Applications link and a
"Read me first" note. Recipients: drag to Applications, open once, then System Settings, Privacy and
Security, Open Anyway. The app is only ad-hoc signed, so that step is required on every Mac.

Licensing note: the bundled ffmpeg includes x264 (GPL). Fine for sharing with friends; a public
release would need to switch File to MP4/MOV to h264_videotoolbox and rebuild ffmpeg without GPL parts.

## Manual

Resources/Manual.html is the user manual (accessible HTML, proper headings). It is copied into the
app (Help menu, "Convertify Manual") and into the DMG. Update the version line at the end of the manual
together with CFBundleShortVersionString in build.sh and the About panel in app.swift.

## First launch

0.7 s after launch the app shows, as sheets on the main window: an offer to move leftover
script-era Automator workflows (matched by menu title in ~/Library/Services) to the Trash, then a
welcome sheet with "Relaunch Finder Now". Flags `welcomed` and `oldServicesChecked` in UserDefaults;
delete them to see the sheets again. Both flows are also in the Help menu. Testing note: if the
screen is locked, System Events sees no windows for any app and nothing can activate.

## 1.2 polish

Preferences has two tabs (General, History) and pop-ups instead of number fields. Cmd I posts an
accessibility announcement of the current status (Speak Status). Cmd D opens a Show Details sheet
for the selected row with full paths, times and message, plus a Copy button. Escape in the table
hides the window without quitting. The Convert menu is grouped: lossy, WAV, video, "and Delete".
Cmd A selects all rows; Delete removes all selected finished rows.

## 1.3 (adopted from Andre Louis's SendTo encoders, September 2026 release)

- Output naming now matches SendTo: name.ext, name-converted.ext, name-converted-2.ext...
- File to MP4/MOV copies the video stream when the container can hold it (codec whitelist), re-encodes only
  incompatible audio to AAC; otherwise h264_videotoolbox, then libx264.
- New: File to MKV (lossless remux, fallback without data streams), Extract Audio (codec-aware extension,
  -c:a copy, verified), Image to JPEG / PNG (sips; WebP not possible: no encoder available), Media Info
  (ffprobe JSON rendered as speech-friendly text; service + Cmd Shift I + Convert menu).
- Chapters mapped on all ffmpeg presets; every output verified with ffprobe; flac uses -j threads.
- Maintenance on launch: on version change re-register with LaunchServices, refresh pbs, delete stale temp
  files; offer to trash duplicate copies (found via LaunchServices); offer to install into /Applications when
  run from a DMG or Downloads.
- Check for Updates: reads a JSON manifest (defaults key updateManifestURL, see make_dmg.sh which writes
  convertify-update.json with version/url/sha256/size/notes), verifies size + SHA-256 (CryptoKit), mounts
  the DMG, stages the app, replaces /Applications/Convertify.app via a detached shell and relaunches.
  The default manifest address is the latest GitHub release asset; `make_dmg.sh` writes the manifest with
  the matching download URL. A release is: bump the version in build.sh, app.swift (About) and the manual,
  `./build.sh && ./make_dmg.sh`, then `gh release create vX.Y Convertify.dmg convertify-update.json`.
  A user can point the app elsewhere with `defaults write com.jakobrosin.convertify updateManifestURL ...`.
