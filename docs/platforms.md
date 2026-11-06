# Platform organization

SaySpan is a multi-platform repository with one implemented platform today.

```text
apps/
  macos/          Native runtime, engines, resources, tests, and installer
docs/
  development/    Platform-specific contributor instructions
website/          Bilingual product site and user documentation
.github/          Repository automation
```

Windows and Linux are planned, not implemented. Future native applications belong
in `apps/windows/` and `apps/linux/`. Mobile input methods would also have their own
platform directories if they are pursued. There are no placeholder binaries or
claims of cross-platform support.

## What each platform owns

- Input-method registration and host text-input integration.
- Key events, composition/marked-text lifecycle, focus, caret and candidate windows.
- Accessibility or equivalent selection-reading integration and permissions.
- Secure credential storage, application preferences, and per-user learning data.
- Native UI, engine adaptation, packaging, signing, updates, and platform tests.

The current macOS framework types must not become dependencies of another platform.
For example, a Windows implementation should not need AppKit-specific models merely
to translate a sentence.

## Common behavior contracts

These requirements should be preserved across platforms, with native-keyboard
differences documented rather than silently changing behavior:

1. Configure a first and second language. Detect either language during translation
   and target the other; keep typing-engine availability explicit.
2. Do not lose a draft on cancellation, a model error, a focus change, or a shortcut.
   Key handling must remain responsive while translation runs asynchronously.
3. Keep source text separate from translated text. Insert only through a deliberate
   user action, and discard stale responses after edits or selection changes.
4. Support local Ollama and configurable compatible APIs. Keep credentials in the
   platform's secure store and keep provider selection explicit.
5. Keep external selection translation independent of active input composition;
   automatic selection translation is a user preference.
6. Make user-visible strings localizable and follow the system UI language by default.

## Shared code, when justified

There is deliberately no empty `core/` or `packages/` abstraction. The current
Objective-C implementation is macOS-specific. When a second platform is built,
first reuse the documented contracts and equivalent test fixtures. Extract a
versioned module under `packages/` only when at least two implementations need it
and it has no operating-system dependencies.

Likely candidates are provider request/response rules, prompt templates, language-pair
decisions, and localization tooling. Whether these become a shared compiled library,
portable data, or separate implementations should follow measured integration needs.
Engine libraries can remain third-party dependencies with platform adapters.

## Release boundaries

Each platform owns its build matrix and release artifacts. Platform signing material
never belongs in source control. Website deployment remains separate from app releases;
the public website source must build without production server access. Current CI
validates the website and macOS source; it does not imply future-platform readiness.
