# Scenario Studio Guide

Telemetry Scenario Studio is the macOS app for creating QA location scenarios.

## Scenario Library

Scenarios are saved as local `.telemetryscenario.json` files under:

```text
~/Library/Application Support/TelemetryScenarioStudio/Scenarios
```

The library supports:

- New scenario
- Duplicate
- Rename
- Delete
- Import and export
- Search
- Tags
- Recent scenarios
- Autosave

## Map Editing

The map editor supports:

- Click the map to insert a route point.
- Drag a point to update its coordinate.
- Right-click a point to delete it.
- Select points from the map, table, or timeline.
- Swap start and end points.
- Switch between manual straight-line mode and road planning mode.
- Plan a MapKit route and apply it to the scenario.

## Route Metrics

The map panel shows:

- Total distance
- Total duration
- Average speed
- Point count
- Total dwell time
- Current route mode

## Timeline Playback Preview

The timeline panel lets you:

- Scrub to a route time.
- Preview interpolated coordinates.
- Start, pause, resume, and stop route playback.
- Change speed.
- Enable or disable looping.

Route playback remains low-frequency by route point, while the timeline preview can interpolate between points.

## Export Formats

- GPX: for Xcode, Simulator, and external tooling.
- JSON: for Scenario Studio, QA Console, and SDK-driven tests.
