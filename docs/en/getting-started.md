# Getting Started

This guide builds and runs T-Local on macOS.

## 1. Clone

```bash
git clone https://github.com/Aiomx/T-Local.git
cd T-Local
```

## 2. Run Tests

```bash
swift test
```

## 3. Build the macOS App

```bash
xcodebuild \
  -workspace EnterpriseTelemetryLocationQA.xcworkspace \
  -scheme TelemetryScenarioStudio \
  -destination 'platform=macOS' \
  -derivedDataPath /Volumes/Build/DerivedData/T-local \
  build
```

Use another `-derivedDataPath` if you do not have a `/Volumes/Build` disk.

## 4. Launch Scenario Studio

```bash
open /Volumes/Build/DerivedData/T-local/Build/Products/Debug/TelemetryScenarioStudio.app
```

## 5. Open in Xcode

```bash
open EnterpriseTelemetryLocationQA.xcworkspace
```

The workspace contains:

- `TelemetryScenarioStudio`: macOS route and scenario editor.
- `TelemetryQAConsole`: iOS QA console.
- `TelemetryLocationKit`: shared SDK.

## Notes

- iOS installation requires your own signing team.
- Network Extension / VPN features require proper Apple Developer capabilities.
- Device location simulation only works with simulators or trusted Apple developer devices that your machine can access.
