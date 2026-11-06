# SaySpan for Windows — 0.2.1 preview

Windows 10 22H2 or Windows 11, **x64 only**. ARM64 and 32-bit applications are not
supported in this preview. The installer is an unsigned development build.

## Install and open Settings

1. Finish any draft, close applications using the previous preview, and run the
   installer. Windows may require signing out or restarting if the input DLL is
   still loaded. Do not test a new installer against an old DLL still in memory.
2. Add **SaySpan** under the Chinese (Simplified) keyboard options in Windows
   Settings if Windows has not already listed it. Use **Win+Space** to select it.
   This registration category does not restrict your configured language pair.
3. Open **Start → SaySpan Preview → SaySpan Settings**, or double-click its icon
   in the notification area. The companion also starts at sign-in.
4. In **Models**, choose Ollama and a locally installed model, or a compatible API
   with a base URL, model ID, optional API key, and reasoning effort. Use the
   refresh buttons to list models, then **Test translation** and **Save**.
   The installer includes the companion runtime, but does not install Ollama or
   download a model. Online translation sends source text to the selected service.

## Input

- The first configured language is initially active. **Tap Shift** to switch
  between the first and second languages. Holding Shift for a letter or shortcut
  does not switch. Caps Lock controls capitalization only.
- English types directly into the application, including **Shift+ABC** and `!`.
  Chinese and Japanese open the sentence/candidate panel.
- Type pinyin or Japanese romaji, use arrows to choose a candidate, then Space.
  Candidates have natural widths; long candidates wrap rather than use ellipses.
- **PgUp/PgDn** first expands the grid to three rows; subsequent presses page.
  Arrows navigate the grid and cross page boundaries. Number keys select within
  the highlighted row. Settings controls 3–9 candidates per row, default 5.
- When no candidate is pending, arrows move the sentence caret; Shift+arrows
  extend a selection. **Ctrl+A/C/X/V/Z** select, copy, cut, paste, and undo within
  the draft. Clearing the sentence closes the panel.
- **Enter** with pending spelling adds those letters to the sentence. Enter after
  candidate confirmation inserts the source sentence. **Tab** inserts a ready
  translation; it preserves the draft while translation is pending or unavailable.
- Shift+letters can add uppercase Latin words to a sentence. Chinese-mode
  punctuation uses Chinese marks. Tapping Shift during composition confirms and
  inserts the selected source before switching language.
- Common candidate choices are remembered locally and ranked on subsequent input.
  Disable or clear this memory in Input settings.

## Translation and selection

Configure **First language** and **Second language** in Languages. Composition
and selected text are translated into the other language. Selection between two
Latin languages is identified by the translation model within the same request.
The shared prompt is editable. Formatting rules preserve explicit line breaks,
blank lines, indentation, lists, Markdown, and code; actual fidelity depends on
the selected model.

Outside an editable field, select text to show a stationary **Translate** button.
Enable **Automatic** in the card or Settings to show translations immediately.
The copy control is at the top right. Click elsewhere to dismiss; reselect to
retry. Source text is never replaced. Translation is suppressed during composition
and inside editable/password fields.

Selection requires the application to expose a read-only selection through
Windows UI Automation. Some custom controls, protected/elevated applications,
and browser content do not expose this data. No clipboard-copy fallback runs
silently. The native input service keeps working if the companion is unavailable.
In restricted AppContainer hosts, source input is supported but sentence translation
through the desktop companion is unavailable; Enter can still insert the source.

## Languages and interface

Simplified/Traditional Chinese pinyin and Japanese romaji have candidate engines.
French, German, Spanish, Portuguese, Italian, Russian, Arabic, Hindi, Thai,
Vietnamese and Indonesian use Windows keyboard layouts where available. Korean
is supported as a translation language; Korean composition still needs Windows'
Korean input method. This matches the current macOS engine boundary rather than
claiming that a translation language automatically has a typing engine.

Settings and panels support English and Simplified Chinese, following Windows'
display language by default. Choose a display language in Interface settings.

## Data and uninstall

Preferences and frequency counts are stored under `HKCU\Software\SaySpan`.
API keys are scoped to their exact normalized endpoint and encrypted with Windows
DPAPI for the current user. No API key, personal dictionary, source text, or
private deployment configuration is included in the installer.

Uninstall **SaySpan (Preview)** from Windows Installed apps. Finish drafts and
close applications using the IME first. Personal preferences are retained for
reinstallation. To remove personal data too, remove `HKCU\Software\SaySpan` and
`%LOCALAPPDATA%\SaySpan` after uninstalling.
