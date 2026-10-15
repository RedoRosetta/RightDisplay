# Third-party licenses / 第三方许可 — candidate

2026-10-15。针对本轮新建Helper及Build44候选；**不是Build41公开RC的SBOM，也不是最终法律合规PASS**。首方采用RNSL1.0；所有第三方材料保留原许可。

## 实际完成

- 45份wheel（含通用文件名别名）均与官方PyPI摘要相符；39份环境发行包+2份构建专用依赖锁定，未更换依赖版本。官方URL/摘要/原始文件名见Dependencies/wheel-inventory.json。
- 已从实际wheel提取顶层与vendored许可、NOTICE、SBOM，解决此前pip、altgraph、macholib、poetry-core、hooks等材料未提取问题。材料在third_party/wheel-materials/。这不代表每个嵌套许可证的法律审查已完成。
- CPython3.12.14官方tag LICENSE、Doc/license.rst已取得；输入runtime自带LICENSE.txt与官方文本逐字节一致。旧3.12.13文件只作为历史原件保留，不再作为3.12.14的唯一依据。
- 新Helper经过23项mock测试；zeroconf33份.py外置、无其.so、不在PYZ，文件与新安装来源一致；修改副本可被导入，未调用发现/配对/控制。
- 打包前移除Cython/poetry-core，避免把构建工具当runtime；实际34个Python发行组件由COLLECT/PYZ/PKG TOC和安装RECORD对应，详见compliance/helper-collected-distributions.json。

## 固定依赖与实际载荷

| 依赖 | 版本 | 本地原始许可元数据 | 本轮实际runtime | 材料 |
|---|---|---|---|---|
| aiohappyeyeballs | 2.7.1 | PSF-2.0 | observed | exact wheel text extracted |
| aiohttp | 3.14.3 | Apache-2.0 AND MIT | observed | exact wheel text extracted |
| aiosignal | 1.4.0 | Apache 2.0 | observed | exact wheel text extracted |
| altgraph | 0.17.5 | MIT | not observed in final runtime TOCs | exact wheel text extracted |
| annotated-types | 0.8.0 | MIT | observed | exact wheel text extracted |
| async-timeout | 5.0.1 | Apache 2 | observed | exact wheel text extracted |
| attrs | 26.1.0 | MIT | observed | exact wheel text extracted |
| certifi | 2026.7.22 | MPL-2.0 | observed | exact wheel text extracted |
| cffi | 2.1.1 | MIT-0 | observed | exact wheel text extracted |
| chacha20poly1305-reuseable | 0.13.2 | Apache-2.0 OR BSD-3-Clause | observed | exact wheel text extracted |
| charset-normalizer | 3.5.1 | MIT | observed | exact wheel text extracted |
| cryptography | 50.0.0 | Apache-2.0 OR BSD-3-Clause | observed | exact wheel text extracted |
| Cython | 3.3.0 | Apache-2.0 | not observed in final runtime TOCs | official exact-tag notice retrieved under third_party/upstream-native-notices |
| frozenlist | 1.8.0 | Apache-2.0 | observed | exact wheel text extracted |
| idna | 3.19 | BSD-3-Clause | observed | exact wheel text extracted |
| ifaddr | 0.2.0 | MIT | observed | exact wheel text extracted |
| macholib | 1.16.4 | MIT | not observed in final runtime TOCs | exact wheel text extracted |
| miniaudio | 1.71 | MIT | observed | exact wheel text extracted |
| multidict | 6.7.1 | Apache License 2.0 | observed | exact wheel text extracted |
| packaging | 26.3 | Apache-2.0 OR BSD-2-Clause | observed | exact wheel text extracted |
| poetry-core | 2.4.1 | MIT | not observed in final runtime TOCs | exact wheel text extracted |
| propcache | 0.5.2 | Apache-2.0 | observed | exact wheel text extracted |
| protobuf | 7.36.0 | 3-Clause BSD License | observed | exact wheel text extracted |
| pyatv | 0.16.1 | MIT | observed | exact wheel text extracted |
| pycparser | 3.0 | BSD-3-Clause | not observed in final runtime TOCs | exact wheel text extracted |
| pydantic | 2.13.4 | MIT | observed | exact wheel text extracted |
| pydantic_core | 2.46.4 | MIT | observed | exact wheel text extracted |
| pyinstaller | 6.22.2 | GPL-2.0-or-later + bootloader exception; runtime hooks Apache-2.0 | observed | exact wheel text extracted |
| pyinstaller-hooks-contrib | 2026.6 | GPL-2.0-or-later build hooks; Apache-2.0 runtime hooks | observed | exact wheel text extracted |
| requests | 2.34.2 | Apache-2.0 | observed | exact wheel text extracted |
| setuptools | 84.0.0 | MIT | observed | exact wheel text extracted |
| six | 1.17.0 | MIT | observed | exact wheel text extracted |
| srptools | 1.0.1 | BSD 3-Clause License | observed | exact wheel text extracted |
| tabulate | 0.10.0 | MIT | not observed in final runtime TOCs | exact wheel text extracted |
| tinytag | 2.3.0 | see exact license text; metadata not sufficient | observed | exact wheel text extracted |
| typing_extensions | 4.16.0 | PSF-2.0 | observed | exact wheel text extracted |
| typing-inspection | 0.4.4 | MIT | observed | exact wheel text extracted |
| urllib3 | 2.7.0 | MIT | observed | exact wheel text extracted |
| yarl | 1.24.5 | Apache-2.0 | observed | exact wheel text extracted |
| zeroconf | 0.150.0 | LGPL-2.1-or-later | observed | exact wheel text extracted |
| pip | 25.0.1 | MIT | not observed in final runtime TOCs | exact wheel text extracted |

