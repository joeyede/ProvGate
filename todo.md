# ProvGate — Fix List

## Bugs

- [x] **`sendingAction` never cleared on publish timeout** — the 30-second `pendingCommands` cleanup task now sets `sendingAction = nil` after removing the correlation entry.
- [x] **`disconnect()` doesn't clear `sendingAction`** — `sendingAction = nil` added to `disconnect()`.
- [x] **`pendingCommands` not drained on `teardown()`** — `pendingCommands.removeAll()` added to `teardown()`.
- [x] **Keychain items missing `kSecAttrAccessible`** — `kSecAttrAccessibleAfterFirstUnlock` applied to both `SecItemUpdate` attributes and `SecItemAdd` query in `CredentialsStore`.
- [x] **`loadingAction` clears on PUBACK, not on gate response** — renamed `loadingAction` → `sendingAction` and removed redundant clear in `didReceiveMessage`.
- [x] **`handleAppBecameActive()` can strand user if OS suspends reconnect Task** — guard extended to also handle `.reconnecting`.
- [x] **`teardown()` calls `disconnect()` on already-disconnected client** — stale-client guard added to `mqtt5DidDisconnect`.

## Medium

- [x] **Correlation ID encoding comment and end-to-end test** — explanatory comment added to `encodeCorrelationId()`; `productionDecodePathRoundTrip` test exercises the actual decode path.
- [x] **`isOutsideView` toggle resets on app restart** — persisted in `UserDefaults` via `didSet`.
- [x] **Login form missing `.onSubmit` / keyboard "Go" action** — `.submitLabel(.go)`, `.onSubmit { handleConnect() }`, and `@FocusState` navigation added.
- [x] **No haptic feedback on gate button press** — `.sensoryFeedback(.impact(weight: .medium), trigger: isLoading)` added to `GateButton`.
- [x] **Reconnect screen has no attempt counter or cancel path** — attempt/max counter and Cancel button shown during `.reconnecting`.
- [x] **`maximumPacketSize = 1024` too small** — limit removed from `connectProperties`.
- [x] **No keyboard avoidance in `LoginView`** — form `VStack` wrapped in `ScrollView`.
- [x] **`sessionExpiryInterval = 300` wasted with new `clientID` per connect** — set to `0`.

## Minor / Style

- [x] **No accessibility labels on `GateButton`** — `.accessibilityLabel(label)` and `.accessibilityHint` added.
- [x] **Keychain errors silently swallowed** — `assert` on `SecItemAdd`/`SecItemUpdate` failures.
- [x] **`statusMessage` capitalisation is fragile** — capitalised at source in `MQTTManager` using `.capitalized`.
- [x] **`GateButton` takes `mqtt` as an explicit parameter** — switched to `@Environment(MQTTManager.self)`.
- [x] **`save(username:password:rememberMe: false)` silently deletes credentials** — dead `rememberMe: false` branch removed; `assert(rememberMe, ...)` added.
- [x] **"Restoring your session" caption shown during `.reconnecting`** — caption only shown for `.connecting`; `.reconnecting` shows attempt counter instead.
- [x] **`loadSavedCredentials()` is a needless pass-through** — removed; `LoginView` reads `CredentialsStore` directly.

## Tests

- [x] **`CredentialsStoreTests` writes to the production Keychain service** — test-scoped service name `ProvGate.MQTT.test` injected via `init(service:)`.
- [x] **`scheduleReconnect()` backoff and state transitions** — tests for no-credentials guard, first-call reconnecting/attempt increment, and max-attempts exhaustion.
- [x] **`handleAppBecameActive()` reconnect flow** — tests for `.disconnected`+credentials → `.connecting`, and `.connecting` state no-op.
- [x] **`sendCommand()` guard when disconnected** — covered by `sendCommandWhenNotConnectedDoesNotSetSendingAction`.
- [x] **`notify()` deduplication** — test verifies second notification replaces first before expiry.

---

## Round 2 — Deep Dive Review

