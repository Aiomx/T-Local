# Device Diagnostics

The Developer Devices page lists simulators and trusted Apple developer devices visible to the Mac.

## Device Discovery

T-Local checks:

- Xcode `devicectl`
- CoreDevice device list
- iOS simulators from `simctl`
- Optional `pymobiledevice3` runtime
- Optional `idevicesetlocation` fallback

## Health Check Report

The health panel reports:

- Xcode / `xcrun` availability
- CoreDevice / `devicectl` availability
- `simctl` availability
- Pairing and trust state
- Connection path
- Developer Mode visibility
- Developer Disk Image visibility
- `pymobiledevice3` availability
- CoreDevice tunnel and RSD port
- DVT location capability

Each item includes:

- Status: pass, warn, fail, or unknown
- Detail
- Recommendation
- Repair command when available
- Whether the issue blocks location simulation

## Copy Reports

Use:

- **Copy Markdown** for human-readable issue reports.
- **Copy JSON** for automation, logs, or internal support tools.

## Common Fixes

Refresh devices:

```bash
xcrun devicectl list devices --timeout 5
```

List simulators:

```bash
xcrun simctl list devices available
```

Set Xcode path when using a custom Xcode install:

```bash
sudo xcode-select -s /Volumes/Build/dowl/Xcode.app/Contents/Developer
```

Restore the optional Python runtime:

```bash
python3 -m venv .venv-pymobiledevice3
.venv-pymobiledevice3/bin/python -m pip install pymobiledevice3
```

## Boundaries

The health check is read-only. It does not install dependencies, mount developer images, or change device settings automatically.
