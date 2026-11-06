# Repository guidance

## Scope and structure

- `apps/windows/` is the native TSF input preview; see `docs/development/windows.md`.
  Registration and installer tests must run in isolated Windows CI sessions.
- `apps/macos/` is the macOS native application. Build scripts, resources,
  dependencies, tests, and installer templates stay with that platform.
- `website/` is portable public website source. Never add production infrastructure
  credentials or private deployment state here.
- Root `deploy/`, when present, is an ignored local operations workspace. Its scripts
  use `website/` as the source; configuration, credentials, and deployment records
  must remain untracked. Read its local README before deployment.
- `docs/platforms.md` describes future platform boundaries. Do not create empty
  abstractions or claim support for platforms that have not been implemented.
- Read the relevant source and documentation before editing. Keep changes focused.

## Communication and data

- Use English for contributor documentation, comments, and commit messages; preserve
  localized user-facing content in its own language.
- Do not log or commit API keys, user text, private endpoints, signing material,
  personal dictionaries, or diagnostic artifacts.
- Do not install, restart, or change permissions for a running input method merely
  to validate source changes. Unfinished composition is user data.
- Commit or push only when the user requests it. Do not force-push shared history.

## Validation

From the repository root, on a compatible Apple Silicon development Mac:

```bash
bash apps/macos/build.sh
python3 apps/macos/Tools/Test.py
python3 website/tools/build.py
python3 website/tools/validate.py
git diff --check
```

Read `docs/development/macos.md` for deployment targets, dependencies, and isolated
tests. Report what actually passed and what still needs manual validation. Do not
run live provider tests without considering the configured endpoint and data sent.

## Behavioral contracts

Preserve the contracts in `docs/architecture.md` and `docs/platforms.md`.
Keep the macOS physical Caps Lock state authoritative. Windows uses Shift-tap
language switching and keeps Caps Lock for capitalization; follow its platform guide.
Preserve draft text on errors, discard stale translations, and separate external
selection from composition.
Use `apps/macos/Resources/Branding.json` and localized strings for display names.
Historical persistent IDs must not be renamed without an explicit migration.
