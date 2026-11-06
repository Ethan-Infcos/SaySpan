"""Build pinned, private arm64 libraries for the distributable macOS app."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parent.parent


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def fetch(dependency, work):
    name = dependency["name"]
    suffix = ".tar.xz" if dependency["url"].endswith(".xz") else ".tar.gz"
    archive = work / "downloads" / f"{name}-{dependency['version']}{suffix}"
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        partial = archive.with_suffix(archive.suffix + ".partial")
        run("curl", "--fail", "--location", "--retry", "2", "--silent",
            "--show-error", dependency["url"], "--output", partial)
        partial.rename(archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != dependency["sha256"]:
        raise ValueError(f"Checksum mismatch: {archive}")
    source = work / "sources" / name
    if not source.exists():
        temporary = work / "sources" / f"{name}-extract"
        temporary.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive) as bundle:
            # Also support the Python supplied by Apple's command-line tools.
            for member in bundle.getmembers():
                target = temporary / member.name
                if not target.resolve().is_relative_to(temporary.resolve()):
                    raise ValueError(f"Unsafe archive path: {member.name}")
                if member.issym() or member.islnk():
                    base = target.parent if member.issym() else temporary
                    if not (base / member.linkname).resolve().is_relative_to(temporary.resolve()):
                        raise ValueError(f"Unsafe archive link: {member.name}")
                elif not (member.isfile() or member.isdir()):
                    raise ValueError(f"Unsupported archive entry: {member.name}")
            run("tar", "-xf", archive, "-C", temporary)
        children = list(temporary.iterdir())
        if len(children) != 1 or not children[0].is_dir():
            raise ValueError(f"Unexpected archive layout: {archive}")
        children[0].rename(source)
        temporary.rmdir()
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, default=ROOT / ".build/portable-arm64")
    parser.add_argument("--min-macos", default="15.0")
    parser.add_argument("--fetch-only", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    prefix = work / "prefix"
    dependencies = json.loads((ROOT / "Packaging/Dependencies.json").read_text())
    sources = {}
    for dep in dependencies:
        print(f"Verifying source: {dep['name']} {dep['version']}", flush=True)
        sources[dep["name"]] = fetch(dep, work)
    if args.fetch_only:
        return
    stamp = work / "dependencies-built.json"
    stamp.unlink(missing_ok=True)
    environment = dict(os.environ, MACOSX_DEPLOYMENT_TARGET=args.min_macos,
                       PKG_CONFIG_PATH="", PKG_CONFIG_LIBDIR=str(prefix / "lib/pkgconfig"))
    common = ["-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release",
              "-DCMAKE_OSX_ARCHITECTURES=arm64",
              f"-DCMAKE_OSX_DEPLOYMENT_TARGET={args.min_macos}",
              f"-DCMAKE_INSTALL_PREFIX={prefix}", f"-DCMAKE_PREFIX_PATH={prefix}",
              f"-DCMAKE_C_FLAGS=-I{prefix / 'include'}",
              f"-DCMAKE_CXX_FLAGS=-I{prefix / 'include'}",
              f"-DCMAKE_EXE_LINKER_FLAGS=-L{prefix / 'lib'}",
              f"-DCMAKE_SHARED_LINKER_FLAGS=-L{prefix / 'lib'}",
              "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local",
              "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF",
              "-DCMAKE_FIND_USE_CMAKE_ENVIRONMENT_PATH=OFF",
              "-DCMAKE_POLICY_VERSION_MINIMUM=3.5", "-DBUILD_SHARED_LIBS=ON",
              f"-DCMAKE_BUILD_RPATH={prefix / 'lib'}",
              f"-DCMAKE_INSTALL_RPATH={prefix / 'lib'}"]
    for dep in dependencies:
        name = dep["name"]
        source = sources[name]
        if not dep.get("headers_only"):
            build = work / "build" / name
            options = dep.get("options", [])
            if name == "leveldb":
                # check_library_exists otherwise caches a miss outside standard paths.
                options = options + ["-U", "HAVE_SNAPPY"]
            if name == "librime":
                options = options + [f"-DBOOST_ROOT={sources['boost']}",
                                     "-DBoost_NO_SYSTEM_PATHS=ON",
                                     "-DBoost_NO_BOOST_CMAKE=ON",
                                     "-DCMAKE_POLICY_DEFAULT_CMP0167=OLD"]
            print(f"Building {name} for arm64 / macOS {args.min_macos}", flush=True)
            run("cmake", "-S", source, "-B", build, *common, *options, env=environment)
            run("cmake", "--build", build, "--parallel", "6", env=environment)
            run("cmake", "--install", build, env=environment)
            if name == "leveldb":
                linked = subprocess.check_output(
                    ["otool", "-L", str(prefix / "lib/libleveldb.dylib")], text=True)
                if "libsnappy" not in linked:
                    raise ValueError("LevelDB must retain Snappy support to read existing learning data")
        notices = prefix / "share/vokira-licenses" / name
        notices.mkdir(parents=True, exist_ok=True)
        license_files = [p for p in source.iterdir() if p.is_file() and
                         any(word in p.name.lower() for word in
                             ("license", "copying", "notice", "copyright", "authors"))]
        if not license_files:
            raise ValueError(f"No license found for {name}")
        for path in license_files:
            shutil.copy2(path, notices / path.name)
        for subdirectory in ("include", "deps"):
            for path in (source / subdirectory).rglob("*"):
                if path.is_file() and any(word in path.name.lower() for word in
                                         ("license", "copying", "notice", "copyright")):
                    target = notices / path.relative_to(source)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path, target)
        (notices / "SOURCE.json").write_text(json.dumps(dep, indent=2) + "\n")
    stamp.write_text(json.dumps({
        "min_macos": args.min_macos,
        "inputs_sha256": hashlib.sha256(
            Path(__file__).read_bytes() + (ROOT / "Packaging/Dependencies.json").read_bytes()
        ).hexdigest(),
        "libraries": {str(p.relative_to(prefix)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in (prefix / "lib").glob("*.dylib") if not p.is_symlink()},
    }, indent=2) + "\n")
    print(f"Built private dependencies: {prefix}")


if __name__ == "__main__":
    main()
