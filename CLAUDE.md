# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Source project

ProvGate is a native Swift/SwiftUI iOS replacement for the `gate-app` component in `/Users/joeyedelstein/proj/gate-project`. That repo contains the full IoT system:

```
ProvGate (this repo)  ──MQTT (WSS 8884)──►  HiveMQ Cloud  ──MQTT──►  gate-remote (RPi)  ──GPIO──►  physical remote
```

- **gate-remote** (`gate-project/gate-remote/`) — Go service on a Raspberry Pi W; maps MQTT commands to GPIO pins (GPIO17/24/27/22) that simulate button presses on the physical gate remote. Deployed as a systemd service.
- The gate-app in gate-project is the React Native/Expo version of the same app. ProvGate replicates its feature set natively.
- Commands (`pedestrian`, `full`, `left`, `right`) and topic names are identical between both clients — the `gate-remote` backend doesn't distinguish which client sent the command.

## Build & Run

Open `ProvGate.xcodeproj` in Xcode and use ⌘R to build and run, or use the CLI:

```bash
# Build
xcodebuild -project ProvGate.xcodeproj -scheme ProvGate -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -project ProvGate.xcodeproj -scheme ProvGate -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test
xcodebuild -project ProvGate.xcodeproj -scheme ProvGate -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ProvGateTests/ProvGateTests/<TestName>
```

Dependencies are managed via Swift Package Manager (SPM) and resolved automatically on build.

## Architecture

`MQTTManager` is the single source of truth — a `@StateObject` created in `ProvGateApp` and injected as an `@EnvironmentObject` into every view.

**State machine** (`ConnectionState`): `initializing → connecting → connected | disconnected`. `ContentView` switches between `ConnectingView`, `LoginView`, and `GateControlView` based on this state.

**MQTT connection**: Connects to HiveMQ Cloud over WebSocket + TLS (port 8884). On app launch, `startup()` checks `CredentialsStore`; if `rememberMe` is set it immediately starts connecting. `handleAppBecameActive()` re-connects on foreground if credentials are saved but state is `.disconnected`.

**Gate commands**: `sendCommand(_:)` publishes JSON to `gate/control`. Left/right actions are swapped when `isInsideView = false` (outside perspective). Each command gets a UUID correlation ID embedded in MQTT5 publish properties (`responseTopic` + `correlationData`). Responses arrive on `gate/responses/<clientID>` and are matched back via `pendingCommands`.

**Credentials**: `CredentialsStore` stores username/password in the iOS Keychain (`ProvGate.MQTT` service) and the `rememberMe` flag in `UserDefaults`.

## Key files

| File | Role |
|------|------|
| `MQTTManager.swift` | All MQTT logic, connection lifecycle, command dispatch, response handling |
| `CredentialsStore.swift` | Keychain read/write wrapper |
| `ContentView.swift` | Root view, routes on `connectionState`, shows toast notifications |
| `GateControlView.swift` | Gate buttons + inside/outside perspective toggle |
| `LoginView.swift` | Credential entry form, pre-fills from saved credentials |

## Dependencies (SPM)

- **CocoaMQTT 2.2.4** — MQTT5 client (`CocoaMQTT5`, `CocoaMQTT5Delegate`)
- **MqttCocoaAsyncSocket 1.0.8** — socket layer used by CocoaMQTT
- **Starscream 4.0.8** — WebSocket transport used by CocoaMQTT

## MQTT topics

| Topic | Direction | Purpose |
|-------|-----------|---------|
| `gate/control` | publish | Gate command JSON `{"action":"<cmd>"}` |
| `gate/status` | subscribe | Gate status updates |
| `gate/responses/#` | subscribe | Command acknowledgements (matched via correlation ID) |
