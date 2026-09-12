# Developing Convertify

Notes for anyone who wants to build, change or release Convertify. The user-facing description is in the README; the user manual is `Resources/Manual.html`.

## Layout

- `Sources/main.swift`: tool discovery, ffprobe helpers, output naming, the preset table (`Preset.all`), the media info report, the entry point.
- `Sources/app.swift`: preferences, history entries, the conversion engine, the main window and table, the preferences window, the media info window, first-launch and maintenance flows, menus, the Finder service handlers.
- `Sources/UpdateService.swift`: the updater, based on Clipman's `UpdateService` by Andre Louis (MIT).
- `Resources/Manual.html`: the manual, copied into the app (Help menu) and into the DMG.
- `build.sh`: compiles with `swiftc`, generates `Info.plist` with one `NSServices` entry per preset, bundles the tools, signs ad hoc, installs to `/Applications/Convertify.app` and registers it.
- `tools/bundle_tools.py`: copies ffmpeg, ffprobe, oggenc and flac from Homebrew into `Contents/MacOS` and every library they need into `Contents/Frameworks`, rewrites the load paths, re-signs, and refuses to finish if anything still points at Homebrew.
- `make_dmg.sh`: produces `Convertify.dmg` for people and `Convertify-macos-<version>.zip` for the updater.

## Building

Requirements: Xcode command line tools (Swift 6 toolchain) and Homebrew with `ffmpeg`, `flac` and `vorbis-tools`. Apple Silicon only, as built here; an Intel build would need the same done on an Intel Mac.

```bash
./build.sh
```

Testing a preset from the command line, without the Finder:

```bash
open -a /Applications/Convertify.app --args --preset mp3 /path/file.flac
```

Quit the app between such runs; a running instance ignores new arguments. Preset ids are in `Preset.all`.

Log: `~/Library/Logs/Convertify.log`, trimmed at 1 MB. History: `~/Library/Application Support/Convertify/history.json`. Preferences: domain `com.jakobrosin.convertify`.

## Adding a conversion

1. Add a `Preset` to `Preset.all` in `main.swift`, with a new `PresetKind` if the existing ones do not fit, and handle that kind in `Engine.convert` in `app.swift`.
2. Add the matching `svc` line in `build.sh` so the Finder gets a service entry, and a `svc_<id>` handler in `AppDelegate`.
3. Add it to the `groups` in the Convert menu, and describe it in the manual.

## Releasing

1. Bump the version in three places: `build.sh` (both `CFBundleVersion` keys), the About panel in `app.swift`, and the last line of the manual.
2. `./build.sh && ./make_dmg.sh`
3. Commit, tag, push, and publish:

```bash
git tag vX.Y && git push origin main vX.Y
gh release create vX.Y Convertify.dmg Convertify-macos-X.Y.zip --title "Convertify X.Y" --notes-file notes.md
```

The updater reads the GitHub Releases API, takes the newest non-draft, non-prerelease version that has a `Convertify*.zip` (or `Convertify.dmg`) asset, and verifies the download against the SHA-256 digest GitHub publishes for the asset. Release notes are shown in the update sheet as plain text, so write them for a listener. Convertify 1.3 looked for a `convertify-update.json` manifest instead; 1.4 shipped one for the last time, so that path is closed.

## How the pieces behave

- **Output naming** follows SendTo: `name.ext`, then `name-converted.ext`, `name-converted-2.ext`. Converting to the same format also lands on `-converted`. Every result is read back with ffprobe before it counts; an unreadable result is deleted and reported.
- **Video containers**: copy the video stream when the container can hold that codec, re-encode only incompatible audio to AAC; otherwise `h264_videotoolbox`, then `libx264`.
- **Window**: opens in front when a job starts (preference), quits by itself after a successful job (preference and delay), always stays open on a failure. Escape hides it without quitting; Command-W closes the key window, which quits only if it is the main window and nothing is running.
- **Notifications**: macOS refuses UserNotifications permission for an ad-hoc signed app, so the finish message goes through `osascript display notification` and shows the Script Editor icon. Sounds are played by the app.
- **First launch** (sheets on the main window, 0.7 s after launch): install into `/Applications` if running from a disk image or Downloads; trash other copies of the app found through LaunchServices; trash leftover Automator workflows from the script-era version (matched by menu title, or by their command when the plist is broken); a welcome with a Relaunch Finder button. Flags `welcomed` and `oldServicesChecked` in the preferences; delete them to see the sheets again. On a version change the app re-registers with LaunchServices, refreshes the services registry and deletes its old temp files.

## Traps that cost time

- Every `NSServices` entry needs `NSRequiredContext` with `NSServiceCategory` set to "Files and Folders", otherwise the Finder's Services menu silently drops it even though `pbs -dump` lists it.
- Never leave a second copy of the app bundle around, in `build/`, in a DMG staging folder, in Downloads. LaunchServices may register that copy and the services vanish. The scripts unregister and remove their copies; the app offers to trash duplicates.
- After changing services: `/System/Library/CoreServices/pbs -flush; pbs -update`, then relaunch the Finder.
- Do not bind Escape to a button: AppKit also sends Command-period to an Escape-bound button, and that quit the app mid-job once.
- `make_dmg.sh` runs under `zsh -e`; an unmatched glob is a fatal error there, so guard globs with `null_glob`.
- When testing with accessibility scripting: a locked screen makes System Events report zero windows for every app and stops any app from activating. Also do not `pkill` the app and relaunch it within a few seconds; quit it with AppleScript and wait.
- `URLSession` deletes a download's temporary file as soon as the completion handler returns; move it before dispatching anywhere.
