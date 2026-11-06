# Third-party notices

The MIT license at the repository root applies to original SaySpan code, not to the
separately licensed material listed below. Retain upstream copyright and license
notices when redistributing source or binaries.

## Material included in this repository

| Material | Upstream and revision | License / notices |
| --- | --- | --- |
| `apps/macos/Resources/Rime/pinyin_simp.dict.yaml` | [rime/rime-pinyin-simp](https://github.com/rime/rime-pinyin-simp), `0c6861ef7420ee780270ca6d993d18d4101049d0` | [Apache 2.0](apps/macos/Vendor/rime-pinyin-simp-LICENSE); dictionary header credits Android PinyinIME |
| Japanese schema and tables in `apps/macos/Vendor/rime-jaroomaji/` | [lazyfoxchan/rime-jaroomaji](https://github.com/lazyfoxchan/rime-jaroomaji), `b743307c0251f388976662ee2f9e267043785116` | [Apache 2.0](apps/macos/Vendor/rime-jaroomaji/LICENSE), with additional dictionary notices below |
| Mozc-derived Japanese dictionary | Same pinned jaroomaji source | [MOZC-NOTICES.txt](apps/macos/Vendor/rime-jaroomaji/MOZC-NOTICES.txt) preserves the Google, IPAdic/NAIST, and ICOT notices; the original header is also retained in the dictionary |
| RapidJSON license text for OpenCC's bundled headers | [Tencent/rapidjson v1.1.0](https://github.com/Tencent/rapidjson/tree/v1.1.0) | [Full license](apps/macos/Vendor/rapidjson-1.1.0-LICENSE), [provenance and checksum](apps/macos/Vendor/rapidjson-1.1.0-SOURCE.txt) |

`apps/macos/Vendor/rime-jaroomaji/UPSTREAM.txt` and `SHA256SUMS.txt` record source provenance and
checksums. The large dictionary is included for build reproducibility; it is not a
user dictionary or model weight file. SaySpan-specific Rime schemas live separately
under `apps/macos/Resources/Rime/`.

## Libraries built for portable packages

The complete versions, source URLs, hashes, and build options are in
[apps/macos/Packaging/Dependencies.json](apps/macos/Packaging/Dependencies.json).

| Dependency | Main license |
| --- | --- |
| librime | BSD 3-Clause |
| gflags | BSD 3-Clause |
| glog | BSD 3-Clause |
| yaml-cpp | MIT |
| Snappy | BSD 3-Clause; additional notices remain in upstream COPYING files |
| LevelDB | BSD 3-Clause |
| MARISA trie | BSD 2-Clause or LGPL 2.1; upstream COPYING.md preserves both options |
| OpenCC | Apache 2.0; bundled third-party headers retain their own notices |
| Boost headers | Boost Software License 1.0 |

`apps/macos/Tools/BuildDependencies.py` copies each source archive's license, copying, notice,
author, and copyright files into the private dependency prefix. `apps/macos/Tools/BundleLibraries.py`
includes them under `Contents/Resources/ThirdParty/Libraries/`, including nested notices
and the otherwise omitted RapidJSON license. OpenCC data and the Rime dictionaries
are accompanied by their upstream notices in the app resources.

A quick Homebrew-linked development build is not a portable redistributable bundle;
use the packaging pipeline to collect the linked libraries and their notices.

## External services and models

Ollama, hosted translation services, and their model weights are not included.
Their terms and licenses are separate from SaySpan's license.
