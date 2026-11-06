# Windows development

The Windows preview owns its implementation under `apps/windows/`. It targets
Windows 10 22H2 / Windows 11 x64. ARM64 is deferred after native application-routing
tests failed on its runner; no ARM64 installer is shipped. There is no x86 support.

## Boundaries

- `src/editor.*`: platform-independent UTF-16 sentence buffer and interaction rules.
- `src/rime_engine.*`: Rime C API adapter, loaded from the installed module directory.
- `src/service.cpp`: COM/TSF service, document edit sessions, composition lifecycle,
  keyboard routing and explicit clipboard commands.
- `src/panel.*`: nonactivating native candidate/sentence window.
- `src/registration.cpp`, `register_main.cpp`: TSF registration and verification.
- `resources/`: Chinese schemas; Japanese and OpenCC data reuse pinned macOS resources.
- `tools/`: pinned dependency builds, validation and packaging.
- `packaging/`: Inno Setup installer and uninstaller.
- `tests/`: portable editor checks, native Rime and real RichEdit integration checks.

Translation, settings, credential storage, and selection monitoring live in the
companion process. Do not embed network requests in the TSF DLL: it runs inside
the client application's process.

## Build on Windows

Install Visual Studio 2022/2026 C++ build tools, the matching x64 or ARM64 tools,
Windows SDK, CMake 3.24+, Python 3.12+, .NET 10 SDK, and Inno Setup 6.6+. Run from the repository
root in a developer PowerShell on the target architecture:

```powershell
python apps/windows/tools/dependencies.py --arch x64
python apps/windows/tools/build.py --arch x64
python apps/windows/tools/package.py --arch x64
```

The architecture-aware build code is retained for future ARM64 work, but only x64
is a current preview target. The build and package scripts perform
registration round trips, so run them **only in an isolated administrator test
session**, not on a computer where you are using the installed preview. The host
test changes only its test thread's keyboard state; it does not inject global keys.

The workflow `.github/workflows/windows.yml` runs native x64 checks.
Dependency archives reuse the SHA-256-pinned manifest in
`apps/macos/Packaging/Dependencies.json`; the Windows build does not depend on AppKit
or macOS binaries. Source notices are copied into the payload. The pinyin dictionary
and its Apache license reuse the existing vendored copy.

Outputs live under ignored `apps/windows/.build/` and `dist/windows/`. Only the
allowlisted payload goes into the installer. Private `deploy/`, credentials, test
user directories and build logs must never enter an artifact.

Portable editor checks can also run on macOS/Linux:

```sh
cmake -S apps/windows -B .build/windows-editor
cmake --build .build/windows-editor
ctest --test-dir .build/windows-editor --output-on-failure
```

## Lifecycle and limits

Windows uses a short, unmodified Shift tap to switch the configured language pair;
it starts in the first language (English by default). Shift used in a chord, or held longer than 500 ms, does not
change the language. Shift + arrows select sentence text, and Shift + letters retain
normal capitalization. Caps Lock only controls capitalization. This intentionally
differs from the macOS Caps Lock contract. Tapping Shift during composition confirms
and inserts the source text before changing mode. Candidate navigation has priority
until spelling is resolved.

All document writes use TSF edit sessions with `TF_ES_ASYNCDONTCARE | TF_ES_READWRITE`,
including hosts that reject synchronous write requests. Callbacks retain their
original context and must never move a draft into another application's field.
The panel is topmost and nonactivating. It draws its own caret without inserting a
caret character into the text. Clipboard access occurs only for explicit shortcuts.

Rime is initialized once per host process and serialized through its adapter lock.
It reads precompiled dictionaries from the installed payload. Per-process writable
scratch data is under `%LOCALAPPDATA%\SaySpan\Runtime`; it contains no learned words
because Rime user dictionaries are disabled. AppContainer hosts use their own
container-local data directory instead. Frequencies are stored separately in HKCU. Rime pins the loaded DLL until
process exit, avoiding finalization inside the Windows loader lock. Close client
apps before replacing or removing the installation.

This is an unsigned development preview for native desktop applications, not a
production release. It does not advertise secure-mode or UI-less TSF capabilities.
Password fields and disabled input contexts pass through. The service registers the modern-app (immersive) capability and owns its candidate
window through the TSF context view, with IME visibility events. A CI AppContainer
fixture checks Chinese/Japanese dictionaries using container-local scratch storage.
Restricted hosts keep source input but cannot use the desktop companion pipe; no
container permission is bypassed. Actual Windows Settings, other packaged apps,
legacy, elevated and game compatibility still require application-level validation. Public signing,
ARM64EC/ARM64X host interoperability, additional accessibility coverage, themes and updates
remain future work. Do not disable Windows protections or auto-trust a certificate.

## Manual acceptance

Use the steps in [the preview guide](../../apps/windows/README.md). Test Notepad,
Edge/Chrome text fields, a rich editor, and the user's actual work applications on
x64. Check candidate position at multiple DPI settings, mixed-text
editing, selection replacement, Shift switching while spelling is pending, switching apps,
undo/copy/paste and uninstall. Record unsupported hosts explicitly; passing native
CI is not a claim that every Windows application works.

## Windows 0.2 companion and translation boundary

`companion/Core` is a portable .NET translation/protocol library with synthetic
provider tests. `companion` is a self-contained x64 desktop process containing
Settings, a notification-area entry, UI Automation selection monitoring, and the
HTTP client. It has no keyboard hook and never receives API credentials from the
input DLL. User-facing branding comes from the shared Branding.json resource.

The native TSF DLL retains input, Rime, draft editing, and candidate rendering.
A bounded worker exchanges length-prefixed UTF-16 frames with a same-user,
same-session named pipe. The client verifies the server executable path before
sending source text. HTTP requests run only in the companion. Draft changes
invalidate request generations; disconnects cancel provider work, and stale
results cannot replace current drafts. Provider failure leaves the source intact.
No credentials or source text are logged. Redirects are disabled for API requests.

Preferences are independent registry values. Settings writes only changed fields;
card toggles cannot be reverted by an unrelated Save from an older Settings view.
API credentials use current-user DPAPI and an endpoint-derived lookup key.
Selection monitoring runs off the UI thread, requires read-only UI Automation
text, and checks an expiring composition activity signal. It never synthesizes
copy or pastes into source applications. Capture is re-armed on startup and when
either selection option changes. The foreground boundary follows UI Automation
ancestry, including embedded providers from another process.

Rime sessions remain process-local. Shared LevelDB dictionaries are deliberately
not opened concurrently by every TSF host. Candidate frequency ranking persists
small per-spelling counts in HKCU, with an off switch and reset. The frontend
browses the first 200 Rime candidates with configurable compact/expanded pages.
Japanese tables and OpenCC data are copied from pinned, licensed dependencies.

The pipeline additionally publishes the self-contained companion, runs its
settings/credential/state-coherence self-tests, and performs a real RichEdit TSF
→ companion → synthetic loopback HTTP → translated Tab insertion integration
check. It then installs, verifies, and uninstalls the actual setup executable.
These isolated checks do not establish compatibility with every Windows app;
Notepad, Edge/Chrome, Office, Electron apps, display scaling, and actual provider
latency require desktop testing. ARM64 remains deferred.
