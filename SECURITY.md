# Security and privacy reports

SaySpan is an early development project. Fixes target the current `main` branch;
there is no promised response time or long-term support schedule.

Do not post API keys, private text, personal dictionaries, or unredacted diagnostics
in a public issue. If GitHub offers **Security → Report a vulnerability** for this
repository, use that private reporting flow. Otherwise, open an issue asking for a
private contact channel without including the vulnerability details or sensitive data.

## Data boundaries

- Composition is handled through macOS InputMethodKit. The optional selection translator
  uses Accessibility to read a selection in another app.
- Text submitted for translation goes to the configured model service. An online API
  receives that text; the service's privacy policy applies. Ollama is local only when
  its configured endpoint is on the user's machine.
- API keys are stored in macOS Keychain and scoped to the normalized API base URL.
  Online API redirects are refused; remote endpoints require HTTPS, with a loopback
  exception for local development services.
- Rime learning data and app preferences are stored in the user's Library. Diagnostic
  and live-model testing should use synthetic text and isolated data directories.
- Automatic selection translation can send selected text to the configured provider
  without another click. Disable it when working with content that should not be sent.

The current packaging tools create ad-hoc-signed, unnotarized development builds.
They do not provide Developer ID signing or public-release notarization.
