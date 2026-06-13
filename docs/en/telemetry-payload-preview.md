# Telemetry Payload Preview

The telemetry preview shows what a QA event would look like before anything is sent to a telemetry backend.

## Included Fields

The preview includes:

- `is_simulated=true`
- `source=qa_sdk`
- `scenario_id`
- `scenario_name`
- route point index and elapsed route time
- latitude and longitude
- altitude
- horizontal and vertical accuracy
- speed
- course
- VPN node ID, name, and region
- public IP and expected IP country when available
- DNS leak status when available
- custom scenario tags

## Scenario Payload

The scenario payload is based on the selected scenario and the current timeline preview position. If the timeline is between points, the coordinate can be interpolated.

## Device State Payload

If a location was already applied to a device, Studio also shows a device-state payload using the last applied coordinate and route progress.

## Copy Actions

- **Copy Fields** copies a simple `key=value` field list.
- **Copy JSON** copies the scenario payload as pretty JSON.
- **Copy Device JSON** copies the last device-state payload as pretty JSON.

## Safety

The preview is read-only. It does not send data to production telemetry.
