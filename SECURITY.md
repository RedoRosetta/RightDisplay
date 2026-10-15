# Security / 安全

不要在公开Issue提交密码、Token、Apple ID、配对凭据、私钥或不愿公开的设备/网络/个人信息。发布诊断或EDID前逐项检查。普通不含敏感信息的缺陷可使用[问题表单](https://github.com/RedoRosetta/RightDisplay/issues/new/choose)；敏感问题不要附到公开Issue，使用仓库提供的私密报告渠道（若可用）。

RightDisplay1.0/Build45为Ad-hoc签名、未公证；精确组件内容绑定不是发布者身份认证。Driver/Broker绑定、Installer检查和默认Apple/Team构建策略见[签名说明](docs/development/SIGNING.md)。Broker继续验证Apple系统音频producer，保留角色、console UID、协议、边界、生命周期与fail-silent检查；当前不以App签名认证consumer，其他同控制台用户进程可能尝试消耗或拒绝服务。没有因整理而改变此边界。

No passwords, tokens, pairing credentials, private keys or personal diagnostics in public Issues. Review attachments before sharing. The 1.0 Ad-hoc component pins protect exact content, not publisher identity. The Broker's console-user consumer policy is not cryptographic App authentication; same-user availability attacks remain possible. See [privacy](docs/installation/PRIVACY.md) and [signing](docs/development/SIGNING.md). No notarization, universal compatibility or complete hardware regression is claimed.

Copyright © 2026 RedoRosetta
