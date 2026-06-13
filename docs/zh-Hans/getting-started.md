# 快速开始

本文说明如何在 macOS 上构建并运行 T-Local。

## 已测试平台

T-Local 当前已测试到：

- macOS 27
- iOS 27
- iPadOS 27

macOS Scenario Studio 是主要桌面端应用。iOS 和 iPadOS 覆盖范围适用于受信任 Apple 开发设备、模拟器，以及项目提供的 QA Console / SDK 工作流。

## 1. 克隆仓库

```bash
git clone https://github.com/Aiomx/T-Local.git
cd T-Local
```

## 2. 运行测试

```bash
swift test
```

## 3. 构建 macOS 应用

```bash
xcodebuild \
  -workspace EnterpriseTelemetryLocationQA.xcworkspace \
  -scheme TelemetryScenarioStudio \
  -destination 'platform=macOS' \
  -derivedDataPath /Volumes/Build/DerivedData/T-local \
  build
```

如果你没有 `/Volumes/Build` 磁盘，可以删除 `-derivedDataPath` 参数，或替换成其他本地路径。

## 4. 启动 Scenario Studio

```bash
open /Volumes/Build/DerivedData/T-local/Build/Products/Debug/TelemetryScenarioStudio.app
```

## 5. 使用 Xcode 打开

```bash
open EnterpriseTelemetryLocationQA.xcworkspace
```

Workspace 包含：

- `TelemetryScenarioStudio`：macOS 路线和场景编辑器。
- `TelemetryQAConsole`：iOS QA 控制台。
- `TelemetryLocationKit`：共享 SDK。

## 注意事项

- iOS 真机安装需要你自己的 Apple Developer 签名团队。
- Network Extension / VPN 能力需要正确配置 Apple Developer capability。
- 设备定位模拟只面向本机可访问的模拟器或受信任 Apple 开发设备。
