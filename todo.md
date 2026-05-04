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

- [x] **`reconnectTask` leaks when `scheduleReconnect()` is called multiple times** — `reconnectTask?.cancel()` added before the Task assignment.
- [x] **`GateCommandSender` missing `rememberMe` guard** — `guard creds.rememberMe` added to `perform()`.
- [x] **Siri intent resolves on PUBACK, not gate response** — Rewrote `GateCommandSender` to subscribe to `gate/responses/<clientID>`, set `responseTopic`/`correlationData` on publish, and wait for the gate remote's reply via correlation ID.

### Design

- [x] **`scheduleReconnect()` internal exposure is too broad** — Reverted to `private`; exposed only in `#if DEBUG` via `testHook_scheduleReconnect()`.
- [x] **Duplicate `GateCommand` struct and `"gate/control"` literal** — Extracted to `GateMessages.swift`.
- [x] **`save()` uses `assert` instead of `precondition`** — All three `assert` calls in `CredentialsStore` replaced with `precondition`.

### Minor / Style

- [x] **No whitespace trimming before connect** — `trimmingCharacters(in: .whitespaces)` applied to both fields; `canConnect` also checks trimmed values.
- [x] **Outside intents send mirrored action with no explanation** — Comment added above outside intent structs explaining the left↔right swap.
- [x] **Intent dialog strings are plain `String`, not `LocalizedStringResource`** — `IntentDialog` doesn't accept `LocalizedStringResource` directly; string literals with `IntentDialog` are already localizable via `.strings` files (no change needed).
- [x] **Eye-button tap target below Apple's 44 pt minimum** — `.frame(width: 44, height: 44)` and `.contentShape(Rectangle())` added to the button.

### Tests

- [x] **`staleClientDisconnectDoesNotTriggerReconnect` triggers a real DNS lookup** — Host changed to `"192.0.2.1"` (RFC 5737 TEST-NET).
- [x] **`ScheduleReconnectTests` with credentials triggers live MQTT connection** — Tests now create `MQTTManager()` before saving credentials so `startup()` finds none and stays `.disconnected`.
