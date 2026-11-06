# SaySpan for Windows — input preview

This preview implements English direct typing and Simplified Chinese pinyin sentence
composition. It does not yet include translation, model settings, selection translation,
other typing engines, cloud requests, or a learned dictionary.

## Install

Use the **x64** installer for Intel/AMD Windows 10 (22H2) or Windows 11; use **ARM64**
for native ARM64 apps on Windows 11. No 32-bit binaries are provided. ARM64 builds do
not yet support x64 apps running under emulation. The preview is a development build,
not a publicly trusted signed release. Windows may display an unknown-publisher or
SmartScreen warning. Do not disable system protection to install it.

1. Finish any active composition and close the apps you will test.
2. Run the matching setup executable; administrator access is needed for TSF registration.
3. Use **Win + Space** to choose **SaySpan (Preview)**. If missing, open Windows language
   settings, add **Chinese (Simplified, China)**, and add **SaySpan (Preview)** as a
   keyboard in that language's options. Sign out and back in if Windows has cached
   the old input-source list.
4. Test in a native desktop app first. Store apps, password fields, elevated apps,
   games, and legacy input controls are outside this preview's verified scope.

The installer never changes your default input source. Remove the preview through
Windows **Installed apps → SaySpan (Preview) → Uninstall**. Close apps using it first;
Windows may require a restart to remove a loaded input-service DLL.

## Typing

| Action | Behavior |
| --- | --- |
| Caps Lock off | English direct typing, no sentence panel |
| Caps Lock on | Chinese pinyin; the keyboard light is authoritative |
| Caps Lock during a sentence | Confirm the current candidate and insert the sentence, then switch |
| Space / 1–5 / click | Choose a candidate and keep building the sentence |
| Arrow keys with pending pinyin | Move candidate highlight |
| Page Up / Page Down | Previous / next candidate page |
| Arrow keys after choosing a candidate | Move the sentence caret |
| Shift + arrows | Select part of the resolved sentence |
| Home / End | Beginning / end of resolved sentence |
| Enter with pending pinyin | Keep the typed Latin letters in the sentence, removing pinyin separators |
| Enter with no pending pinyin | Insert the completed sentence |
| Tab | Confirm/insert the sentence and let the app handle Tab |
| Shift + letters | Add uppercase Latin text to the current sentence |
| Ctrl + A / C / X / V / Z | Select, copy, cut, paste, undo within the sentence |
| Backspace / Delete | Delete spelling, selected text, or text next to the caret |
| Escape | Clear pending spelling, collapse selection, or cancel the current composition |

An empty sentence closes the panel. Changing focus confirms the source text in the
original document. Cancelling restores text that was selected before composition.
The candidate window does not take keyboard focus.

### First test

With Caps Lock **on**, type `nihao`, press **Space**, hold **Shift** to type `CAD`,
type `ceshi`, then press **Space** and **Enter**. The result should contain Chinese,
`CAD`, and Chinese again. Try Shift + Left before Enter to select and replace part
of the sentence. Turn Caps Lock **off** and verify `hello` enters directly.

Report the installer architecture, Windows version, application name/version,
exact keystrokes, expected result, and actual result. Do not include private text.

## Build

See [Windows development](../../docs/development/windows.md). This preview is separate
from the existing macOS implementation; installing it has no effect on macOS settings.