## 本轮最终清理结果

- 新增`third_party/standalone-20260825/`：从官方digest核验完整档案提取八个实际静态库的原始全文许可，来源/精确版本/摘要见native-runtime-components.json。库不是凭版本相近推定：15个代码/数据段、UUID、2532个导出符号和dyld/依赖表均与现有库一致；原始整文件摘要不一致，未声称签名字节可复现。
- cryptography另含OpenSSL4.0.1，与CPython的3.5.8分别记录；已获其精确版本声明。原wheel的Rust图32个外部crate均按图内摘要取得源码并保留原声明，包含build/proc-macro工具，**不把整张图伪装成全部在arm64载荷中实际执行的库**。
- miniaudio1.71精确sdist原文与header声明已补齐：核心0.11.25、dr_wav0.14.5、dr_flac0.13.3、dr_mp3 0.7.3是源码声明版本；可选解码器是否实际编入仍不由版本宏单独证明。

## 重点边界与未完成项

**Apple Driver。** 保留AudioVirtualDevice/Driver/APPLE-LICENSE.txt（Apple Inc.2024 MIT风格）。能确认的是原文授权及首方工程实际使用；不能仅因目录附许可就断言全部增量权属已确认。Driver/VirtualVolume.c、Producer.h的上游/首方增量范围需权利人确认；不重新限制Apple原始部分。

**zeroconf/LGPL。** 外置纯Python组件及修改后导入已验证；对应源码和LGPL全文保留。正式LICENSE §7.3A明确必要组合修改、替换/重新链接、复制及逆向调试权，优先于冲突的RNSL限制；不改变库本身的商业权，不将整个Helper改为宽松许可。未来二进制分发仍须独立履行LGPL第6条交付义务。

**PyInstaller/hooks。** 实际pyinstaller载荷来源为loader bootstrap及rthooks；hooks-contrib只观察到rthooks/pyi_rth_cryptography_openssl.py，适用其原文runtime hooks的Apache规则；普通GPL构建hook本身未作为runtime列入。bootloader例外仅按原文覆盖的文件解释，不替其他库免责。工具源/修改的独立再分发仍有原许可义务。

**CPython原生runtime。** 此前缺少来源/原生声明的问题现已实质补齐：bzip2 1.0.8、libffi3.4.8、mpdecimal4.0.0、Expat2.8.3、OpenSSL3.5.8、SQLite3.53.1.0、XZ5.8.3、libuuid1.0.3的来源与SHA、许可全文来自官方20260825构建资料。仅加入实际静态链接库，ncurses/zlib/libedit等系统动态库单列，不引入Tk/Tcl/BDB。字节差异与内容对应的证据保留，不用这项工程对应代替最终法律审查。

**其他wheel嵌套依赖。** cryptography的实际OpenSSL版本查询与publisher SBOM对应，32份crate源码摘要/原始许可已补齐；保持原许可表达式，self_cell等双许可不会被改写为RNSL。publisher Rust图含构建工具，尚未独立复现Rust target闭包。setuptools vendored声明已提取；pydantic-core等原生wheel及aiohttp vendored内容的目标级完整嵌套闭包仍需最终审查，不能用顶层MIT/Apache元数据宣称全清。未改变核心库或其许可。

**MPL/certifi。** 对应源码及MPL文本保留，MPL文件不改RNSL；可执行分发需要真实可用的源码获取方式和通知。[MPL原文](https://www.mozilla.org/en-US/MPL/2.0/)。RNSL官方原包首方源码链接例外不减轻第三方义务。

宽松MIT/BSD/Apache/PSF部分可按其条件与独立首方限制并存，但原始商业权不消失。GPL/AGPL无适用例外、且触发组合整体义务的代码不得简单并入RNSL；当前组合边界尚未作最终法律结论。

## SBOM范围

helper-sbom.cdx.json来自实际COLLECT/PYZ/PKG而非锁文件猜测；candidate-product-sbom.cdx.json对应本轮明确定位的编译装配产物，记录关键artifact摘要。二者明确标记原生嵌套完整性未闭合，不是已发布发行包SBOM。source-scope.json是拟上传源码范围，不包含Build、venv、pkg、App、日志和私有证据。

English: exact wheel legal materials and CPython upstream notices are now present. Actual runtime collection, pure-Python zeroconf replacement import and compilation are verified. Source-only authorization is adopted with the explicit LGPL reservation; future binary payloads still require their own exact source/relink compliance. No third-party license was changed.


## Current source-only distribution decision

First-party material is RNSL 1.0. Original third-party terms prevail. LICENSE §7.3A expressly permits own-use combined-work modification, replacement/relinking and reverse debugging where LGPL2.1 §6 requires, overriding conflicting RNSL conditions without relicensing the whole Helper. LGPL library rights, including independent commercial rights, are unrestricted.

The source snapshot includes zeroconf corresponding source and original license. No Python runtime, Helper executable, App or installer binary is uploaded. Future combined binaries must supply the exact library source and complete rebuild/relink materials by an applicable §6 route; the current source audit does not certify future binary releases. External pure-Python zeroconf replacement and modified loading were tested offline; official signatures are not supplied. No lawyer review is claimed.
