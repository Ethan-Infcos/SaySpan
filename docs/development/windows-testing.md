# Windows preview acceptance checklist

Use a disposable document in each application. Record Windows version, application
version, selected provider/model, and the exact sequence for a failure. Do not send
API keys, confidential source text, or personal dictionary files with reports.

| Area | Test | Expected result |
| --- | --- | --- |
| Settings | Start → SaySpan Preview → SaySpan Settings | Six settings pages; Models first |
| English | Hold Shift and type `ABC`, then `1` | `ABC!` appears directly; language does not switch |
| Switching | Tap Shift, type `nihao`, tap Shift | Selected Chinese source is inserted, then English is active |
| Candidates | Type `shi`; PgDn; arrows across row/page boundaries | Three rows; visible highlight; no loss of spelling |
| Candidate sizing | Change columns to 3, 5, then 9 | Count changes on new input; long choices wrap |
| Editing | Confirm `nihao`, Shift+Left, type a replacement | Only the selected sentence portion changes |
| Clipboard | Ctrl+A/C/X/V/Z in a draft | Commands affect the draft; panel remains until empty |
| Mixed text | Type `nihao`, Space, hold Shift and type `CAD` | Chinese and Latin text coexist in the sentence |
| Raw spelling | Type `ceshi`, Enter | Literal `ceshi` joins the sentence; next Enter inserts source |
| Translation | Confirm a sentence, wait for result, Tab | Translated text is inserted exactly once |
| Slow service | Tab while translation is pending | Draft remains; no empty insertion or focus jump |
| Stale result | Change the sentence while a request is pending | Old translation never replaces the new sentence |
| Failure | Stop Ollama or use a deliberately invalid model | Source remains editable; error appears without a crash |
| Models | Refresh local/online models, test, save | List populates; next request uses the chosen model |
| Credentials | Save one endpoint's key, change endpoint | The old key is not reused for the new endpoint |
| Japanese | Select Japanese as second language, type `nihon` | Japanese candidates appear, not only Latin letters |
| Traditional | Select Traditional Chinese, type `hanyu` | Traditional candidates such as `漢語` appear |
| Frequency | Repeatedly choose a lower candidate, restart the host | That candidate ranks higher for the same spelling |
| Selection | Select message/article text outside an editor | Stationary Translate button appears |
| Automatic | Enable Automatic, dismiss, reselect | Translation card appears without another click |
| Coherence | Keep Settings open, toggle Automatic in card, save unrelated setting | Card choice remains saved |
| Suppression | Select or compose text inside an editable/password field | No external selection card |
| Formatting | Translate text containing blank lines, indentation and a list | Structure remains, subject to model output quality |
| Focus | Switch apps while composing; finish in the original app | Draft does not move to another application's field |
| Interface | Change English/Chinese/System, reopen settings | Labels use the selected/system language |
| Upgrade | Close drafts/apps, install new build, restart if requested | New version runs; settings remain |

Run these in Notepad, Edge/Chrome, a rich editor/Office, and the user's Electron
applications. Check 100%, 150%, and 200% scaling and monitors with different DPI.
Selection compatibility depends on UI Automation providers and is not established
by a successful input test. The portable tests and CI fixtures cover deterministic
behavior; they do not replace this application matrix.
