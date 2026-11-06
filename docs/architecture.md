# Architecture

SaySpan is currently one native macOS InputMethodKit application, implemented primarily
in Objective-C. It is a working prototype, not a cross-platform input-method framework.
Other platforms will need their own host integration and input lifecycle handling.

The repository separates platform applications (`apps/`), documentation (`docs/`),
and the public website (`website/`). This section describes files relative to
`apps/macos/`; see [platforms.md](platforms.md) for future platform boundaries.

## Main boundaries

| Area | Files | Responsibility |
| --- | --- | --- |
| Host integration | `Sources/Main.m`, `InputController.m` | InputMethodKit session, key events, marked text, insertion, input-menu commands |
| Composition | `Composition.m`, `SentenceView.m`, `CandidateListView.m` | Draft, selection, undo, candidate navigation, caret, source/translation rows |
| Input engines | `PinyinEngine.m`, `KeyboardLayoutEngine.m`, `InputLanguages.m` | Rime sessions, macOS keyboard layouts, language pair and Caps Lock mapping |
| Translation | `Translation.m`, `TranslationLayout.m`, `ModelProvider.m` | Language detection, prompts, asynchronous requests, result validation and layout |
| Credentials | `ModelCredentials.m` | Endpoint-scoped macOS Keychain storage |
| Selection translation | `SelectionReader.m`, `SelectionWebAccessibility.m`, `SelectionTranslation.m`, `SelectionOverlay.m` | External selection discovery, editable-field suppression, request lifecycle and floating UI |
| Settings and UI language | `Settings.m`, `ModelPreferencesView.m`, `Localization.m` | Persistence, model configuration, immediate selection toggles, localized strings |
| Registration | `InputSourceRegistration.m` | Input-source registration and guarded repair of the generated Keyboard Settings cache |

## Invariants to preserve

1. Caps Lock off selects the first configured language; on selects the second. The
   physical keyboard state is authoritative. Changing it while composing confirms
   the active source candidate and inserts the source before changing languages.
2. English is direct typing. A translation language being available does not imply
   that its native typing engine is implemented. Chinese and Japanese use candidates;
   additional scripts use supported native layouts where available.
3. While candidates are pending, arrow keys control candidates. Once resolved, they
   control the sentence caret; Shift + arrows extends the sentence selection.
4. Translation must not block key handling. A stale or cancelled request must not
   replace a newer draft or selection. Failed requests must not erase source text.
5. Composition and selection translation are separate lifecycles. An input method's
   marked text is not a user request for the external selection translator.
6. Selection enable/automatic switches apply immediately. Saving unrelated settings
   must not overwrite a newer selection preference from the translation card.

## Persistent identity

The display name is generated from `Resources/Branding.json`. Identifiers containing
`DualLineIME`, `dual_line`, or `vokira` remain intentionally stable for preferences,
Keychain entries, input-source registration, Rime schemas, and learned vocabulary.
Renaming them requires a tested migration; changing display branding does not.

## Testing boundaries

Nine executable regression suites cover composition, language pairs, engine behavior,
translation formatting, external-selection state, localization, Japanese conversion,
provider transport/credentials, and settings. See [macOS development](development/macos.md).
These checks complement hands-on testing of focus changes, real applications,
Accessibility permission, the physical Caps Lock key, and fresh installations.

## Website

The root `website/` directory contains a Python-generated bilingual static site. It has no application
backend or access to typed text. Public website builds are independent of private
server deployment and model credentials.
