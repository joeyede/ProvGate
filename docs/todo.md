# Future TODOs

## Gate liveness probe (CarPlay / status tile)

Currently `gateOnline` starts as `nil` ("Ready") on each new connection and only
flips to `true` when the first passive heartbeat arrives — up to 60 seconds.

**Proposed fix:** add a `ping` action to `gate-remote`.

### gate-remote changes (`gate-project/gate-remote/mqtt/handler.go`)

- Handle `{"action":"ping"}` in the `switch cmd.Action` block (line ~92).
- Instead of touching GPIO, immediately publish `{"status":"success","action":"ping"}`
  to the `responseTopic` with the matching `correlationData` — same ack path as real
  commands.

### iOS changes (`ProvGate/MQTTManager.swift`)

- After a successful `didConnectAck`, send a ping command via the existing
  `sendCommand` / response flow (or a lighter-weight dedicated method that doesn't
  set `sendingAction`).
- On receiving the ack, `gateOnline` flips to `true` immediately — no waiting for
  the 60s heartbeat.

### Notes

- A ping that gets no reply within ~5s means the controller is offline; leave
  `gateOnline` as `nil` ("Ready") rather than immediately setting `false` (the
  controller may just be mid-reconnect).
- The Android emulator (`tools/gate-emulator`) would also need updating to handle
  the `ping` action on dry-run topics.
- No physical gate action occurs for `ping` — safe to send on every connect.
