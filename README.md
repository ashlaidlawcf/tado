# Tado

A native macOS menu bar client for tado° smart heating, built with SwiftUI and Liquid Glass.

Unofficial and not affiliated with tado GmbH.

## Features

- Sign in via tado's OAuth device code flow (your password never touches the app)
- See each room's current temperature, humidity, target and heating activity
- Adjust target temperature, turn rooms off, or resume the schedule
- Refreshes only when opened (at most every 2 minutes) to stay within tado's daily API limits

Supports tado V3/V3+ devices (`my.tado.com/api/v2`). tado X is not supported yet.

## Requirements

- macOS 26 or later
- Xcode 26+ / Swift 6.2+

## Build & run

```sh
./scripts/bundle.sh
open build/Tado.app
```

Or open `Package.swift` in Xcode.

To regenerate the app icon after editing `scripts/make-icon.swift`:

```sh
swift scripts/make-icon.swift Resources
```

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/Tado/Auth/` | Device code flow, token refresh/rotation, Keychain storage |
| `Sources/Tado/API/` | tado REST client and models |
| `Sources/Tado/AppModel.swift` | App state and actions |
| `Sources/Tado/Views/` | SwiftUI views |
| `scripts/` | App bundling and icon generation |
