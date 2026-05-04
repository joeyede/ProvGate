# ProvGate — Fix List

## Bugs

- [ ] **`sendingAction` never cleared on publish timeout** — the 30-second `pendingCommands` cleanup task (`MQTTManager.swift:93`) removes the correlation entry but never sets `sendingAction = nil`; if a QoS 1 ACK is lost the loading spinner hangs until the next disconnect.
- [ ] **`disconnect()` doesn't clear `sendingAction`** (`MQTTManager.swift:58`) — if a command is in-flight when the user logs out, the spinner leaks into `LoginView`.
- [ ] **`pendingCommands` not drained on `teardown()`** (`MQTTManager.swift:167`) — stale entries linger 30 s after disconnect; drain the map in `teardown()`.
- [ ] **Keychain items missing `kSecAttrAccessible`** (`CredentialsStore.swift:44`) — the default `kSecAttrAccessibleWhenUnlocked` prevents reading credentials while backgrounded; use `kSecAttrAccessibleAfterFirstUnlock` so auto-reconnect works on a freshly rebooted device.
- [x] **`loadingAction` clears on PUBACK, not on gate response** — rename `loadingAction` → `sendingAction` and remove the redundant `loadingAction = nil` in `didReceiveMessage` to make the intent explicit, or invert: clear only on response and remove the PUBACK clear.
- [x] **`handleAppBecameActive()` can strand user if OS suspends reconnect Task** — extend the guard from `connectionState == .disconnected` to also handle `.reconnecting`, cancelling and restarting the reconnect on foreground.
- [x] **`teardown()` calls `disconnect()` on already-disconnected client** — in `mqtt5DidDisconnect`, nil-check the incoming `mqtt5` parameter against `self.client` before calling `scheduleReconnect()` to avoid invoking disconnect on a client that already dropped.

## Medium

- [ ] **Correlation ID encoding is opaque and test documents surprising behaviour** (`MQTTManager.swift:120`, `ProvGateTests.swift:40`) — the encode function adds a 2-byte length prefix that CocoaMQTT strips on receive; the test documents this with a comment but the production decode path (`String(bytes: corrData, encoding: .utf8)`) is never directly tested end-to-end. Add a test that round-trips via the actual decode path, and add a comment in the encode function explaining why the prefix is required by CocoaMQTT.
- [ ] **`isOutsideView` toggle resets on app restart** (`GateControlView.swift:102`) — persist the value in `UserDefaults` so the user's preferred perspective is remembered.
- [ ] **Login form missing `.onSubmit` / keyboard "Go" action** (`LoginView.swift:46`) — add `.onSubmit { handleConnect() }` and `.submitLabel(.go)` to the password field so the user can submit without tapping the button.
- [ ] **No haptic feedback on gate button press** (`GateControlView.swift:165`) — add `.sensoryFeedback(.impact(weight: .medium), trigger:)` or `UIImpactFeedbackGenerator` for tactile confirmation before the network round-trip completes.
- [ ] **Reconnect screen has no attempt counter or cancel path** (`ContentView.swift:47`) — users are stuck watching "Reconnecting…" with no indication of progress or way to abort before the 5-attempt limit. Show attempt/max and add a "Cancel" button that calls `disconnect()`.
- [ ] **`maximumPacketSize = 1024` too small** — raise to 65535 or remove the limit; the 1 KB cap will silently drop any response larger than that, leaving the pending command unresolved.
- [ ] **No keyboard avoidance in `LoginView`** — wrap the form `VStack` in a `ScrollView` so the Connect button isn't hidden by the software keyboard on small devices.
- [ ] **`sessionExpiryInterval = 300` is wasted with a new `clientID` per connect** — either adopt a stable client ID (persisted in `UserDefaults`) to actually resume sessions, or set `sessionExpiryInterval = 0` to tell the broker to drop the session immediately.

## Minor / Style

- [ ] **No accessibility labels on `GateButton`** (`GateControlView.swift:164`) — VoiceOver reads the raw SF Symbol name; add `.accessibilityLabel("Pedestrian gate")` etc. to each button.
- [ ] **Keychain errors silently swallowed** (`CredentialsStore.swift:49`) — `SecItemAdd`/`SecItemUpdate` return values are discarded; at minimum assert or `assertionFailure` in `#if DEBUG`.
- [ ] **`statusMessage` capitalisation is fragile** (`GateControlView.swift:19`) — `prefix(1).uppercased() + dropFirst()` breaks on emoji/multi-scalar graphemes; capitalise at the source in `MQTTManager` assignments instead.
- [ ] **`GateButton` takes `mqtt` as an explicit parameter** (`GateControlView.swift:159`) — inconsistent with every other view that uses `@Environment`; switch to `@Environment(MQTTManager.self)`.
- [ ] **`save(username:password:rememberMe: false)` silently deletes credentials** (`CredentialsStore.swift:18`) — callers expecting "save without remembering" get a delete; the `rememberMe: false` branch inside `save` is dead code anyway (call site uses `clear()` directly). Remove the branch or document the behaviour.
- [ ] **"Restoring your session" caption shown during `.reconnecting`** — show the caption only for `.connecting` (already the case after the routing fix) or replace it with "Retrying connection…" for `.reconnecting` to distinguish first-connect from retry.
- [ ] **`loadSavedCredentials()` is a needless pass-through** — remove the wrapper method and have `LoginView` read from `CredentialsStore` directly, or expose the store as a plain property on `MQTTManager`.

## Tests

- [ ] **`CredentialsStoreTests` writes to the production Keychain service** (`ProvGateTests.swift:51`) — running the test suite on a device with saved credentials will delete them; inject a test-scoped service name (e.g. `ProvGate.MQTT.test`) via a constructor parameter.
- [ ] **`scheduleReconnect()` backoff and state transitions** — test that: (a) state goes `.reconnecting` on first drop, (b) delays double each attempt, (c) state goes `.disconnected` after max attempts, (d) rememberMe=false guard resets state to `.disconnected`.
- [ ] **`handleAppBecameActive()` reconnect flow** — test that calling it in `.disconnected` with saved credentials transitions to `.connecting`, and that calling it in any other state is a no-op.
- [ ] **`sendCommand()` guard when disconnected** — test that calling `sendCommand` when `connectionState != .connected` sets `statusMessage` to "Not connected" and does not publish.
- [ ] **`notify()` deduplication** — test that a second notification fired before the first expires replaces it (doesn't leave a stale message visible).
