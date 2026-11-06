#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
product_name=$(python3 Tools/Branding.py --name)
dependency_prefix="${IME_DEPENDENCY_PREFIX:-$(brew --prefix)}"
minimum_macos="${IME_MIN_MACOS:-27.0}"
app_dir="${IME_APP_DIR:-$PWD/dist/$product_name.app}"
deploy_dir="${IME_DEPLOY_DIR:-$PWD/.build/deploy-data}"
opencc_prefix="${IME_OPENCC_PREFIX:-$(brew --prefix opencc)}"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources/Rime" "$deploy_dir"
clang -arch arm64 -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter \
  -Werror=unguarded-availability -Werror=unguarded-availability-new \
  "-mmacosx-version-min=$minimum_macos" \
  -I "$dependency_prefix/include" -I Sources -L "$dependency_prefix/lib" \
  -Wl,-rpath,"$dependency_prefix/lib" -Wl,-headerpad_max_install_names \
  -framework Cocoa -framework InputMethodKit -framework Carbon -framework ApplicationServices -framework NaturalLanguage -framework Security -framework LocalAuthentication -lrime \
  Sources/*.m Tests/*.m -o "$app_dir/Contents/MacOS/$product_name"
cp Resources/Rime/* "$app_dir/Contents/Resources/Rime/"
cp Vendor/rime-jaroomaji/*.yaml "$app_dir/Contents/Resources/Rime/"
mkdir -p "$app_dir/Contents/Resources/ThirdParty/rime-jaroomaji"
cp Vendor/rime-jaroomaji/LICENSE Vendor/rime-jaroomaji/README.md Vendor/rime-jaroomaji/*.txt "$app_dir/Contents/Resources/ThirdParty/rime-jaroomaji/"
cp ../../LICENSE ../../THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/ThirdParty/"
python3 Tools/BundleOpenCC.py "$opencc_prefix" "$app_dir/Contents/Resources"
cp Vendor/rime-pinyin-simp-LICENSE "$app_dir/Contents/Resources/"
swift Tools/MakeIcon.swift "$app_dir/Contents/Resources/MenuIcon.pdf" "$product_name"
for localization in Resources/*.lproj; do
  ditto "$localization" "$app_dir/Contents/Resources/$(basename "$localization")"
done
python3 Tools/Branding.py --prepare-app "$app_dir" --min-macos "$minimum_macos"
DUALIME_USER_DIR="$deploy_dir" "$app_dir/Contents/MacOS/$product_name" --deploy
for schema in dual_line dual_line_static dual_line_traditional dual_line_traditional_static vokira_japanese vokira_japanese_static vokira_japanese_kana; do
  test -s "$deploy_dir/build/$schema.schema.yaml"
done
test -s "$deploy_dir/build/vokira_japanese.table.bin"
test -s "$deploy_dir/build/vokira_japanese_kana.table.bin"
ditto "$deploy_dir/build" "$app_dir/Contents/Resources/Rime/build"
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
printf 'Built %s\n' "$app_dir"
