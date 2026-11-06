"""Build checksum-pinned Rime dependencies natively on Windows x64 or ARM64."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
sys.path.insert(0, str(REPO / 'apps/macos/Tools'))
from BuildDependencies import fetch


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=('x64', 'ARM64'), required=True)
    args = parser.parse_args()
    work = ROOT / '.build' / args.arch / 'dependencies'
    prefix = work / 'prefix'
    deps = json.loads((REPO / 'apps/macos/Packaging/Dependencies.json').read_text())
    deps = [d for d in deps if d['name'] not in ('gflags', 'glog')]
    inputs = hashlib.sha256(Path(__file__).read_bytes() + json.dumps(deps).encode()).hexdigest()
    stamp = work / 'stamp.json'
    if stamp.exists() and json.loads(stamp.read_text()).get('inputs') == inputs:
        print(f'Reusing verified build inputs: {prefix}', flush=True)
        return
    sources = {d['name']: fetch(d, work) for d in deps}
    options = {
        'yaml-cpp': ['-DYAML_CPP_BUILD_TESTS=OFF', '-DYAML_CPP_BUILD_TOOLS=OFF', '-DYAML_MSVC_SHARED_RT=OFF'],
        'snappy': ['-DSNAPPY_BUILD_TESTS=OFF', '-DSNAPPY_BUILD_BENCHMARKS=OFF'],
        'leveldb': ['-DLEVELDB_BUILD_TESTS=OFF', '-DLEVELDB_BUILD_BENCHMARKS=OFF'],
        'marisa': ['-DBUILD_TESTING=OFF', '-DENABLE_TOOLS=OFF'],
        'opencc': [f'-DCMAKE_CXX_FLAGS=/I"{prefix / "include"}"', '-DUSE_SYSTEM_MARISA=ON', '-DENABLE_GTEST=OFF', '-DBUILD_TESTING=OFF', '-DBUILD_OPENCC_JIEBA_PLUGIN=OFF'],
        'librime': ['-DBUILD_STATIC=ON', '-DBUILD_SHARED_LIBS=ON', '-DBUILD_TEST=OFF', '-DBUILD_DATA=OFF',
                    '-DENABLE_LOGGING=OFF', '-DBUILD_MERGED_PLUGINS=OFF', '-DENABLE_EXTERNAL_PLUGINS=OFF',
                    '-DBoost_NO_BOOST_CMAKE=ON', '-DCMAKE_POLICY_DEFAULT_CMP0167=OLD',
                    f'-DBOOST_ROOT={sources["boost"]}'],
    }
    for dep in deps:
        name = dep['name']
        source = sources[name]
        if not dep.get('headers_only'):
            build = work / 'build' / name
            print(f'Building {name} ({args.arch})', flush=True)
            run('cmake', '-S', source, '-B', build, '-A', args.arch,
                '-DCMAKE_POLICY_VERSION_MINIMUM=3.5', '-DCMAKE_BUILD_TYPE=Release',
                '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded', '-DBUILD_SHARED_LIBS=OFF',
                f'-DCMAKE_PREFIX_PATH={prefix}', f'-DCMAKE_INSTALL_PREFIX={prefix}', *options[name])
            run('cmake', '--build', build, '--config', 'Release', '--parallel', '3')
            run('cmake', '--install', build, '--config', 'Release')
        notices = prefix / 'licenses' / name
        notices.mkdir(parents=True, exist_ok=True)
        files = [p for p in source.iterdir() if p.is_file() and any(k in p.name.lower() for k in ('license', 'copying', 'notice', 'authors', 'copyright'))]
        if not files:
            raise RuntimeError(f'No license found for {name}')
        for p in files:
            shutil.copy2(p, notices / p.name)
        for directory in ('include', 'deps'):
            for p in (source / directory).rglob('*'):
                if p.is_file() and any(k in p.name.lower() for k in ('license', 'copying', 'notice', 'copyright')):
                    out = notices / p.relative_to(source)
                    out.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(p, out)
        (notices / 'SOURCE.json').write_text(json.dumps(dep, indent=2) + '\n')
    for name in ('rapidjson-1.1.0-LICENSE', 'rapidjson-1.1.0-SOURCE.txt'):
        shutil.copy2(REPO / 'apps/macos/Vendor' / name, prefix / 'licenses/opencc' / name)
    stamp.write_text(json.dumps({'inputs': inputs, 'arch': args.arch}) + '\n')


if __name__ == '__main__':
    main()