### Bugs

- [ ] **`reconnectTask` leaks when `scheduleReconnect()` is called multiple times** (`MQTTManager.swift:203`) — `reconnectTask = Task { ... }` replaces the previous task without calling `reconnectTask?.cancel()` first. The orphaned task wakes, finds `connectionState != .reconnecting`, and exits harmlessly, but wastes a Task per call. Fix: add `reconnectTask?.cancel()` before the assignment.
- [ ] **`GateCommandSender` missing `rememberMe` guard** (`GateCommandSender.swift:44`) — `perform()` only checks that `username`/`password` are non-nil; if the keychain has data but `rememberMe` is `false` (e.g. a half-cleared state), the Siri intent silently connects. Should mirror the production check: `guard creds.rememberMe, let username = ...`.
- [ ] **Siri intent resolves on PUBACK, not gate response** (`GateCommandSender.swift:56–60`) — `waitForAck` resolves when the broker ACKs the publish (QoS 1), not when the Raspberry Pi processes the command. Siri says "Gate opened" even if the Pi is offline. Subscribing to `gate/responses/` with a correlation ID (same pattern as `MQTTManager`) would give a truthful result.

### Design

- [ ] **`scheduleReconnect()` internal exposure is too broad** (`MQTTManager.swift:185`) — Made internal to enable tests, but now any caller can invoke it while connected and silently disconnect the user. Prefer keeping it `private` and testing through a narrower seam (e.g. a dedicated `@testable`-only hook type or triggering via the delegate path).
- [ ] **Duplicate `GateCommand` struct and `"gate/control"` literal** (`MQTTManager.swift:224`, `GateCommandSender.swift:209`) — Both files define an identical `private struct GateCommand: Encodable { let action: String }` and hardcode `"gate/control"`. Extract to a shared file (e.g. `GateProtocol.swift` or `Config.swift`) to prevent drift.
- [ ] **`save()` uses `assert` instead of `precondition`** (`CredentialsStore.swift:22`) — `assert` is stripped in release builds; a future errant call with `rememberMe: false` would silently save wrong data. Use `precondition` to enforce the invariant in all configurations.

### Minor / Style

- [ ] **No whitespace trimming before connect** (`LoginView.swift:99`) — `username` and `password` are passed verbatim; a trailing space produces an auth failure with no helpful error. Add `.trimmingCharacters(in: .whitespaces)` to both before calling `mqtt.connect(...)`.
- [ ] **Outside intents send mirrored action with no explanation** (`GateIntents.swift:44,55`) — `resolvedAction("right", isOutsideView: true)` returns `"left"`, which is correct but counterintuitive. Add a one-line comment explaining the perspective swap so future readers don't "fix" it.
- [ ] **Intent dialog strings are plain `String`, not `LocalizedStringResource`** (`GateIntents.swift:11,23,32,46,57`) — `"Gate opened"` etc. are hardcoded English. `ProvidesDialog` accepts `LocalizedStringResource`; switching is a trivial change that keeps the door open for l10n.
- [ ] **Eye-button tap target below Apple's 44 pt minimum** (`LoginView.swift:60–67`) — The show/hide password button has only 8 pt trailing padding; the tappable area is well under 44×44 pt. Add `.frame(width: 44, height: 44)` to the `Button`.

### Tests

- [ ] **`staleClientDisconnectDoesNotTriggerReconnect` triggers a real DNS lookup** (`ProvGateTests.swift:150`) — `CocoaMQTT5(clientID: "stale", host: "test.example.com", port: 8884)` resolves a live hostname. Use a reserved non-routable address like `"192.0.2.1"` (TEST-NET, RFC 5737) to keep the test fully offline.
- [ ] **`ScheduleReconnectTests` with credentials triggers live MQTT connection** — Saving production credentials before creating `MQTTManager()` causes `startup()` → `createClient()` → real TLS connect attempt. The test tears it down immediately, but it's an integration side-effect inside a unit suite that will fail without network access.
