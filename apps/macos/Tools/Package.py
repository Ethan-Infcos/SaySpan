"""Create an unsigned test DMG for Apple Silicon Macs running macOS 15+."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

from Branding import product_name, prepare_installer

ROOT = Path(__file__).resolve().parent.parent
MINIMUM_MACOS = "15.0"


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-dependency-build", action="store_true",
                        help="Reuse the private libraries from an earlier run; audits still run.")
    args = parser.parse_args()
    os.chdir(ROOT)
    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    brand = product_name()
    name = f"{brand}-{info['CFBundleShortVersionString']}-macOS15-arm64-unsigned"
    output = ROOT / "dist" / f"{name}.dmg"
    if output.exists():
        raise FileExistsError(f"Refusing to replace an existing release: {output}")
    work = ROOT / ".build/portable-arm64"
    prefix = work / "prefix"
    if not args.skip_dependency_build:
        run(sys.executable, ROOT / "Tools/BuildDependencies.py", "--min-macos", MINIMUM_MACOS)
    stamp = json.loads((work / "dependencies-built.json").read_text())
    inputs_hash = hashlib.sha256((ROOT / "Tools/BuildDependencies.py").read_bytes() +
                                 (ROOT / "Packaging/Dependencies.json").read_bytes()).hexdigest()
    if stamp["min_macos"] != MINIMUM_MACOS or stamp["inputs_sha256"] != inputs_hash:
        raise ValueError("Private dependencies are stale; run without --skip-dependency-build")
    for path, digest in stamp["libraries"].items():
        if hashlib.sha256((prefix / path).read_bytes()).hexdigest() != digest:
            raise ValueError(f"Private library changed since build: {path}")
    stage = Path(tempfile.mkdtemp(prefix="package-", dir=work))
    print(f"Package workspace: {stage}", flush=True)
    payload = stage / "payload"
    app = payload / f"{brand}.app"
    relocated = stage / "relocation-check" / f"{brand}.app"
    try:
        environment = dict(os.environ, IME_DEPENDENCY_PREFIX=str(prefix),
                           IME_OPENCC_PREFIX=str(prefix), IME_MIN_MACOS=MINIMUM_MACOS,
                           IME_APP_DIR=str(app), IME_DEPLOY_DIR=str(stage / "deploy"))
        run("bash", ROOT / "build.sh", env=environment)
        run(sys.executable, ROOT / "Tools/BundleLibraries.py", app, "--prefix", prefix)
        # Relocation catches paths accidentally referring to the build-time app folder.
        run("ditto", app, relocated)
        for option in ("self", "language-pair", "typing-engine", "translation",
                       "selection", "localization", "japanese", "provider", "settings"):
            log = stage / f"{option}-test.log"
            test_environment = dict(os.environ, DUALIME_USER_DIR=str(stage / f"test-{option}"),
                                    DYLD_PRINT_LIBRARIES="1")
            with log.open("w") as stream:
                run(relocated / "Contents/MacOS" / brand, f"--{option}-test",
                    env=test_environment, stdout=stream, stderr=subprocess.STDOUT)
            text = log.read_text()
            loaded = [line for line in text.splitlines() if line.startswith("dyld[")]
            if not loaded:
                raise ValueError(f"Missing runtime dependency trace: {log}")
            for line in loaded:
                if "/opt/homebrew/" in line or str(prefix) in line:
                    raise ValueError(f"External library loaded: {line}")
            print(f"Passed: {option} (details: {log})", flush=True)
        component = [{"RootRelativeBundlePath": f"{brand}.app", "BundleIsRelocatable": False,
                      "BundleIsVersionChecked": True, "BundleHasStrictIdentifier": True,
                      "BundleOverwriteAction": "upgrade"}]
        component_plist = stage / "Components.plist"
        component_plist.write_bytes(plistlib.dumps(component))
        packages = stage / "packages"
        packages.mkdir()
        run("pkgbuild", "--root", payload, "--component-plist", component_plist,
            "--install-location", "/Library/Input Methods",
            "--identifier", "local.inputmethod.DualLineIME.pkg",
            "--version", f"{info['CFBundleShortVersionString']}.{info['CFBundleVersion']}",
            "--ownership", "recommended", packages / f"{brand}-component.pkg")
        installer_source = stage / "installer"
        prepare_installer(installer_source)
        distribution = ET.parse(installer_source / "Distribution.xml")
        declared_minimum = distribution.find("volume-check/allowed-os-versions/os-version").get("min")
        if declared_minimum != MINIMUM_MACOS:
            raise ValueError("Installer and application minimum OS versions differ")
        image_root = stage / "image"
        image_root.mkdir()
        installer = image_root / f"Install {brand}.pkg"
        run("productbuild", "--distribution", installer_source / "Distribution.xml",
            "--resources", installer_source / "Resources", "--package-path", packages, installer)
        shutil.copy2(installer_source / "Resources/en.lproj/ReadMe.html", image_root / "Read Me.html")
        shutil.copy2(installer_source / "Resources/zh-Hans.lproj/ReadMe.html", image_root / "安装说明.html")
        for command in installer_source.glob("*.command"):
            run("bash", "-n", command)
            shutil.copy2(command, image_root / command.name)
        output.parent.mkdir(exist_ok=True)
        run("hdiutil", "create", "-volname", f"{brand} Installer", "-srcfolder", image_root,
            "-fs", "HFS+", "-format", "UDZO", stage / f"{name}.dmg")
        run("hdiutil", "verify", stage / f"{name}.dmg")
        shutil.move(str(stage / f"{name}.dmg"), output)
        digest = hashlib.sha256(output.read_bytes()).hexdigest()
        output.with_suffix(".dmg.sha256").write_text(f"{digest}  {output.name}\n")
        print(f"Created: {output}\nSHA-256: {digest}\nValidation logs: {stage}")
    finally:
        # AppKit CLI fixtures register bundles with Launch Services. Do not leave
        # build copies competing with the user's installed input method.
        registration_tool = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        for temporary_app in (app, relocated):
            if temporary_app.exists():
                run(registration_tool, "-u", temporary_app)



if __name__ == "__main__":
    main()
