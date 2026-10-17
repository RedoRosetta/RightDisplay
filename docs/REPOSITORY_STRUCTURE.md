# Repository structure / 仓库结构

当前版本：RightDisplay1.0.1 · Build46。[下载](https://github.com/RedoRosetta/RightDisplay/releases/tag/v1.0.1)。当前为1.0.1产品更新；此前仓库整理不改变原v1.0.0发行物。

| 目录/文件 | 用途 |
|---|---|
| README.md / README.en.md | 当前中英文产品主页与下载入口 |
| LICENSE / LICENSE_SCOPE.md / NOTICE.md | 正式RNSL、适用范围和必要声明；不改变第三方授权 |
| RightDisplay/ / RightDisplay.xcodeproj/ | 当前Swift/C++应用、真实Bundle资源和Xcode引用，保留位置 |
| AudioVirtualDevice/ | Driver、Broker、Transport、Installer脚本及Apple原声明 |
| Helpers/ | 当前Python Helper、PyInstaller spec及相关测试 |
| Scripts/ / Tests/ | 当前构建、获取、打包与离线测试；保留大小写及路径，避免破坏工程 |
| Dependencies/ | 当前精确锁定依赖与wheel来源合同 |
| assets/icons/ | 公开文档图标；App自己的图标仍在Bundle资源目录 |
| docs/installation/ | [安装/卸载](installation/INSTALLATION.md)、[隐私](installation/PRIVACY.md) |
| docs/development/ | [构建](development/BUILDING.md)、[架构](development/ARCHITECTURE.md)、[签名](development/SIGNING.md)、截图说明 |
| docs/licensing/ | 第三方清单、品牌/权属、中文许可解释、LGPL替换说明 |
| docs/releases/ | 当前1.0.1及已发布1.0说明；旧版本专属说明归档 |
| compliance/ | 当前有效SBOM、许可来源/权利记录和当前Build46实际载荷证据 |
| third_party/ | 上游原许可、notice、原生来源资料，不删除重复但独立必需的声明 |
| release-assets/Right-Display-0.1-Beta-compliance/ | 名称虽旧，当前Helper脚本仍读取其中的对应源码和许可证，必须保留位置 |
| archive/ | [历史索引](../archive/README.md)：旧说明、截图和阶段报告，不重复存放完整历史源码 |
| .github/ | 当前反馈表单、CI和贡献入口 |

分类原则：产品/开发输入保留；通用文档按主题分组；有价值的历史资料标注HISTORICAL；确定重复模板/旧语言副本删除，Git历史仍保留。未知或实际仍引用的材料保留。逐文件分类清单作为本次维护的本地核对记录，不把内部审计材料新增到公开仓库。
