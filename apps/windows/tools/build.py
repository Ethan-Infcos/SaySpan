"""Build and exercise the native Windows preview without changing the active keyboard."""
import argparse
import shutil
from pathlib import Path
from dependencies import ROOT, REPO, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=('x64', 'ARM64'), required=True)
    args = parser.parse_args()
    work = ROOT / '.build' / args.arch
    prefix = work / 'dependencies/prefix'
    build = work / 'app'
    run('cmake', '-S', ROOT, '-B', build, '-A', args.arch,
        f'-DSAYSPAN_DEPENDENCIES={prefix}')
    run('cmake', '--build', build, '--config', 'Release', '--parallel', '3')
    run('ctest', '--test-dir', build, '-C', 'Release', '--output-on-failure')
    binary = build / 'bin/Release'
    data = binary / 'data'
    data.mkdir(parents=True, exist_ok=True)
    for schema in (ROOT / 'resources').glob('*.yaml'):
        shutil.copy2(schema, data / schema.name)
    shutil.copy2(REPO / 'apps/macos/Resources/Rime/pinyin_simp.dict.yaml', data)
    deploy = work / 'dictionary-build'
    run(binary / 'runtime_tests.exe', '--deploy', data, deploy)
    shutil.copytree(deploy / 'build', data / 'build', dirs_exist_ok=True)
    run(binary / 'runtime_tests.exe', work / 'test-user')
    run(binary / 'SaySpanRegister.exe', '--register')
    try:
        run(binary / 'SaySpanRegister.exe', '--verify')
        run(binary / 'host_tests.exe')
    finally:
        run(binary / 'SaySpanRegister.exe', '--unregister')
    payload = work / 'payload'
    if payload.exists():
        shutil.rmtree(payload)
    payload.mkdir(parents=True)
    for name in ('SaySpanTip.dll', 'SaySpanRegister.exe', 'rime.dll'):
        shutil.copy2(binary / name, payload / name)
    shutil.copytree(data, payload / 'data')
    shutil.copytree(prefix / 'licenses', payload / 'licenses')
    for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
        shutil.copy2(REPO / name, payload / name)
    shutil.copy2(REPO / 'apps/macos/Vendor/rime-pinyin-simp-LICENSE', payload / 'licenses/pinyin-LICENSE')


if __name__ == '__main__':
    main()
