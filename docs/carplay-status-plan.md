# CarPlay status-tile fix plan

Self-contained implementation plan. An implementer should be able to execute this
without prior context. Every change names the file, the anchor, and the intended
behavior. Line numbers are approximate — match on the quoted code, not the number.

## Background

The CarPlay status tile is the gray top-left panel in
`ProvGate/CarPlaySceneDelegate.swift`, drawn by `statusImage(...)` and fed from
`makeSections()`.

Key facts that motivate the fixes:

- `gate/status` (subscribed in `MQTTManager.swift`, `mqtt5.subscribe("\(topicPrefix)/status", ...)`)
  carries **only** a once-per-minute liveness heartbeat JSON `{"hb":"<RFC3339>"}`.
  There is **no** open/closed gate state anywhere in the system. Confirmed in
  `gate-project/gate-remote/mqtt/handler.go` (`HeartbeatMessage`, 1-minute ticker).
  → The tile currently renders that raw JSON blob as "Gate {...}".
- The actual command result ("Pedestrian: Success/Failed") is written only to
  `statusMessage`, which the CarPlay tile never reads. → CarPlay shows no outcome.
- `sendingAction` is cleared in `didPublishAck` — the broker's QoS1 PUBACK, which
  arrives in milliseconds, long before the gate acts. → "Sending…" never visibly shows.

Three concerns are conflated in one tile: **controller liveness**, **last command
result**, and **in-flight command**. Each fix below owns one.

---

## Fix 1 — Liveness ("Online/Offline"), stop dumping heartbeat JSON

**`MQTTManager.swift`**

1. Add an observable property near the other `private(set) var ...` declarations
   (by `gateStatus`):
   ```swift
   private(set) var gateOnline: Bool = false
   ```
   Keep the existing `gateStatus` property unchanged — the Debug sheet
   (`GateControlView.swift`, `Text("Gate: \(status)")`) still uses it.

2. Add a watchdog field with the other `@ObservationIgnored` vars:
   ```swift
   @ObservationIgnored private var heartbeatWatchdog: Task<Void, Never>?
   ```

3. In `mqtt5(_:didReceiveMessage:...)`, the `gate/status` branch
   (`if topic == "\(topicPrefix)/status" { gateStatus = payload; return }`):
   after `gateStatus = payload`, mark online and reset the watchdog:
   ```swift
   gateOnline = true
   heartbeatWatchdog?.cancel()
   heartbeatWatchdog = Task { @MainActor [weak self] in
       try? await Task.sleep(for: .seconds(150))   // 2.5x the 60s heartbeat
       self?.gateOnline = false
   }
   ```

4. Set `gateOnline = false` and `heartbeatWatchdog?.cancel()` on every
   connection-drop path: `teardown()`, `disconnect()`, and `mqtt5DidDisconnect`.

Because the tile will observe `gateOnline` (a bool that rarely flips) instead of
`gateStatus` (which changes every heartbeat), this also removes the wasteful
full-strip redraw every 60 seconds.

---

## Fix 2 — Surface the command result in the tile

**`MQTTManager.swift`**

1. Add a small result type and property (near `gateStatus`):
   ```swift
   struct CommandResult { let action: String; let success: Bool }
   private(set) var lastCommandResult: CommandResult? = nil
   ```

2. In `sendCommand(_:)`, where `sendingAction = action` is set, clear any stale
   result so a fresh press doesn't show the previous outcome:
   ```swift
   lastCommandResult = nil
   ```

3. In the `gate/responses` handler, where `success` and `action` are already
   computed (`if let action { statusMessage = "\(action.capitalized): ..." }`),
   also record the structured result:
   ```swift
   if let action {
       statusMessage = "\(action.capitalized): \(success ? "Success" : "Failed")"
       lastCommandResult = CommandResult(action: action, success: success)
   }
   ```

---

## Fix 3 — "Sending…" stays up long enough to see, even on a fast reply

Move the clear off the broker PUBACK onto the real gate response, **and** guarantee
a minimum visible duration so a fast reply doesn't flash the indicator.

**`MQTTManager.swift`**

1. Add a constant and a timestamp field:
   ```swift
   private static let minSendingDisplaySeconds = 0.7
   @ObservationIgnored private var sendingStartedAt: Date?
   ```

2. In `sendCommand(_:)`, where `sendingAction = action` is set, record the start:
   ```swift
   sendingStartedAt = Date()
   ```

