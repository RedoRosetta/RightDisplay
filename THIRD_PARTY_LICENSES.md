# Third-party information / 第三方说明

RightDisplay's proprietary source is not licensed as open source here. Third-party components retain their own terms.

自有源码不因本仓库获得开源许可，第三方遵循各自条款。

The published [0.1](https://github.com/RedoRosetta/RightDisplay/releases/tag/RightDisplay0.1Beta) and [0.2](https://github.com/RedoRosetta/RightDisplay/releases/tag/RightDisplay0.2Beta) pages provide matching notices, helper rebuild materials and corresponding-source assets. These document LGPL zeroconf, MPL certifi and other dependencies independently of the application source.

0.1／0.2 发行页提供各自匹配的 notices、辅助组件重建材料和对应源码，涉及 LGPL zeroconf、MPL certifi 等，与自有源码独立。

For [0.4 Beta RC](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.4-beta-rc), matching notices, licenses, exact corresponding sources and replacement instructions are supplied inside `Right Display.app/Contents/Resources/ThirdParty`:

- `THIRD_PARTY_NOTICES.md`: audited runtime versions, including pyatv 0.16.1, CPython 3.12.14 and PyInstaller 6.22.2.
- `LICENSES/`: original license texts, including Python and the Apache-licensed cryptography runtime hook.
- `SOURCES/`: exact zeroconf 0.150.0 (LGPL-2.1-or-later) and certifi 2026.7.22 (MPL-2.0) corresponding source archives.
- `REPLACEMENT.md`: replacing the complete external pure-Python zeroconf package and locally re-signing the App. This is an externally replaceable library mechanism, not an offer to publish private helper source.
- `SBOMS/`: upstream cryptography component information; permissive options are selected for dual-licensed dependencies.

Native DNS-SD uses Apple's system library; no separate DNS-SD implementation is bundled. HomePodAudioHelper is a proprietary subprocess containing the audited runtime and dependencies. No mandatory GPL-only runtime dependency was identified. This is an engineering assessment, not legal advice.

0.4 Beta RC 的匹配许可证、notices、zeroconf／certifi 精确对应源码及替换说明随 App 提供。zeroconf 是完整外置纯 Python 包，已验证可替换并加载；允许为个人使用修改该库及为调试修改进行逆向工程，不要求公开独立自有源码。原生 DNS-SD 使用 macOS 系统库，不额外捆绑实现。旧发行附件仅对应各自版本。
