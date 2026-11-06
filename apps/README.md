# Platform applications

Each application owns its operating-system integration, build tools, resources,
tests, permissions, credentials, and installer.

| Directory | Status |
| --- | --- |
| [macos/](macos/) | Current native macOS InputMethodKit application |

Add future applications as `windows/` and `linux/` when implementation starts.
Do not add empty projects or describe planned platforms as downloadable products.
See [platforms.md](../docs/platforms.md) for the common behavior contracts and
criteria for extracting shared code.