3. `didPublishAck` currently clears `sendingAction` on the broker PUBACK. Make it a
   no-op:
   ```swift
   nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {}
   ```

4. Add a helper that clears `sendingAction` but never sooner than the minimum
   on-screen time:
   ```swift
   private func clearSending(for action: String) {
       guard sendingAction == action else { return }
       let elapsed = sendingStartedAt.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
       let remaining = max(0, Self.minSendingDisplaySeconds - elapsed)
       if remaining == 0 {
           sendingAction = nil
       } else {
           Task { @MainActor [weak self] in
               try? await Task.sleep(for: .seconds(remaining))
               guard let self, self.sendingAction == action else { return }
               self.sendingAction = nil
           }
       }
   }
   ```

5. In the `gate/responses` handler (same `if let action` block as Fix 2), clear via
   the helper instead of directly:
   ```swift
   clearSending(for: action)
   ```

   `lastCommandResult` is set immediately, but the tile shows `sendingAction` with
   higher priority — so it displays "Sending…" for at least 0.7s, then flips to the
   result. The existing 30s fallback in `sendCommand` and the disconnect clear remain
   the safety nets if the gate never replies (those may clear directly).

> Cross-surface note: this also affects the **phone** UI — its full-screen spinner
> (`GateControlView.swift`, `if mqtt.sendingAction != nil`) now stays up for the real
> in-flight window (min 0.7s, until the gate responds) instead of flashing. Intended
> improvement; call it out in the PR description.

---

## Wire-up — CarPlay tile rendering

**`ProvGate/CarPlaySceneDelegate.swift`**

1. In `makeSections()`, change the status element inputs:
   ```swift
   image: Self.statusImage(online: mqtt.gateOnline,
                           sendingAction: sendingAction,
                           lastResult: mqtt.lastCommandResult,
                           specs: specs),
   ```

2. Rewrite `statusImage(...)` signature and the heading/body selection:
   ```swift
   private static func statusImage(online: Bool, sendingAction: String?,
                                   lastResult: MQTTManager.CommandResult?,
                                   specs: [(title: String, symbol: String, action: String, prominent: Bool)]) -> UIImage {
   ```
   Branch order and styling (replace the current `if/else if/else` and the hardcoded
   `bodyAttrs` color with a per-branch `bodyColor`):
   - `sendingAction` set → heading `"Sending"`, body `<title>…`, color `.label`
   - else `lastResult` set → heading `lastResult.action.capitalized`,
     body `lastResult.success ? "Success" : "Failed"`,
     color `lastResult.success ? .systemGreen : .systemRed`
   - else → heading `"Gate"`, body `online ? "Online" : "Offline"`, color `.label`

3. In `observe()`, replace `_ = mqtt.gateStatus` with the tile's new dependencies:
   ```swift
   _ = mqtt.connectionState
   _ = mqtt.sendingAction
   _ = mqtt.gateOnline
   _ = mqtt.lastCommandResult
   _ = mqtt.isOutsideView
   ```

---

## Tests & verification

- **`ProvGateTests/ProvGateTests.swift`** (unit, no creds): cover that
  (a) processing a `gate/responses` success/fail sets `lastCommandResult` and
  eventually clears `sendingAction`; (b) `didPublishAck` no longer clears
  `sendingAction`; (c) `sendingAction` stays set for at least the minimum window
  on a fast reply. Reuse the DEBUG dependency-injected `init(store:defaults:)`.
- **`MQTTIntegrationTests.swift`**: the `MQTTTestObserver` already replies on the
  response topic — confirm `sendingAction → nil` still occurs now that it keys off
  the response rather than PUBACK.
- Build:
  `xcodebuild -project ProvGate.xcodeproj -scheme ProvGate -destination 'platform=iOS Simulator,name=iPhone 17' build`
  then `bash scripts/run-tests.sh`.
- Manual: run the Android repo's `tools/gate-emulator` against dry-run topics and
  watch the CarPlay simulator show Online + "Sending…" + Success/Failed.

---

## Decisions locked (no choices left for the implementer)

- Minimum "Sending…" display: **0.7s**. Liveness window: **150s**.
- Headings: **"Sending" / `<Action>` / "Gate"**. Result colors: **green/red**.
- `gateStatus` raw property is **kept** (Debug sheet); it just no longer drives the tile.
- Out of scope (separate follow-ups): the inert tile still visually reads as a
  button (#5); shortening the 30s no-response fallback.
