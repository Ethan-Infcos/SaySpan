"""Single product-name source for app resources, icons, and installer templates."""
import argparse
import html
import json
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parent.parent
TOKEN = "@PRODUCT_NAME@"


def product_name():
    name = json.loads((ROOT / "Resources/Branding.json").read_text())["name"]
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9 -]*", name) or name != name.strip():
        raise ValueError("Product name must be a safe application filename")
    return name


def render(text, *, markup=False):
    name = product_name()
    return text.replace(TOKEN, html.escape(name) if markup else name)


def prepare_app(app, minimum_macos):
    info = plistlib.loads(render((ROOT / "Resources/Info.plist").read_text(), markup=True).encode())
    info["LSMinimumSystemVersion"] = minimum_macos
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info, sort_keys=False))
    resources = app / "Contents/Resources"
    for path in [*resources.glob("*.lproj/InfoPlist.strings"), *resources.glob("Rime/*.schema.yaml")]:
        text = path.read_text()
        if TOKEN in text:
            path.write_text(render(text))


def prepare_installer(destination):
    destination.mkdir(parents=True, exist_ok=True)
    source = ROOT / "Packaging"
    for path in [source / "Distribution.xml", *sorted((source / "Resources").rglob("*.html"))]:
        output = destination / path.relative_to(source)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(render(path.read_text(), markup=True))
    for path in sorted(source.glob("*.command")):
        output = destination / path.name
        output.write_text(render(path.read_text()))
        output.chmod(0o755)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", action="store_true")
    parser.add_argument("--prepare-app", type=Path)
    parser.add_argument("--min-macos", default="15.0")
    args = parser.parse_args()
    if args.name:
        print(product_name())
    if args.prepare_app:
        prepare_app(args.prepare_app, args.min_macos)
