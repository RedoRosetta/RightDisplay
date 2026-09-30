# Privacy & diagnostics / 隐私与诊断

Reports are saved locally on request through the system save dialog, not automatically uploaded to GitHub. Device discovery/pairing/control communicates over the network when used.

报告由用户主动保存到本地，不自动上传 GitHub；使用设备发现／配对／控制时会进行网络通信。

## Contents / 内容

- App/system versions, Mac model, display names and non-serial vendor/product information.
- Display state/evidence, modes, capability/validation records and selected settings.
- Audio properties, connection and volume/readback availability.
- Recent operation events (up to five minutes / 180 events) and selected troubleshooting excerpts.

包含版本、Mac 型号、设备名称和不含序列号的厂商／产品信息；显示状态与依据、模式和验证记录；音频属性与连接／音量状态；最近五分钟、最多 180 条事件及筛选摘录。

## Redaction and review / 脱敏与检查

Structured display identifiers omit the serial portion; selected display-log identifiers are replaced. Selected audio excerpts use an allowlist and omit pairing secrets; IPv4 addresses in those excerpt errors are replaced. Names, all event/error text, IPv6 addresses and every other field are not guaranteed anonymous.

结构化显示标识不保留序列号部分，选取的显示日志标识会被替换；音频摘录按白名单选取，不导出配对秘密，并替换该摘录错误中的 IPv4 地址。但不保证名称、所有事件／错误、IPv6 地址及其余字段均匿名。

**Review every attachment before sharing.** User-defined device names and raw EDID can identify devices or people; raw EDID may contain serial numbers. Remove personal names, addresses, paths and secrets. Do not publish credentials, PINs, tokens or private keys.

**分享前逐项检查附件。** 自定义名称、原始 EDID 可能识别设备或个人；原始 EDID 可能带序列号。删除个人名称、地址、路径和秘密，不公开凭据、PIN、token 或私钥。
