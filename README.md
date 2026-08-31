# Right Display

Right Display 是一款用于查看并调整 Mac 实际输出的显示信号的实用工具。对于使用 Mac、LG OLED、Apple TV 和 HomePod 或其他组合的用户，可以方便地查看和调整相关显示与音频设置。
<p align="center">
  <img src="docs/assets/right-display-app-icon.png" width="160" alt="Right Display 应用图标">
</p>
目前经过实际测试，Right Display 已可以在 **Mac mini（M4）+ LG G6 + Apple TV 4K（Gen3）+ HomePod（Gen2）** 的组合中识别并调整 RGB、12 Bit、165 Hz 和 HDR 等显示状态，同时调节显示器亮度以及通过 eARC 连接的 HomePod 设备音量，并实现与 Mac 键盘音量快捷键的联动。

此外，Redmi G27 Pro U 显示器也已经完成测试，可以正确切换至 RGB 模式，解决与Mac连接的兼容性问题。
这是一个早期测试版本。测试显示模式切换前，请记录当前可用的显示设置。

## 下载

请从 [Right Display 0.1 Beta Release 页面](https://github.com/RedoRosetta/RightDisplay/releases/tag/RightDisplay0.1Beta)]下载 **Right-Display-0.1-Beta.zip**。

SHA-256：**da1270012eb18402b152af4d87a4e003de26c8e1c0ac9ccf90245c9b0b549792**

Release 页面同时提供 Apple TV helper 重建材料，以及 zeroconf 0.150.0 的精确对应源码。

## 主要功能

- 通告当前的物理输出分辨率、HiDPI 逻辑分辨率和显示链路信号状态。
- 通告当前 HDR/SDR、VRR、DSC启用状态，并读取 RGB、YCbCr 信号信息，并实现开关控制。
- 在 macOS 提供可写接口时控制显示器亮度。
- 通过控制可写的 Core Audio 输出，提供 Apple TV/HomePod 兼容音频功能。
- 读取、解析并导出显示器的 EDID 和显示诊断信息。
- 可启用Mac键盘原生音量快捷键，实现类原生的音量调节。

## 软件截图

<p align="center">
  <img src="docs/screenshots/quick-panel.png" width="420" alt="Right Display 状态栏快捷面板">
</p>

![Right Display 高级设置概览](docs/screenshots/advanced-overview.png)

![Right Display 连接与信号页面](docs/screenshots/connection-signal.png)

![Right Display EDID 页面](docs/screenshots/edid-details.png)

## 兼容性与系统要求

- macOS 14 或更高版本。
- 当前安装包面向 Apple 芯片 Mac。
- 部分诊断和控制功能仅适用于外接显示器。
- 功能可用性取决于 Mac、macOS 版本、显示器、扩展坞或转接器、线材和连接方式。
- 部分显示控制功能需要辅助功能权限。
- Apple TV/HomePod 发现与控制需要本地网络权限。

并非所有显示器都支持全部控制功能。当 macOS 无法提供可验证的数据时，Right Display 会显示不可用或推断结果。

## 已知限制

- 许多 RGB/YCbCr 和色深组合由 macOS、驱动与显示器协商，无法保证每个请求组合都能被采用或持续生效。
- DSC 状态来自显示模式和链路带宽推断，并非直接从显示器接收端读取。
- VRR、亮度、HDR、颜色格式、色深和音频行为会因硬件与连接链路而异。
- 当前 Beta 使用 ad-hoc 签名，没有 Apple Developer ID 签名，也未经过 Apple notarization。

## 安装

1. 下载并解压 **Right-Display-0.1-Beta.zip**。
2. 将 **Right Display.app** 移动到“应用程序”文件夹。
3. 打开应用。
4. 如果 macOS 阻止首次启动，请打开 **系统设置 → 隐私与安全性**，找到 Right Display 并选择 **仍要打开（Open Anyway）**。
5. 仅在需要相关功能时授予辅助功能或本地网络权限。

## 反馈与 Issues

请使用 [GitHub Issues](https://github.com/RedoRosetta/RightDisplay/issues)，并选择 Bug Report 模板。

请尽量提供 Mac 型号、macOS 版本、显示器型号、连接方式、分辨率、刷新率、HDR 状态、问题描述和重现步骤。如果条件允许，也可以提供 Right Display 诊断信息。

诊断报告和 EDID 可能包含设备名称、序列号、显示器标识符、网络信息或其他个人信息。公开上传前请先检查并删除不希望公开的内容。不要发布密码、Token、Apple ID、配对凭据或其他敏感信息。

## 第三方许可证

用户安装包内包含所需的第三方许可证和 NOTICE。Apple TV/HomePod helper 重建包及对应源码材料可从 [v0.1 Release 页面](https://github.com/RedoRosetta/RightDisplay/releases/tag/v0.1) 获取。

公开分发摘要见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。

## 源码公开范围

Right Display 自有的 Swift 显示控制核心源码和私有 Xcode 工程未在本仓库公开。

为满足独立 Apple TV/HomePod helper 第三方许可证要求所需的源码和重建材料，已作为 Release Asset 提供。
