# Helper replacement / LGPL替换 — engineering evidence

未链接的源码/脚本/数据路径均以仓库根目录为基准；命令也从仓库根目录执行。 Unlinked source paths and commands are relative to the repository root.

已验证技术替换路径；正式 LICENSE §7.3A 保留 LGPL 必要组合权利，原 LGPL 权利不受 RNSL 限制。实际打包可执行文件在网络/用户Library写入均禁止时，`--help`成功加载了修改后的外置zeroconf；不是只在独立Python里测试import。没有启动App、发现、配对或控制设备。

## 源码重建

按BUILDING使用显式CPython3.12.14和hash锁定wheels重建。纯Python包33份.py在_internal/zeroconf，既不隐藏进PYZ也无其编译扩展。原始源码tar、LGPL全文和原声明保留。允许按原许可修改库，不应以RNSL给库追加非商业条件。

## 用户替换路径

停止Helper；保留回退副本；在隔离副本替换完整且接口兼容的_internal/zeroconf目录（不是拷不兼容.so）；若在签名App内，修改资源可能使包签名失效，使用开发者自己的合法签名与系统正常批准流程。不要关闭Gatekeeper/SIP，不需要也不会提供官方私钥。源码App通过Process执行打包Helper，未发现对Helper源码/hash的固定校验，但受系统签名/加载规则约束；完整官方签名包替换后功能未验收。

本轮自动验证仅--help，不能据此保证AppleTV发现/配对/音量正确。实际设备验证留给用户。没有更换Helper首方许可，没有增加网络自检或产品行为开关。

## License boundary

LICENSE §7.3A expressly overrides conflicting RNSL conditions for the combination modification, reproduction, replacement/relinking and reverse-debugging rights required by LGPL2.1§6, without applying a noncommercial condition to those required rights. It does not generally authorize commercial operation/distribution/services for first-party Helper code. Original library commercial permissions remain intact. Future executable distributors must independently satisfy an applicable §6 delivery route and provide exact library/rebuild materials. This source-only upload supplies no executable and claims no lawyer review.
