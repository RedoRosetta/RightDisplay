# Right Display

Right Display 是一款用于查看并调整 Mac 实际输出的显示信号的实用工具。对于使用 Mac、LG 电视、Apple TV 和 HomePod 组合的用户，可以方便地查看和调整相关显示与音频设置。

目前经过实际测试，Right Display 已可以在 **Mac mini（M4）+ LG G6（55 英寸）+ Apple TV 4K（第 3 代）+ HomePod（新款）** 的组合中识别并调整 RGB、12 Bit、165 Hz 和 HDR 等显示状态，同时调节显示器亮度以及通过 eARC 连接的 HomePod 设备音量，并实现与 Mac 键盘音量快捷键的联动。

此外，Redmi G27 Pro U 显示器也已经完成测试，可以正确切换至 RGB 模式显示。

> **当前版本：Right Display 0.1 Beta（Build 1）**
>
> [下载 Right Display 0.1 Beta](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.1)

这是一个早期测试版本。测试显示模式切换前，请保存重要工作，并记录当前可用的显示设置。

## 下载

请从 [v0.1 Release 页面](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.1) 下载 **Right-Display-0.1-Beta.zip**。

SHA-256：**da1270012eb18402b152af4d87a4e003de26c8e1c0ac9ccf90245c9b0b549792**

Release 页面同时提供 Apple TV helper 重建材料，以及 zeroconf 0.150.0 的精确对应源码。

## 主要功能

- 区分物理输出分辨率、HiDPI 逻辑分辨率和渲染缓冲尺寸。
- 显示当前刷新率，以及 macOS 提供的 VRR 模式。
- 显示 HDR/SDR 和系统可读取的 RGB、YCbCr 信号信息。
- 显示系统可读取的色深信息。
- 根据显示模式和链路带宽推断是否可能使用 DSC；DSC 会明确标注为推断，并非显示器接收端直接报告。
- 读取、解析并导出 EDID 和显示诊断信息。
- 切换系统支持的分辨率与刷新率模式，并提供确认期限和自动恢复尝试。
- 在 macOS 提供可写接口时控制显示器亮度。
- 控制可写的 Core Audio 输出，并提供可选的 Apple TV/HomePod 兼容音频功能。

## 截图

随着测试继续进行，后续会补充界面截图。目前可以直接从 Release 页面下载 0.1 Beta。

## 兼容性与系统要求

- macOS 14 或更高版本。
- 当前安装包面向 Apple 芯片 Mac。
- 部分诊断和控制功能仅适用于外接显示器。
- 功能可用性取决于 Mac、macOS 版本、显示器、扩展坞或转接器、线材和连接方式。
- 部分显示控制功能需要辅助功能权限。
- Apple TV/HomePod 发现与控制需要本地网络权限。

并非所有显示器都支持全部控制功能。当 macOS 无法提供可验证的数据时，Right Display 会显示不可用或推断结果。

## 已知限制

- 许多 RGB/YCbCr 和色深组合由 macOS、驱动与显示器协商。Right Display 无法保证每个请求组合都能被采用或持续生效。
- DSC 状态来自显示模式和链路带宽推断，并非直接从显示器接收端读取。
- HDR 控制部分依赖可能随 macOS 版本变化的系统接口。
- VRR、亮度、HDR、颜色格式、色深和音频行为会因硬件与连接链路而异。
- Apple TV/HomePod 设备发现已经测试；现有 Apple TV 配对恢复、状态读取、音量读取和音量修改已经测试。首次配对以及所有 HomePod 组合尚未完整验证。
- 当前 Beta 使用 ad-hoc 签名，没有 Apple Developer ID 签名，也未经过 Apple notarization。

## 安装

1. 下载并解压 **Right-Display-0.1-Beta.zip**。
2. 将 **Right Display.app** 移动到“应用程序”文件夹。
3. 打开应用。
4. 如果 macOS 阻止首次启动，请打开 **系统设置 → 隐私与安全性**，找到 Right Display 并选择 **仍要打开（Open Anyway）**。
5. 仅在需要相关功能时授予辅助功能或本地网络权限。

不需要关闭 SIP。不要关闭 Gatekeeper，也不要使用 **spctl --master-disable**。

## 反馈与 Issues

请使用 [GitHub Issues](https://github.com/RedoRosetta/RightDisplay/issues)，并选择 Bug Report 模板。

请尽量提供 Mac 型号、macOS 版本、显示器型号、连接方式、分辨率、刷新率、HDR 状态、问题描述和重现步骤。如果条件允许，也可以提供经过检查的 Right Display 诊断信息。

诊断报告和 EDID 可能包含设备名称、序列号、显示器标识符、网络信息或其他个人信息。公开上传前请先检查并删除不希望公开的内容。不要发布密码、Token、Apple ID、配对凭据或其他敏感信息。

## 第三方许可证

用户安装包内包含所需的第三方许可证和 NOTICE。Apple TV/HomePod helper 重建包及对应源码材料可从 [v0.1 Release 页面](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.1) 获取。

公开分发摘要见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。

## 源码公开范围

Right Display 自有的 Swift 显示控制核心源码和私有 Xcode 工程未在本仓库公开。

为满足独立 Apple TV/HomePod helper 第三方许可证要求所需的源码和重建材料，已作为 Release Asset 提供。
