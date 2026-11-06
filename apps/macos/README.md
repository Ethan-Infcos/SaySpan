# SaySpan for macOS

Native Objective-C / AppKit / InputMethodKit application for Apple Silicon.
This directory owns all macOS runtime code, tests, resources, and packaging.

From the repository root:

```bash
brew install librime opencc
bash apps/macos/build.sh
python3 apps/macos/Tools/Test.py
```

The quick build defaults to macOS 27 and links local Homebrew dependencies. The
portable packaging pipeline targets macOS 15+ and bundles pinned private libraries.
Read the [macOS development guide](../../docs/development/macos.md) before installing,
changing deployment targets, or building a DMG.

Generated output stays in this directory's `dist/` and `.build/`; both are ignored.
Do not commit personal Rime data, test logs, signing identities, or installer files.

The display name comes from `Resources/Branding.json`. Historical internal IDs
remain stable for compatibility with existing installations. A source-tree move
does not rename installed app data or alter the running input method.
