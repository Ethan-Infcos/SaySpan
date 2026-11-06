#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
product_name=$(python3 Tools/Branding.py --name)
app_dir="$HOME/Library/Input Methods/$product_name.app"
# Historical bundle names are migration paths, never UI branding.
existing_dirs=("$app_dir" "$HOME/Library/Input Methods/Vokira.app" "$HOME/Library/Input Methods/DualLineIME.app")
codesign --verify --deep --strict "$PWD/dist/$product_name.app"
needs_backup=false
for existing in "${existing_dirs[@]}"; do
  if [ -e "$existing" ]; then
    if [ "${1:-}" != "--replace" ]; then
      printf 'Installation already exists: %s\nUse --replace to back it up and install %s.\n' "$existing" "$product_name" >&2
      exit 1
    fi
    needs_backup=true
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$existing/Contents/Info.plist")
    if [ "$identifier" != "local.inputmethod.DualLineIME" ]; then
      printf 'Refusing to replace an unrelated app: %s\n' "$existing" >&2
      exit 1
    fi
  fi
done
if [ "$needs_backup" = true ]; then
  mkdir -p "$PWD/.build/backups"
  backup_dir=$(mktemp -d "$PWD/.build/backups/input-method-XXXXXX")
  python3 - "${existing_dirs[@]}" <<'PY'
from pathlib import Path
import os
import plistlib
import signal
import subprocess
import sys
import time

executables = set()
for path in map(Path, sys.argv[1:]):
    if path.exists():
        info = plistlib.loads((path / "Contents/Info.plist").read_bytes())
        executables.add(str(path / "Contents/MacOS" / info["CFBundleExecutable"]))
pids = []
for line in subprocess.check_output(["ps", "-axo", "pid=,uid=,comm="], text=True).splitlines():
    pid, uid, command = line.strip().split(None, 2)
    if int(uid) == os.getuid() and command in executables:
        os.kill(int(pid), signal.SIGTERM)
        pids.append(int(pid))
for _ in range(50):
    alive = []
    for pid in pids:
        try:
            os.kill(pid, 0)
            alive.append(pid)
        except ProcessLookupError:
            pass
    if not alive:
        break
    time.sleep(0.1)
else:
    raise SystemExit("Previous input method did not exit; no app files were moved")
PY
  for existing in "${existing_dirs[@]}"; do
    if [ -e "$existing" ]; then mv "$existing" "$backup_dir/"; fi
  done
  printf 'Previous installation backed up in %s\n' "$backup_dir"
fi
mkdir -p "$HOME/Library/Input Methods"
ditto "dist/$product_name.app" "$app_dir"
"$app_dir/Contents/MacOS/$product_name" --register
if "$app_dir/Contents/MacOS/$product_name" --refresh-input-source-cache; then
  :
else
  printf 'The app is installed, but its picker cache was not refreshed. Quit System Settings and run:\n  "%s" --refresh-input-source-cache\n' "$app_dir/Contents/MacOS/$product_name" >&2
fi
# The menu agent can retain the previous name and icon after TIS registration changes.
killall TextInputMenuAgent 2>/dev/null || true
printf 'Installed %s\nAdd %s in System Settings > Keyboard > Text Input > Edit > + > Others.\n' "$app_dir" "$product_name"
