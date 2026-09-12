# Convertify

Convert audio and video files straight from the Finder, with the keyboard, without ever opening a converter app.

Select a file, open the context menu, go to Services, and choose what you want: MP3 Encode, File to Wav, Extract Audio, File to MP4, Image to JPEG and so on. A small window shows the progress, plays a sound when it is done, and gets out of the way. Everything is built to be read and operated with VoiceOver.

## Why this exists

Converting a recording used to mean opening a converter, finding the file again in its dialog, picking a format from a list of options you have to read through every time, and then finding the output. For a blind user that is a lot of steps for something you do ten times a day.

On Windows, [Andre Louis](https://github.com/OnjLouis) and arfy solved this in 2012 with **SendTo encoders**: a set of shortcuts in the Send To menu that ran LAME, FLAC, oggenc and Opus with sensible settings, so a conversion was two keystrokes away and never needed a dialog. Andre has kept that project alive ever since. Convertify brings the same idea to the Mac, with the same conversion names and quality settings, and adds a progress window, a history, and self-updating.

## What it does

Sixteen conversions in the Finder Services menu:

- **Lossy audio:** MP3 Encode, MP3 Encode (Low Quality), AAC Encode, Opus Encode, OGG Encode.
- **Lossless and raw:** File to Wav, Extract Audio, which takes the audio out of a video without re-encoding it, Flac to Wav and Delete, Wav to Flac and Delete.
- **Video:** File to MP4, File to MOV, File to MKV, Image + Audio to Video. Streams are copied without re-encoding whenever the target container can hold them, so most of these take seconds.
- **Images:** Image to JPEG, Image to PNG.
- **Media Info:** a spoken-friendly report of what a file contains.

Every conversion accepts several files at once and any input format FFmpeg can read. Nothing is ever overwritten: a clash gets a numbered "-converted" name, and only the two conversions with "and Delete" in their name remove a source file, after the result has been verified.

The progress window is one table, one row per file: name, status, progress with time left, when it started, which conversion, and the result. Arrow keys, Home and End move through it, Return opens the output, Delete removes a row from the history, Command-I speaks the current status, Command-D shows the full details of a row. Finished files stay in the history so you can find results later.

## Installing

1. Download the latest `Convertify.dmg` from [Releases](https://github.com/jakobrosin/convertify/releases) and drag Convertify to your Applications folder.
2. Open it once. macOS will refuse, because the app is not from an identified developer. Open System Settings, go to Privacy and Security, scroll down, and choose **Open Anyway**.
3. The conversions are now in the Finder Services menu. If they do not show up right away, the welcome message offers to relaunch the Finder.

Requirements: a Mac with Apple Silicon and macOS 14 or newer. Nothing else to install; FFmpeg and the other tools are inside the app.

Convertify checks for new versions once a day when it starts and asks before installing. Updates replace the app in place and leave nothing behind. Both behaviours can be changed in Preferences.

The full manual is inside the disk image and in the app's Help menu. It covers every conversion, every shortcut, the preferences, and what to do when something does not work.

## Contributing and building

Convertify is a small Swift app with no dependencies beyond Xcode's command line tools and Homebrew. See [DEVELOPING.md](DEVELOPING.md) for how it is built, how the Finder services are registered, how a release is made, and the traps that cost time along the way.

## Credits

- **Andre Louis** ([github.com/OnjLouis](https://github.com/OnjLouis)) and **arfy** created and maintain SendTo encoders, the Windows project Convertify descends from. The conversion names, the quality settings, the output naming scheme and several 2026 features such as copying streams instead of re-encoding, lossless audio extraction, the MKV and image conversions and the media report come from there. The in-app updater is based on the one in Andre's [Clipman](https://github.com/OnjLouis/Clipman).
- **Jakob Rosin** wrote the Mac version in 2026, together with Claude, an AI assistant from Anthropic.
- The real work is done by [FFmpeg](https://ffmpeg.org), [LAME](https://lame.sourceforge.io), [Opus](https://opus-codec.org), [x264](https://www.videolan.org/developers/x264.html), and [FLAC](https://xiph.org/flac/) and [vorbis-tools](https://xiph.org/vorbis/) from the Xiph.Org Foundation.

## Licence

Convertify's own code is released under the MIT licence, see [LICENSE](LICENSE).

The disk image bundles unmodified builds of FFmpeg (GPL, because x264 is included), LAME (LGPL), Opus (BSD), x264 (GPL), FLAC (BSD and GPL) and vorbis-tools (GPL), obtained through Homebrew. They keep their own licences, their sources are available from their projects, and Convertify runs them as separate programs.
