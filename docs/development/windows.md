# Windows development

The first Windows preview owns its implementation under `apps/windows/`. It targets
Windows 10 22H2 / Windows 11 x64 and Windows 11 ARM64. Native host architecture must
match the DLL; x86 and emulated x64 hosts on ARM64 are not supported in this preview.

## Boundaries

- `src/editor.*`: platform-independent UTF-16 sentence buffer and interaction rules.
- `src/rime_engine.*`: Rime C API adapter, loaded from the installed module directory.
- `src/service.cpp`: COM/TSF service, document edit sessions, composition lifecycle,
  keyboard routing and explicit clipboard commands.
- `src/panel.*`: nonactivating native candidate/sentence window.
- `src/registration.cpp`, `register_main.cpp`: TSF registration and verification.
- `resources/`: minimal static pinyin schema. No personal dictionary is enabled yet.
- `tools/`: pinned dependency builds, validation and packaging.
- `packaging/`: Inno Setup installer and uninstaller.
- `tests/`: portable editor checks, native Rime and real RichEdit integration checks.

There is no networking, model worker, credential storage or translation UI yet.
These must stay outside synchronous key processing when added. Do not embed network
requests in the TSF DLL: it runs inside the client application's process.

## Build on Windows

Install Visual Studio 2022/2026 C++ build tools, the matching x64 or ARM64 tools,
Windows SDK, CMake 3.24+, Python 3.12+, and Inno Setup 6.6+. Run from the repository
root in a developer PowerShell on the target architecture:

```powershell
python apps/windows/tools/dependencies.py --arch x64
python apps/windows/tools/build.py --arch x64
python apps/windows/tools/package.py --arch x64
```

Use `ARM64` instead of `x64` on Windows ARM. The build and package scripts perform
registration round trips, so run them **only in an isolated administrator test
session**, not on a computer where you are using the installed preview. The host
test changes only its test thread's keyboard state; it does not inject global keys.

The workflow `.github/workflows/windows.yml` runs separate native x64 and ARM64 jobs.
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

The OS Caps Lock toggle is authoritative: off passes English directly to the host;
on composes pinyin. There is no menu override or temporary language mode. During
composition, Caps Lock confirms the selected source before allowing the native key
through. Candidate navigation has priority until spelling is resolved.

All document writes use TSF edit sessions with `TF_ES_ASYNCDONTCARE | TF_ES_READWRITE`,
including hosts that reject synchronous write requests. Callbacks retain their
original context and must never move a draft into another application's field.
The panel is topmost and nonactivating. It draws its own caret without inserting a
caret character into the text. Clipboard access occurs only for explicit shortcuts.

Rime is initialized once per host process and serialized through its adapter lock.
It reads precompiled dictionaries from the installed payload. Per-process writable
scratch data is under `%LOCALAPPDATA%\SaySpan\Runtime`; it contains no learned words
because this preview disables user dictionaries. Rime pins the loaded DLL until
process exit, avoiding finalization inside the Windows loader lock. Close client
apps before replacing or removing the installation.

This is an unsigned development preview for native desktop applications, not a
production release. It does not advertise secure-mode or UI-less TSF capabilities.
Password fields and disabled input contexts pass through. Store/app-container,
legacy, elevated and game compatibility need separate validation. Public signing,
ARM64EC/ARM64X host interoperability, accessibility, themes, learning and updates
remain future work. Do not disable Windows protections or auto-trust a certificate.

## Manual acceptance

Use the steps in [the preview guide](../../apps/windows/README.md). Test Notepad,
Edge/Chrome text fields, a rich editor, and the user's actual work applications on
both architectures. Check candidate position at multiple DPI settings, mixed-text
editing, selection replacement, Caps Lock while spelling is pending, switching apps,
undo/copy/paste and uninstall. Record unsupported hosts explicitly; passing native
CI is not a claim that every Windows application works.
