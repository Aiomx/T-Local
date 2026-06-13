# Architecture

T-Local is split into a shared SDK and platform apps.

## TelemetryLocationKit

The shared SDK contains:

- `LocationProvider`: async location provider abstraction.
- `CoreLocationProvider`: production Core Location provider.
- `MockRouteLocationProvider`: scenario playback provider for QA.
- `TelemetryScenario`: scenario model.
- `RoutePoint`: timed route point model.
- `RouteInterpolator`: interpolated location generation.
- `GPXExporter`: GPX export.
- `TelemetryEventPreview`: read-only QA payload preview.
- VPN and network diagnostics models.

## Telemetry Scenario Studio

The macOS app provides:

- Scenario library and local file management.
- Map-based route editing.
- Route timeline preview.
- Developer device discovery.
- Device health diagnostics.
- GPX and scenario JSON export.
- Telemetry payload preview.

## Telemetry QA Console

The iOS app provides a target-device QA surface for:

- Loading scenarios.
- Previewing telemetry fields.
- VPN metadata and network diagnostics foundations.

## Data Flow

```text
Scenario Studio -> .telemetryscenario.json -> QA Console / SDK
Scenario Studio -> .gpx -> Xcode / Simulator / external tools
TelemetryLocationKit -> simulated events -> internal QA telemetry pipeline
```

## Production Safety

Production apps should default to `CoreLocationProvider`. QA or debug builds can opt into `MockRouteLocationProvider` and must keep `is_simulated=true`, `scenario_id`, and `source=qa_sdk` in telemetry payloads.
