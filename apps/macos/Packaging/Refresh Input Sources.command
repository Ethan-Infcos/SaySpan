#!/bin/bash
set -euo pipefail
app="$HOME/Library/Input Methods/@PRODUCT_NAME@.app"
executable="$app/Contents/MacOS/@PRODUCT_NAME@"
if [ ! -x "$executable" ]; then
  printf 'Install @PRODUCT_NAME@ for this user before running this command.\n' >&2
  exit 1
fi
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
if [ "$identifier" != 'local.inputmethod.DualLineIME' ]; then
  printf 'The installed app has an unexpected identity; no changes made.\n' >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app"
"$executable" --register
"$executable" --refresh-input-source-cache
/usr/bin/open 'x-apple.systempreferences:com.apple.Keyboard-Settings.extension'
