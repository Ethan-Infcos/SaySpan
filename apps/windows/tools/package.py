"""Create the development installer from the allowlisted, tested payload."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from dependencies import ROOT, REPO, run
from verify_registration import verify_registration


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=('x64', 'ARM64'), required=True)
    args = parser.parse_args()
    work = ROOT / '.build' / args.arch
    payload = work / 'payload'
    shutil.copy2(ROOT / 'README.md', payload / 'README.txt')
    # Hosted Windows runners include Inno Setup 6.6+; no unpinned installer download.
    compilers = [Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Inno Setup 6/ISCC.exe',
                 Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'Inno Setup 6/ISCC.exe']
    compiler = next((p for p in compilers if p.is_file()), None)
    if not compiler:
        raise RuntimeError('Install Inno Setup 6.6 or later to package the preview')
    output = REPO / 'dist/windows' / args.arch
    output.mkdir(parents=True, exist_ok=True)
    allowed = {'SaySpanTip.dll', 'SaySpanRegister.exe', 'rime.dll', 'data', 'licenses', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'README.txt'}
    if {p.name for p in payload.iterdir()} != allowed:
        raise RuntimeError('Unexpected package payload contents')
    brand = json.loads((REPO / 'apps/macos/Resources/Branding.json').read_text())['name']
    run(compiler, f'/DBrand={brand}', f'/DPayload={payload}', f'/DArch={args.arch}', f'/DOutput={output}', ROOT / 'packaging/setup.iss')
    installer = next(output.glob('*-setup.exe'))
    # Verify the actual installed copy and uninstall it on an isolated CI runner.
    target = work / 'installer-test'
    run(installer, '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', f'/DIR={target}', f'/LOG={work / "install.log"}')
    try:
        verify_registration(target / 'SaySpanRegister.exe')
        for name in ('SaySpanTip.dll', 'SaySpanRegister.exe', 'rime.dll'):
            if (target / name).read_bytes() != (payload / name).read_bytes():
                raise RuntimeError(f'Installed binary differs: {name}')
    finally:
        run(target / 'unins000.exe', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    shutil.copy2(ROOT / 'README.md', output / 'README.txt')
    digest = hashlib.sha256(installer.read_bytes()).hexdigest()
    (output / 'SHA256SUMS.txt').write_text(f'{digest}  {installer.name}\n')
    (output / 'BUILD.json').write_text(json.dumps({
        'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
        'architecture': args.arch, 'version': '0.1.0-preview',
        'signing': 'Unsigned development preview',
        'checks': ['editor', 'native Rime', 'COM registration', 'installer round-trip']
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
