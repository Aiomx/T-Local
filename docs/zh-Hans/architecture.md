# 架构说明

T-Local 由共享 SDK 和平台应用组成。

## TelemetryLocationKit

共享 SDK 包含：

- `LocationProvider`：异步定位源抽象。
- `CoreLocationProvider`：生产环境 Core Location 定位源。
- `MockRouteLocationProvider`：QA 场景回放定位源。
- `TelemetryScenario`：场景模型。
- `RoutePoint`：带时间信息的路线点模型。
- `RouteInterpolator`：插值定位生成。
- `GPXExporter`：GPX 导出。
- `TelemetryEventPreview`：QA 只读 payload 预览。
- VPN 和网络诊断相关模型。

## Telemetry Scenario Studio

macOS 应用提供：

- 场景库和本地文件管理。
- 地图路线编辑。
- 路线时间轴预览。
- 开发设备发现。
- 设备健康诊断。
- GPX 和场景 JSON 导出。
- 遥测 Payload 预览。

## Telemetry QA Console

iOS 应用提供目标设备上的 QA 界面基础：

- 加载场景。
- 预览遥测字段。
- VPN 元数据和网络诊断基础能力。

## 数据流

```text
Scenario Studio -> .telemetryscenario.json -> QA Console / SDK
Scenario Studio -> .gpx -> Xcode / Simulator / 外部工具
TelemetryLocationKit -> 模拟事件 -> 内部 QA 遥测流水线
```

## 生产安全

生产 App 应默认使用 `CoreLocationProvider`。QA 或 Debug 构建可以选择 `MockRouteLocationProvider`，并且必须在遥测 payload 中保留 `is_simulated=true`、`scenario_id` 和 `source=qa_sdk`。
