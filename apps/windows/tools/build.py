"""Build and exercise the native Windows preview without changing the active keyboard."""
import argparse
import os
import json
import shutil
from pathlib import Path
from dependencies import ROOT, REPO, run
from verify_registration import verify_registration


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
    for name in ('vokira_japanese.schema.yaml', 'vokira_japanese_static.schema.yaml', 'vokira_japanese_kana.schema.yaml', 'vokira_japanese.dict.yaml', 'vokira_japanese_kana.dict.yaml'):
        text = (REPO / 'apps/macos/Resources/Rime' / name).read_text()
        text = text.replace('@PRODUCT_NAME@', json.loads((REPO / 'apps/macos/Resources/Branding.json').read_text())['name'])
        (data / name).write_text(text, encoding='utf-8')
    for source in (REPO / 'apps/macos/Vendor/rime-jaroomaji').glob('*.yaml'):
        shutil.copy2(source, data)
    shutil.copytree(prefix / 'share/opencc', data / 'opencc', dirs_exist_ok=True)
    deploy = work / 'dictionary-build'
    run(binary / 'runtime_tests.exe', '--deploy', data, deploy)
    shutil.copytree(deploy / 'build', data / 'build', dirs_exist_ok=True)
    run(binary / 'runtime_tests.exe', work / 'test-user')
    os.environ['SAYSPAN_TEST_NO_COMPANION'] = '1'
    run(binary / 'SaySpanRegister.exe', '--register')
    try:
        verify_registration(binary / 'SaySpanRegister.exe')
        run(binary / 'host_tests.exe')
    finally:
        run(binary / 'SaySpanRegister.exe', '--unregister')
    payload = work / 'payload'
    if payload.exists():
        shutil.rmtree(payload)
    payload.mkdir(parents=True)
    for name in ('SaySpanTip.dll', 'SaySpanRegister.exe', 'rime.dll'):
        shutil.copy2(binary / name, payload / name)
    companion = ROOT / 'companion'
    run('dotnet', 'run', '--project', companion / 'Tests/SaySpan.Core.Tests.csproj', '--configuration', 'Release')
    run('dotnet', 'publish', companion / 'SaySpan.Companion.csproj', '--configuration', 'Release', '--runtime', 'win-x64', '--self-contained', 'true', '-o', payload / 'companion')
    run(payload / 'companion/SaySpan.exe', '--self-test')
    shutil.copytree(data, payload / 'data')
    shutil.copytree(prefix / 'licenses', payload / 'licenses')
    for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
        shutil.copy2(REPO / name, payload / name)
    shutil.copytree(REPO / 'apps/macos/Vendor/rime-jaroomaji', payload / 'licenses/rime-jaroomaji', ignore=shutil.ignore_patterns('*.yaml'))
    shutil.copy2(REPO / 'apps/macos/Vendor/rime-pinyin-simp-LICENSE', payload / 'licenses/pinyin-LICENSE')


if __name__ == '__main__':
    main()
