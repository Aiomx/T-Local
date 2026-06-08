# Enterprise Telemetry Location QA

Swift-native starter implementation for an internal map telemetry QA tool.

## What Is Included

- `TelemetryLocationKit`: shared SDK with real/simulated location providers, route interpolation, scenario JSON, GPX export, telemetry event tagging, VPN node models, and network diagnostics.
- `TelemetryScenarioStudio`: macOS SwiftUI scenario editor for route templates, JSON import/export, and GPX export.
- `TelemetryQAConsole`: SwiftUI QA console for scenario playback, telemetry event inspection, and VPN/IP/DNS diagnostics.
- `Config/TelemetryQAConsole.entitlements`: Network Extension entitlement template for Personal VPN.

## Boundaries

This project does not modify system GPS and does not affect third-party apps. Simulated GPS is exposed through `TelemetryLocationKit` for apps that integrate the SDK. IP geolocation testing is handled through VPN nodes and network diagnostics.

## Build And Test

```bash
swift test
swift build
xcodegen generate
xcodebuild -scheme TelemetryScenarioStudio -destination 'platform=macOS' build
xcodebuild -project EnterpriseTelemetryLocationQA.xcodeproj -target TelemetryQAConsole -sdk iphoneos26.0 CODE_SIGNING_ALLOWED=NO build
open EnterpriseTelemetryLocationQA.xcworkspace
```

The Swift package builds on macOS with Xcode 26 / Swift 6.2. The generated Xcode project contains the `TelemetryQAConsole` iOS app target, `TelemetryScenarioStudio` macOS app target, platform-specific framework targets that expose the shared `TelemetryLocationKit` module, and a macOS unit-test target.

For iOS device installation, set your real Apple Developer Team on the project or `TelemetryQAConsole` target, then enable Network Extensions for the App ID. `Config/TelemetryQAConsole.entitlements` is already wired into the generated app target.

## Integrating The SDK In The Internal Map App

Use `CoreLocationProvider` for production behavior and `MockRouteLocationProvider` for QA scenarios.

```swift
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
    // Send event into the existing telemetry pipeline.
}
```

Every simulated event should keep `isSimulated=true`, `scenarioID`, and `source=qa_sdk` so QA data does not pollute production analytics.

## VPN Notes

`PersonalVPNService` wraps `NEVPNManager` for IKEv2/IPSec Personal VPN. A real deployment still needs:

- Apple Developer Program signing.
- Network Extension capability enabled for the App ID.
- Real keychain-backed password or certificate references.
- Internal or trusted endpoints for IP geolocation and DNS leak checks.

Packet Tunnel support is intentionally deferred to the next phase.
