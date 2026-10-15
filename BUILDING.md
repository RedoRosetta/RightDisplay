# 构建 / Building

**已验证：Xcode 27.0 / macOS SDK27.0 / Apple silicon arm64，候选0.4 Build44编译与完整资源装配。** 不等于签名可安装版本、HAL加载、真实播放或恢复验收。App target为macOS14；Virtual Audio产品要求macOS27+；Swift语言模式5、C11、C++20。

## 明确输入

- 显式使用CPython **3.12.14 arm64**。`Scripts/acquire_runtime.py --output Build/inputs/python`可获取固定官方standalone档案，校验GitHub digest并拒绝覆盖/不安全路径；不查找作者缓存。已用此公开runtime在新目录完成Helper及App编译。wheels显式提供且已核对官方摘要，没有重新下载全部wheels；不声称自编整个CPython工具链。
- 固定45个wheel输入、39个环境发行包及2个构建专用依赖。Dependencies/wheel-inventory.json记录官方PyPI URL与摘要；Dependencies/helper-requirements.lock带hash。冻结库部分通用wheel文件名拆分过，字节与官方摘要一致，不需要更换版本。
- zeroconf和certifi对应源码档案已随候选保留。只恢复源码/固定依赖，不拿历史App、Helper或pkg补输入。

## 从仓库根目录构建

```sh
python3 Scripts/acquire_runtime.py --output Build/inputs/python
python3 Scripts/acquire_wheels.py
python3 Scripts/build_helper.py --python "$PWD/Build/inputs/python/bin/python3.12" --wheels "$PWD/Build/inputs/wheels"
sh AudioVirtualDevice/build_packages.sh "$PWD/Build/VirtualAudio" -
python3 Scripts/preflight.py
python3 Scripts/build.py --compile-only
```

Helper脚本要求新输出目录，创建全新venv、离线hash锁定安装、从精确源码构建纯Python zeroconf、23项离线测试后再打包；构建专用Cython/poetry-core在打包前移除。存在旧输出时应先保留证据并由开发者选择新checkout，不暗中复用。原Helper shell入口现在要求显式python/wheel目录，不再默认寻找父级旧工作区。

上面的 `-` 仅生成**本地ad-hoc编译验证组件**；主App关闭签名，仅验证源码与装配。没有降低任何运行时认证检查；现有固定Team自身组件验证仍不能由此满足。不得把这条命令结果发布为可用安装版。

Xcode嵌入阶段和build wrapper均要求preflight：缺Helper、runtime、zeroconf、精确CPython许可或两个组件pkg即非零失败，不再warning后制造不完整成功。preflight检查结构，Helper audit检查纯Python/替换结构；不把结构PASS当供应链、法律或运行时PASS。

## 本轮验证方式及边界

本轮显式导入冻结合同的独立CPython和45份摘要校验wheel（不导入旧venv/Helper/pkg），从零新建Helper。随后在无DerivedData的新源码副本中使用**本轮生成的**Helper/pkg装配编译，外层沙箱拒绝访问私有开发目录、旧聊天目录及原候选目录；这些拒读规则通过实际拒读检查。

macOS拒绝Swift宏的嵌套sandbox时，独立验证runner使用 `--inherit-outer-sandbox`。该选项仅让宏继承已有外层拒读规则；普通构建无需启用。外层规则、产品代码和认证校验不因此移除。首次失败日志保留。具体PASS/FAIL结果见compliance/engineering-result.json；未把“提供了全部本地输入”写成“另一台Mac从公开网络冷启动已通过”。

## 离线回归

```sh
python3 Scripts/offline_targeted.py
python3 Scripts/offline_recovery.py
```

顺序执行，9组诊断/控制器/transport/fake-HAL/恢复/在途回调/容量测试。只使用fake backends，不播放、不安装、不操作GUI/Link Test/显示模式/默认输出。历史UI/设备runner不在此安全入口内，先读Tests/README。

## 签名参数化及尚未闭合

默认官方Team和自选Team两套策略均通过C/Swift安全测试；实际自选Team贯通App、Driver、Broker及生成安装脚本，并完整编译。见 [SIGNING.md](SIGNING.md)。这不是实际第三方证书或HAL运行验收。

1. 自身Team已参数化，官方默认策略保留；实际第三方证书签名、安装/HAL/XPC和跨机发行仍待人工验收，不能用path/name/CDHash绕过。
2. CPython八个实际静态原生依赖来源、版本、全文许可及模块链接已补齐；内容段/UUID/dyld表/导出符号与官方档案一致，整文件摘要因元数据布局不同不相同。其他wheel的目标级嵌套闭包仍需最终审查，见THIRD_PARTY_LICENSES。
3. LGPL技术替换：实际打包可执行程序已在网络拒绝下加载修改外置zeroconf。组合的自行修改/逆向调试法律权利、签名官方包替换后的实际设备功能仍未确认；详见HELPER_REPLACEMENT。
4. RNSL、首方权属和品牌审查；Build44恢复UNVERIFIED、overrun根因UNKNOWN；公开RC ad-hoc问题仍未修复。

English: complete source compilation/assembly is validated with explicit inputs, not a signed or runtime-accepted release. Build the helper from fresh hash-pinned dependencies, compile local components, then compile-only the app. Missing inputs fail closed. Clean-path source compilation is distinguished from a cold public-network bootstrap. No install, GUI or audio action is part of this workflow.

新增安全回归：`python3 Scripts/test_signing.py`。普通source编译可用自己的10位Team配置，官方默认值不是必须拥有的身份；真实运行仍须自己的有效Apple签名。

## 授权状态更新 / Authorization status

用户已确认首方代码及构建脚本/必要文档公开范围；RNSL 1.0 已采用；编译通过不等于实机验收。源码含Team参数化配置，不包含官方私钥/证书凭据。混合上游、第三方和品牌范围见LICENSE_SCOPE与OWNERSHIP_SCOPE。

## Source-only Sponsor resources

Copyright © 2026 RedoRosetta. Both Sponsor PNG filenames are retained as neutral generated placeholders, containing no payment/QR/account data. Regenerate with `python3 Scripts/generate_sponsor_placeholders.py`. The Xcode folder reference and bundle resource lookup remain intact; source builds cannot use these images to pay. No original payment image is included.
