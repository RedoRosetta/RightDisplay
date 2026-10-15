# 架构 / Architecture

Swift/SwiftUI 状态栏 App 由 Models、Services、Views 与 PreferencePane 组成。DisplayStore/DisplayOutputController 读取和调整系统显示状态；EDIDStore 解释设备声明；ColorProfileStore/ICCProfile 读取描述文件模型。控制结果必须回读并保留未知状态。

证据边界：macOS/SLS 当前报告不等于接收端物理输出；EDID 声明不等于当前输出；DSC 推断不等于物理验证；ICC/VCGT 图表不等于屏幕实测或 GPU 当前 LUT。

```text
系统音频 → output-only Driver producer
         → Broker / shared PCM transport
         → App TransportClient / Playback / SRC / gain
         → 保存 CoreAudio UID 的真实输出
```

Driver/Broker 为 C，实时桥为 C++，Swift AudioBridgeEngine 串行管理 HAL 生命周期和非实时证据写入，VirtualVolumeController 管理用户意图。Apple TV helper 是独立 Python/PyInstaller 进程，通过 pyatv 控制兼容设备。

音频保护：output-only、Apple 系统 producer 验证、当前 console user、single-owner、protocol/format/bounds、epoch/stale-context、UID 唯一解析与 fail-silent。目标消失不回落 Mac 扬声器，不改变系统默认输出，不采集麦克风。软件 gain 不改变电视硬件音量，100% 只表示内部 unity。

候选保留首次故障快照与稀疏 journal。原目标撤销被证实、清理安全、同 UID 唯一返回且满足全部策略时只自动尝试一次；手动停止取消恢复。回调入口与 Context 分离，等待中的回调未退出不释放 Context，特殊退役入口上限 32，达到上限要求重启。overrun 不自动重试，根因 UNKNOWN。

实时回调不得分配、锁、文件 IO、日志、阻塞 IPC、枚举设备或操作 UI。Build44 实际恢复仍 UNVERIFIED；模拟 fixture 不替代真机验收。

## English

Swift controls system-reported display state; EDID describes capabilities and ICC describes profiles, neither measures physical output. C Driver/Broker feed a C++ output-only transport and a UID-selected physical output. Swift owns lifecycle and one-shot conditional target-return policy. Preserve producer authentication, single ownership, bounds, epochs, stale-context checks and fail-silent behavior. No microphone or speaker fallback. Recovery remains unverified on real hardware; overrun remains unresolved.
