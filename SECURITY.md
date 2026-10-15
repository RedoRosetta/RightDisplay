> Current: RightDisplay 1.0 / Build45, Ad-hoc signed, not notarized. See [1.0 release notes](releases/1.0.0.md) and [signature boundaries](SIGNING.md). Prior RC/build notes below retain their historical scope.

# Security

Please do not open a public Issue containing passwords, access tokens, Apple IDs, pairing credentials, private keys, serial numbers, or other sensitive information.

Before attaching a Right Display diagnostic report or EDID export, review it and remove any device identifiers, network details, paths, usernames, or personal information you do not want to publish.

For an ordinary software defect that does not contain sensitive information, use the public bug report template.


## Current Beta audio policy

The 0.4 Beta RC broker does not authenticate the App consumer's cryptographic identity. Other own-component Apple/Team-signature checks remain unchanged and may prevent forwarding with the ad-hoc package. Current console-user, role/protocol, format/bounds, lifecycle and fail-silent guards remain, as does authentication of Apple OS audio producer hosts. Another same-console-user process may try to impersonate a consumer or deny availability.

本 RC 的 broker 不验证 App 客户端的签名身份；其他自身组件之间的 Apple／Team 签名校验仍保留，可能阻止 ad-hoc 包启用转发。当前控制台用户、角色／协议、格式／边界、生命周期、安全停止和 Apple 系统音频进程验证继续保留。同一控制台用户的其他进程可能尝试冒充客户端或占用连接。


## Source candidate / 源码候选

Source Available, not OSI Open Source. First-party material is licensed under RNSL 1.0 (Noncommercial). Copyright © 2026 RedoRosetta is the public attribution, not a separate legal entity. This Build44-based source preparation differs from the Build41 public RC and is not fully hardware-accepted. No official signing credentials are supplied.

Own-component Team is build-time configurable, official default preserved. Actual certificates/HAL/XPC runtime remain unverified. A private reporting contact is not invented; confirm a working private channel before final publication. Preserve producer/UID/ownership/bounds/epoch/fail-silent checks; no device or installation action in CI.

Copyright © 2026 RedoRosetta
