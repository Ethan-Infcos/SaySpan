"""Bundle the installed OpenCC s2t configuration and only its required data."""
import json
from pathlib import Path
import shutil
import sys

prefix, resources = map(Path, sys.argv[1:])
source = prefix / "share/opencc"
destination = resources / "Rime/opencc"
destination.mkdir(parents=True, exist_ok=True)
configuration = json.loads((source / "s2t.json").read_text())


def files(value):
    if isinstance(value, dict):
        if "file" in value:
            yield value["file"]
        for child in value.values():
            yield from files(child)
    elif isinstance(value, list):
        for child in value:
            yield from files(child)


for name in {"s2t.json", *files(configuration)}:
    if Path(name).name != name:
        raise ValueError(f"Unexpected OpenCC data path: {name}")
    shutil.copy2(source / name, destination / name)
notices = prefix / "share/vokira-licenses/opencc"
if not notices.exists():
    notices = prefix
shutil.copy2(notices / "LICENSE", resources / "OpenCC-LICENSE")
shutil.copy2(notices / "AUTHORS", resources / "OpenCC-AUTHORS")
