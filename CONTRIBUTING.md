# Contributing to SaySpan

Bug reports, documentation fixes, translations, and focused pull requests are welcome.
For a new input engine or a change to keyboard behavior, open an issue to discuss the
interaction first. Translation support and typing-engine support are different capabilities.

## Development

Follow the [build guide](docs/development/macos.md), then run:

```bash
python3 apps/macos/Tools/Test.py
python3 website/tools/build.py
python3 website/tools/validate.py
git diff --check
```

Use a logged-in macOS session for AppKit tests. The provider suite uses mocked HTTP
responses and a temporary, uniquely named Keychain entry. It does not call a paid API.
Tests use isolated Rime data; do not point them at your normal learning directory.
Live-model tests are separate and opt-in.

Keep pull requests small. Explain the behavior before and after the change, how you
tested it, and any remaining limitations. Add regression coverage for behavior changes;
do not count UI or permission checks as verified unless you actually performed them.

## Project conventions

- Use English for code identifiers, new comments, commit messages, and contributor documentation.
- Follow the surrounding Objective-C and Python style; avoid unrelated formatting changes.
- Add user-facing text to both `apps/macos/Resources/en.lproj/Localizable.strings` and
  `apps/macos/Resources/zh-Hans.lproj/Localizable.strings`. Use `L()` / `LF()` and the existing
  `{appName}` substitution instead of embedding the product name in interface strings.
- `apps/macos/Resources/Branding.json` owns application branding. Legacy bundle, preferences,
  Keychain, and Rime IDs are persisted compatibility contracts, not display names.
- Keep physical Caps Lock authoritative. Finish a draft before changing its typing
  language; do not reintroduce menu-driven or temporary draft language switching.
- Do not add global keyboard hooks or clipboard replacement to normal composition.
- Do not commit credentials, logs, personal dictionaries, installer artifacts, or
  private deployment files. Review the actual staged files before pushing.
- Preserve dependency licenses, source provenance, and checksums when updating vendors.

## Reporting problems

Include the app version, macOS version, host application, language pair, provider/model
(without API keys), steps to reproduce, and expected/actual behavior. Use a harmless
sample sentence. Crop or redact screenshots and review logs before attaching them.
See [SECURITY.md](SECURITY.md) for sensitive reports.

Contributions are made under the repository's MIT license, except for separately
licensed third-party material, whose original terms must be preserved.
