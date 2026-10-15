# Signing / 签名配置

## 已实现并验证

`AudioVirtualDevice/SigningIdentity.h`统一自身组件的Team策略，默认仍是官方公开标识45F25M3DS7。Xcode的`RD_COMPONENT_TEAM`、组件builder第三参数和Swift桥接使用同一值；不是运行时可变偏好。安装/卸载脚本在构建时烘焙经过10位大写字母/数字验证的值，不读取安装时用户环境。

```sh
# ABCDE12345仅为无证书的编译测试ID，请换成开发者自己的实际Team
sh AudioVirtualDevice/build_packages.sh "$PWD/Build/VirtualAudio" - ABCDE12345
python3 Scripts/build.py --compile-only --component-team ABCDE12345
python3 Scripts/test_signing.py
```

这条路径不需要官方Team的证书，也不需要任何私钥。ad-hoc和unsigned仅验证编译：它们仍无法满足`anchor apple generic`和Team证书条件，不是受支持的运行发行包。测试确认伪造同名/同identifier的ad-hoc Broker被拒绝。

实际签名构建需开发者自己的有效Apple签名身份：给组件builder传入该身份和其Team；主App Xcode使用相同`RD_COMPONENT_TEAM`与自己的`DEVELOPMENT_TEAM`/`CODE_SIGN_IDENTITY`。非ad-hoc组件会核对签名回读的Team是否与编译策略一致。此配置并不提供证书、账号、特殊entitlement或平台许可。

官方构建省略组件第三参数、保留RD_COMPONENT_TEAM默认值，继续可选择原官方签名身份；本轮用C/Swift语义测试和默认策略完整编译确认要求未变，没有调用官方私钥完成签名。

## 保留的边界

Apple系统producer的anchor和两个系统音频identifier、CoreAudio UID、single-owner、protocol/format/bounds、epoch/stale-context和fail-silent全部保留。没有path/name/CDHash替代身份，没有自动安装或扬声器fallback。

不同Team的App不会因参数化而自动信任旧官方组件；安装/卸载也不会跨Team接管原组件。先决条件和人工迁移需另行设计/授权，本轮未操作系统安装。

AudioServerPlugIn HAL Driver与Broker不是本轮新加的系统扩展；是否被目标macOS实际加载、XPC连接、Installer授权、Gatekeeper/公证和音频转发仍须在开发者机器人工验证。编译或codesign结构成功不能保证这些。Helper嵌套库/签名App资源修改后需用户自己的合法重签名，不得用关闭Gatekeeper/SIP规避。

English: official default trust policy is preserved. A developer can explicitly select its own team consistently across C, Swift and baked Installer scripts. Actual Apple certificates and platform acceptance remain external prerequisites; ad-hoc is compile-only and still rejected by authenticated runtime requirements.
