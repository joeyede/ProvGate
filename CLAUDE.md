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

There is also an **Android version** of ProvGate (Kotlin/Jetpack Compose) in a separate repo. On this machine it lives at `~/AndroidStudioProjects/ProvGate/` — the path may differ on other systems. It contains a useful Go tool at `tools/gate-emulator/` that emulates `gate-remote` against the dry-run topics (`gate/test/...`), subscribing to `gate/test/control`, sending MQTT5 ACKs back on the response topic, and publishing a heartbeat to `gate/test/status` every minute. Useful for manual end-to-end testing with dry-run mode enabled. See `tools/gate-emulator/emulator.conf.template` for required env vars (`MQTT_BROKER_URL`, `MQTT_USERNAME`, `MQTT_PASSWORD`).

## Build & Run

Open `ProvGate.xcodeproj` in Xcode and use ⌘R to build and run, or use the CLI:

```bash
# Build
xcodebuild -project ProvGate.xcodeproj -scheme ProvGate -destination 'platform=iOS Simulator,name=iPhone 17' build
```

For running tests, see [Testing](#testing) below.

Dependencies are managed via Swift Package Manager (SPM) and resolved automatically on build.

**Required before building:** copy `ProvGate/Config.swift.template` to `ProvGate/Config.swift` and fill in your HiveMQ Cloud host. `Config.swift` is git-ignored and must not be committed.

## Testing

Tests live in two targets:

- **`ProvGateTests`** — [Swift Testing](https://developer.apple.com/documentation/testing) (`@Test`/`@Suite`/`#expect`), split into:
  - **Unit tests** (`ProvGateTests.swift`) — pure logic and state-machine checks (action swap, correlation-ID encoding, keychain round-trips, reconnect backoff, dry-run flag). No network, no credentials.
  - **Integration tests** (`MQTTIntegrationTests.swift`) — exercise the full MQTT path against the **live HiveMQ broker** using dry-run topics (`gate/test/...`), so the physical gate is never touched. A `MQTTTestObserver` helper subscribes to what the system-under-test publishes and replies on the response topic to simulate `gate-remote`. These suites are gated with `.enabled(if: canRunIntegration())` and are **auto-skipped when no credentials are present**.
- **`ProvGateUITests`** — XCUITest UI flows.

### Run unit tests (no credentials needed)

```bash
bash scripts/run-tests.sh
```

Or directly with xcodebuild:

```bash
xcodebuild test -project ProvGate.xcodeproj -scheme ProvGate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ProvGateTests
```

Without credentials the integration suites skip themselves and only the unit tests run.

### Run a single suite

Swift Testing filters at the **suite** level (the XCTest `Target/Class/method` form does not apply):

```bash
xcodebuild test -project ProvGate.xcodeproj -scheme ProvGate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ProvGateTests/ActionSwapTests
```

### Run integration tests (live broker)

Integration tests read `PROVGATE_TEST_USERNAME` / `PROVGATE_TEST_PASSWORD` from the environment. **iOS Simulator test processes do not inherit the parent shell's environment**, and a scheme `<EnvironmentVariable>` with value `$(VAR)` is injected *literally* (the macro never expands) — which silently feeds garbage credentials to the broker. The only reliable channel is the simulator's launchd environment, which `scripts/run-tests.sh --with-env` sets up for you:

```bash
bash scripts/run-tests.sh --with-env
```

This sources `~/.provgate-test-env` (git-ignored, never committed) and pushes the credentials into the booted simulator via `xcrun simctl spawn booted launchctl setenv` before running the full `ProvGateTests` target. `~/.provgate-test-env` defines:

```bash
export PROVGATE_TEST_USERNAME="..."
export PROVGATE_TEST_PASSWORD="..."
```

### Code coverage

```bash
xcodebuild test -project ProvGate.xcodeproj -scheme ProvGate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES -resultBundlePath /tmp/provgate-cov.xcresult
xcrun xccov view --report --only-targets /tmp/provgate-cov.xcresult   # per-target summary
xed /tmp/provgate-cov.xcresult                                        # open in Xcode
```

App-target coverage is ~87% with all targets run; the MQTT/logic layer (`MQTTManager`, `GateCommandSender`, `CredentialsStore`, `GateHelpers`) is 82–100%. The only uncovered files are the Siri App-Intents glue (`GateIntents.swift`, `GateShortcuts.swift`).

## Architecture

`MQTTManager` is the single source of truth — an `@Observable @MainActor` class held as `@State` in `ProvGateApp`, injected via `.environment(mqtt)` and read with `@Environment(MQTTManager.self)` in every view. It takes injectable `CredentialsStore` and `UserDefaults` dependencies (via a `#if DEBUG` init) so tests can isolate the keychain and the dry-run flag.

**State machine** (`ConnectionState`): `initializing → connecting → connected | disconnected`; a dropped connection cycles through `reconnecting` before retrying. `ContentView` switches between `ConnectingView`, `LoginView`, and `GateControlView` based on this state.

**MQTT connection**: Connects to HiveMQ Cloud over WebSocket + TLS (port 8884). On app launch, `startup()` checks `CredentialsStore`; if `rememberMe` is set it immediately starts connecting. `handleAppBecameActive()` re-connects on foreground if credentials are saved but state is `.disconnected`.

**Gate commands**: `sendCommand(_:)` publishes JSON to `gate/control`. Left/right actions are swapped when `isOutsideView = true` (outside perspective). Each command gets a UUID correlation ID embedded in MQTT5 publish properties (`responseTopic` + `correlationData`). Responses arrive on `gate/responses/<clientID>` and are matched back via `pendingCommands`.

**Credentials**: `CredentialsStore` stores username/password in the iOS Keychain (`ProvGate.MQTT` service) and the `rememberMe` flag in `UserDefaults`.

## Key files

| File | Role |
|------|------|
| `MQTTManager.swift` | All MQTT logic, connection lifecycle, command dispatch, response handling |
| `GateCommandSender.swift` | Standalone one-shot MQTT sender used by App Intents (Siri/Shortcuts) — fresh connection per invocation, no shared state with the main app session |
| `GateHelpers.swift` | Shared pure helpers (`resolvedAction`, `encodeCorrelationId`, app-group constant) used by the app, widget, and tests |
| `CredentialsStore.swift` | Keychain read/write wrapper (injectable service / app-group for test isolation) |
| `ContentView.swift` | Root view, routes on `connectionState`, shows toast notifications |
| `GateControlView.swift` | Gate buttons + inside/outside perspective toggle |
| `LoginView.swift` | Credential entry form, pre-fills from saved credentials |
| `ProvGateTests/MQTTIntegrationTests.swift` | `MQTTTestObserver` helper + live-broker integration suites (credential-gated) |
| `scripts/run-tests.sh` | Test runner; `--with-env` injects broker creds into the simulator for integration tests |

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
