# SaySpan website

Portable source for [sayspan.com](https://sayspan.com), with English and Simplified
Chinese product pages and user documentation. It uses Python's standard library,
plain CSS, and browser JavaScript; no package manager or backend is required.

From the repository root, with Python 3.9 or newer:

```bash
python3 website/tools/build.py
python3 website/tools/validate.py
python3 -m http.server 8765 --bind 127.0.0.1 --directory website/dist
```

Open `http://127.0.0.1:8765/`. The root chooses a language from the browser preference;
the language switch retains the visitor's choice. `/en/` and `/zh/` are explicit routes.

## Editing

- `content/en.json`, `content/zh.json`: localized product copy and seven documentation guides.
- `site.json`: canonical origin and repository URL.
- `release.json`: development version metadata, not an installer download manifest.
- `src/assets/`: styles, interaction code, favicon, and the generated social image.
- `tools/build.py`: templates and static generation.
- `tools/validate.py`: routes, links, anchors, metadata, search indexes, and distribution checks.
- `tools/render-social.swift`: regenerate the social image on macOS with
  `swift website/tools/render-social.swift website/src/assets/social.png`.

The header includes a direct GitHub link. Download actions currently point to the
repository; installers are not hosted with the site. Interactive product examples
are illustrations and do not call a translation service.

## Hosting

Upload only `website/dist/` to a static host. Serve directory `index.html` files,
return `404.html` for missing routes, and use HTTPS. The generated content uses
same-origin assets and supports a Content Security Policy without inline scripts.
Infrastructure credentials, DNS automation, and production server configuration
are intentionally outside this public source tree.
