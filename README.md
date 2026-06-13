# T-Local

T-Local is a Swift-native QA toolkit for building, editing, replaying, and inspecting location telemetry scenarios across macOS and iOS.

The project focuses on legitimate developer and QA workflows:

- macOS scenario authoring with route editing, GPX export, JSON scenario files, device health diagnostics, and telemetry payload previews.
- iOS QA console foundations for scenario playback, VPN metadata, IP/DNS diagnostics, and previewing simulated telemetry events.
- A shared `TelemetryLocationKit` SDK that lets internal apps switch between real Core Location and controlled QA route playback.

> T-Local does not modify system GPS for third-party apps. Location simulation is intended for apps that integrate the SDK, Xcode/Simulator workflows, and trusted Apple developer devices available to your own development environment.

## Features

- Visual route and scenario editing on macOS.
- Draggable MapKit route points, point insertion, right-click deletion, endpoint swapping, road planning, straight-line mode, and route metrics.
- Local scenario library with import/export, search, tags, recent scenarios, and autosave.
- Route playback controls with timeline preview, speed, pause/resume, stop, and loop.
- GPX export and scenario JSON export.
- Developer device discovery for simulators and trusted Apple devices.
- Device health diagnostic report with Markdown and JSON copy actions.
- Telemetry payload preview with pretty JSON and field table copy actions.
- Shared route interpolation, mock location provider, network profile, VPN node model, and telemetry tagging types.

## Repository Layout

```text
Config/                         Entitlements for app targets
Generated/                      Info.plist files used by the Xcode project
Sources/TelemetryLocationKit/   Shared SDK and domain models
Sources/TelemetryScenarioStudio macOS Scenario Studio app
Sources/TelemetryQAConsole/     iOS QA Console app
Tests/TelemetryLocationKitTests SDK tests
docs/en/                        English guides
docs/zh-Hans/                   Simplified Chinese guides
```

## Requirements

- macOS 14 or later
- Xcode 26 or compatible Swift 6 toolchain
- Swift Package Manager
- Optional: Apple Developer Program account for iOS device deployment and VPN entitlements
- Optional: `pymobiledevice3` runtime for advanced trusted-device DVT location workflows

## Quick Start

```bash
git clone https://github.com/Aiomx/T-Local.git
cd T-Local

swift test
xcodebuild \
  -workspace EnterpriseTelemetryLocationQA.xcworkspace \
  -scheme TelemetryScenarioStudio \
  -destination 'platform=macOS' \
  -derivedDataPath /Volumes/Build/DerivedData/T-local \
  build
open /Volumes/Build/DerivedData/T-local/Build/Products/Debug/TelemetryScenarioStudio.app
```

If you do not want to use `/Volumes/Build`, remove the `-derivedDataPath` argument or replace it with another local path.

## Documentation

English:

- [Getting Started](docs/en/getting-started.md)
- [Scenario Studio Guide](docs/en/scenario-studio.md)
- [Device Diagnostics](docs/en/device-diagnostics.md)
- [Telemetry Payload Preview](docs/en/telemetry-payload-preview.md)
- [Architecture](docs/en/architecture.md)

简体中文:

- [快速开始](docs/zh-Hans/getting-started.md)
- [场景工作台指南](docs/zh-Hans/scenario-studio.md)
- [设备诊断](docs/zh-Hans/device-diagnostics.md)
- [遥测 Payload 预览](docs/zh-Hans/telemetry-payload-preview.md)
- [架构说明](docs/zh-Hans/architecture.md)

## SDK Integration Example

```swift
import TelemetryLocationKit

let scenario = ScenarioTemplates.deliveryRoute
let provider: LocationProvider = MockRouteLocationProvider(scenario: scenario)

for try await location in provider.locations() {
    let event = TelemetryEvent(
        scenarioID: scenario.id,
        source: "qa_sdk",
        isSimulated: true,
        location: location,
        tags: scenario.expectedTelemetryTags
    )
    // Send event into your QA telemetry pipeline.
}
```

Keep simulated events marked with `isSimulated=true`, `scenarioID`, and `source=qa_sdk` so QA data remains separable from production analytics.

## Safety Boundaries

- No system-wide GPS modification is provided.
- No third-party app location spoofing is provided.
- Scenario files store VPN metadata only; secrets should stay in Keychain or your internal credential system.
- Network and VPN behavior must be validated on devices you own or administer.

## License

MIT License. See [LICENSE](LICENSE).
