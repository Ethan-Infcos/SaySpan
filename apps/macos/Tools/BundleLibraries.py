"""Embed private dylibs, rewrite load paths, and audit the distributable app."""
import argparse
from pathlib import Path
import plistlib
import re
import shutil
import subprocess


def output(*args):
    return subprocess.check_output([str(a) for a in args], text=True)


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def dependencies(binary):
    return [line.strip().split(" (compatibility", 1)[0]
            for line in output("otool", "-L", binary).splitlines()[1:]]


def system_library(path):
    return path.startswith(("/System/Library/", "/usr/lib/"))


def rpaths(binary):
    lines = output("otool", "-l", binary).splitlines()
    for index, line in enumerate(lines):
        if line.strip() == "cmd LC_RPATH":
            yield lines[index + 2].strip().split("path ", 1)[1].rsplit(" (offset", 1)[0]


def version(value):
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def audit(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    frameworks = app / "Contents/Frameworks"
    binaries = [executable, *sorted(frameworks.glob("*.dylib"))]
    for binary in binaries:
        if output("lipo", "-archs", binary).strip() != "arm64":
            raise ValueError(f"Unexpected architecture: {binary}")
        build = output("xcrun", "vtool", "-show-build", binary)
        minimum = re.search(r"\bminos ([\d.]+)", build)
        if not minimum or version(minimum[1]) > version(info["LSMinimumSystemVersion"]):
            raise ValueError(f"Incompatible deployment target: {binary}\n{build}")
        for path in dependencies(binary):
            if system_library(path):
                continue
            if path.startswith("@loader_path/"):
                resolved = binary.parent / path[len("@loader_path/"):]
            elif path.startswith("@executable_path/"):
                resolved = executable.parent / path[len("@executable_path/"):]
            elif path == f"@rpath/{binary.name}" and binary != executable:
                continue  # The library's own install ID, not a dependency.
            else:
                raise ValueError(f"External dependency in {binary.name}: {path}")
            if not resolved.resolve().is_relative_to(app.resolve()) or not resolved.is_file():
                raise ValueError(f"Unresolved bundled dependency: {path}")
        if list(rpaths(binary)):
            raise ValueError(f"Unexpected runtime search path in {binary}")
    print(f"Audited {len(binaries)} arm64 binaries: macOS {info['LSMinimumSystemVersion']}+, bundled or system dependencies only.")


def bundle(app, prefix):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    frameworks = app / "Contents/Frameworks"
    frameworks.mkdir(exist_ok=True)
    queue = [executable]
    visited = set()
    names = {}
    while queue:
        original = queue.pop(0)
        if original in visited:
            continue
        visited.add(original)
        destination = executable if original == executable else frameworks / original.name
        if original != executable:
            shutil.copy2(original, destination)
            destination.chmod(0o755)
            run("install_name_tool", "-id", f"@rpath/{destination.name}", destination)
        for path in dependencies(original):
            if system_library(path):
                continue
            if path.startswith("@rpath/"):
                resolved = prefix / "lib" / path[len("@rpath/"):]
            elif path.startswith("@loader_path/"):
                resolved = original.parent / path[len("@loader_path/"):]
            else:
                resolved = Path(path)
            resolved = resolved.resolve()
            if resolved == original:
                continue
            if not resolved.is_relative_to(prefix) or not resolved.is_file():
                raise ValueError(f"Dependency outside private prefix: {path}")
            if resolved.name in names and names[resolved.name] != resolved:
                raise ValueError(f"Conflicting library basename: {resolved.name}")
            names[resolved.name] = resolved
            replacement = ("@executable_path/../Frameworks/" if original == executable
                           else "@loader_path/") + resolved.name
            run("install_name_tool", "-change", path, replacement, destination)
            queue.append(resolved)
        for path in list(rpaths(destination)):
            run("install_name_tool", "-delete_rpath", path, destination)
    notices = app / "Contents/Resources/ThirdParty/Libraries"
    shutil.copytree(prefix / "share/vokira-licenses", notices, dirs_exist_ok=True)
    # OpenCC's source archive retains RapidJSON headers but omits its license file.
    vendor = Path(__file__).resolve().parent.parent / "Vendor"
    shutil.copy2(vendor / "rapidjson-1.1.0-LICENSE", notices / "opencc/rapidjson-1.1.0-LICENSE")
    shutil.copy2(vendor / "rapidjson-1.1.0-SOURCE.txt", notices / "opencc/rapidjson-1.1.0-SOURCE.txt")
    audit(app)
    for library in sorted(frameworks.glob("*.dylib")):
        run("codesign", "--force", "--sign", "-", library)
    run("codesign", "--force", "--sign", "-", app)
    run("codesign", "--verify", "--deep", "--strict", app)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--prefix", type=Path)
    args = parser.parse_args()
    if args.prefix:
        bundle(args.app.resolve(), args.prefix.resolve())
    else:
        audit(args.app.resolve())
