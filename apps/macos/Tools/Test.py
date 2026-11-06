"""Run the offline app regression suites with isolated Rime data directories."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

from Branding import product_name

ROOT = Path(__file__).resolve().parent.parent
SUITES = ("self", "language-pair", "typing-engine", "translation", "selection",
          "localization", "japanese", "provider", "settings")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "dist" / f"{product_name()}.app")
    args = parser.parse_args()
    app = args.app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    (ROOT / ".build").mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="tests-", dir=ROOT / ".build"))
    print(f"Test logs: {work}", flush=True)
    total = 0
    for suite in SUITES:
        environment = dict(os.environ, DUALIME_USER_DIR=str(work / suite))
        log = work / f"{suite}.log"
        with log.open("w") as stream:
            subprocess.run([str(executable), f"--{suite}-test"], env=environment,
                           stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=300)
        summary = re.search(r"(\d+) (?:[\w-]+ )?checks, (\d+) failures", log.read_text())
        if not summary or int(summary[2]) or not int(summary[1]):
            raise RuntimeError(f"Missing or unsuccessful test summary: {log}")
        total += int(summary[1])
        print(f"PASS {suite}: {summary[1]} checks", flush=True)
    print(f"PASS: {total} checks across {len(SUITES)} suites; no live model requests.")


if __name__ == "__main__":
    main()
