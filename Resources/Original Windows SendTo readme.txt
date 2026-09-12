SendTo encoders.

Started by onj, updated by arfy on 2012/01/19 7:47 NZDT, further updated by Onj on May 4th, 2013 and updated yet again by Onj on May 24th, 2013.

How to set up sendTo menu items for various encoding/decoding jobs.
Follow these instructions, substituting the command line for your encoder of choice, see below.
Copy everything in the bin folder to your windows\system32 directory. This ensures everything's in the path, no matter what system your on, and not needing to go in and change any environment variables.
Copy all the shortcuts in the shortcuts folder to your sendTo folder. This is found under \documents and settings\user name on XP, and %appdata%\Microsoft\Windows\SendTo on Vista and 7.
Copy the bat files to your windows directory.
If for whatever reason these shortcuts don't work out of the box, follow these instructions to set things up manually.


For each exe file, right click and select create shortcut. this will give you a shortcut to <exe name> in your current directory. rename this to the name given for each exe file below, Then go into the properties for each shortcut, filling out the target field as given in the instructions. 
Finally, copy these shortcuts to your sendTo folder.
now, for the encoders.

flac: flac.exe

Flac 2 Wav & delete:
%windir%\system32\flac.exe -d --delete-input-file  --keep-foreign-metadata

Wav 2 Flac & delete:
%windir%\system32\flac.exe -8 --delete-input-file -V -f  --keep-foreign-metadata


Mp3: lame.exe

note I: only an mp3 encode option is given, as it's assumed most sound editors, etc, can read mp3 natively. Also, the version of lame here can directly encode flac files as well as standard pcm wav files.

Note II: Be sure to put libsndfile-1.dll in your windows directory.

mp3 encode:
%windir%\system32\lame.exe -h -V2 -q2 -m s

Ogg encode: oggenc2.exe
note: again, only an ogg encode option is given, as it's assumed most sound editors, etc, can read ogg natively. Also, like lame, oggenc can take flac input directly and give you an ogg file.

ogg encode
%windir%\system32\oggenc2.exe -q4

AAC encode: neroAacEnc.exe

Shortcut property: %windir%\aac.bat

Note: Put aac.bat in your windows directory.

Strange we're calling a bat file yes, but the bat file tells the Nero AAC encoders to do their job and believe me, slaving over the syntax for that took the best part of a Friday evening so please, enjoy and test it heartily!


Opus encode/decode

opusdec.exe opusenc.exe
Required bat files: OpDec.bat OpEnc.bat
shortcut for Opus decode: %windir%\opdec.bat
Shortcut for Opus encode: %windir%\OpEnc.bat

Again, the two bat files go in windows, the opus exe files in windows\system32.


Well, that's it, for now. feel free to tell us about any other encoders/decoders you'd like in here, and we'll see what can be done.

