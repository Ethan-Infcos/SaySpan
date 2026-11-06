# macOS development

App source lives in `apps/macos/`. Unless stated otherwise, run the following commands
from that directory (`cd apps/macos` from the repository root).

## Requirements

- An Apple Silicon Mac and a logged-in graphical macOS session for AppKit tests.
- Xcode command-line tools (`xcode-select --install`), Python 3.9+, and Homebrew
  for the quick development workflow.
- CMake and Ninja for a portable dependency build.

The app's portable deployment target is macOS 15. The quick development build
currently defaults to macOS 27 because it links the development machine's Homebrew
libraries. Setting a lower app target alone does not lower a dependency's minimum OS.

## Quick development build

```bash
brew install librime opencc
bash build.sh
python3 Tools/Test.py
```

Output: `dist/SaySpan.app`. `Tools/Test.py` reads the executable name from bundle
metadata and runs nine offline suites with a new Rime data directory for each.
Logs stay in `.build/tests-*/`. Provider requests are mocked; the Keychain test creates
and deletes a unique test entry. Settings fixtures use temporary preferences or
process-only overrides. These tests do not need Ollama, an API key, or Accessibility.

You may set `IME_MIN_MACOS=15.0` when building on macOS 15 with compatible local
libraries. For repeatable deployment targets, use pinned private libraries below.

## Portable DMG

```bash
brew install cmake ninja
python3 Tools/Package.py
```

`Packaging/Dependencies.json` pins source URLs, versions, and SHA-256 hashes. The
packaging tool builds private arm64 libraries with a macOS 15 target, bundles them
and their notices, audits Mach-O architectures/load paths/deployment targets, then
runs all nine suites from a relocated app. It creates:

```text
dist/SaySpan-<version>-macOS15-arm64-unsigned.dmg
dist/SaySpan-<version>-macOS15-arm64-unsigned.dmg.sha256
```

It refuses to overwrite an existing DMG. Intermediate sources, logs, and libraries
remain in `.build/portable-arm64/`. A subsequent `--skip-dependency-build` run reuses
those libraries only when their build inputs and binary checksums match. Packaging
does not replace the installed input method. No Ollama, model weights, user data,
or credentials are included.

To compile and test using already-built private dependencies without making a DMG:

```bash
python3 Tools/BuildDependencies.py
IME_DEPENDENCY_PREFIX="$PWD/.build/portable-arm64/prefix" \
IME_OPENCC_PREFIX="$PWD/.build/portable-arm64/prefix" \
IME_MIN_MACOS=15.0 bash build.sh
python3 Tools/Test.py
```

The result of that command still references the private build libraries. Run
`Tools/Package.py` for a relocated, self-contained distribution artifact.

All current builds are ad-hoc signed and unnotarized. Signature integrity checks
are not Gatekeeper approval. Public binary distribution still needs a suitable
Developer ID signing/notarization process and clean-machine testing. Do not disable
system-wide security controls to install a development build.

## Local installation

Finish any draft, save your work, and switch to ABC before replacing an input method.

```bash
bash install.sh
# For an existing SaySpan or earlier development installation:
bash install.sh --replace
```

The script installs to `~/Library/Input Methods/SaySpan.app`; `--replace` first backs
up recognized earlier bundles under `.build/backups/`. It preserves preferences,
Keychain credentials, and learning data. It registers the input source, but does
not automatically enable it. Add **Others → SaySpan** in Keyboard settings.
A fresh login may be required on first installation.

The DMG's `Install SaySpan.pkg` also installs in the current user's Input Methods
folder. Configure your model separately after installation.

For external selection translation, add that installed app under **Privacy &
Security → Accessibility**, and enable selection translation in SaySpan's own
settings. Ad-hoc signature changes may invalidate an earlier permission grant.
Normal input-method composition does not require this permission.

## Registration diagnostics

```bash
"$HOME/Library/Input Methods/SaySpan.app/Contents/MacOS/SaySpan" --list
```

If SaySpan is missing or blank in the input-source picker, quit System Settings and
run the installed executable with `--refresh-input-source-cache`. The maintenance
command backs up the generated Keyboard Settings cache; `--register` is the separate
command for registering a bundle that has not yet been registered.
It refuses to run as root or while System Settings is open. The DMG includes the
combined registration/cache workflow as `Refresh Input Sources.command`. Neither edits the enabled
input-source list or reset Accessibility permission.

## Tests and CI

`python3 Tools/Test.py --app /path/to/SaySpan.app` runs the offline suites on a
specified build. Individual flags are `--self-test`, `--language-pair-test`,
`--typing-engine-test`, `--translation-test`, `--selection-test`,
`--localization-test`, `--japanese-test`, `--provider-test`, and `--settings-test`.

Live model tests (`--live-test`, `--translation-live-test`, `--selection-live-test`)
are opt-in and send synthetic fixture text to a configured local Ollama service.
Use a fresh `DUALIME_USER_DIR`; never run learning tests against personal data.

GitHub Actions builds the website and validates its links, then builds and runs the
offline app suites on an Apple Silicon macOS runner. CI does not publish installers,
deploy the website, use release credentials, or call live translation providers.

Before a release, also manually check real host applications, input-source addition,
Caps Lock/LED behavior, candidate and caret navigation, permissions, selection
translation, and installation on a clean Mac at the minimum supported OS version.
Automated fixtures do not prove those platform interactions.

## Website

See [website/README.md](../../website/README.md). It builds with Python's standard library.
Only its generated `dist/` output should be uploaded to a static host.
