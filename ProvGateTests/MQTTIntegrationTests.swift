import Foundation
import Testing
import CocoaMQTT
import CocoaMQTTWebSocket
@testable import ProvGate

// MARK: - Integration test infrastructure
//
// These tests exercise the full MQTT path against the real HiveMQ Cloud broker
// using dry run topics (gate/test/...). The physical gate is never touched because
// the gate-remote service only subscribes to gate/control, not gate/test/control.
//
// Each test that needs to assert wire-level behavior spins up a TestObserver
// alongside the system under test (SUT). The observer subscribes to gate/test/control
// so it can verify what the SUT publishes, and replies on gate/test/responses/<clientID>
// to simulate the gate-remote acknowledging the command.
//
// Concurrent connections per test: at most 2 (SUT + observer). Suites are
// .serialized so the broker never sees more than 2 concurrent connections from us.
//
// Prerequisite: run the app once and log in with valid credentials. The integration
// suites read the saved credentials from the shared app-group keychain. If no
// credentials are present, the suites are disabled (skipped, not failed).

// MARK: - Credential loading
//
// Credentials are looked up in this order:
//   1. Env vars PROVGATE_TEST_USERNAME / PROVGATE_TEST_PASSWORD
//      (set these in the test scheme's "Run > Arguments > Environment Variables")
//   2. The shared app-group keychain (set by running the app once and logging in)
//
// If neither yields valid credentials, all integration suites are disabled (skipped).

private struct IntegrationConfig {
    let username: String
    let password: String
}

private func loadIntegrationConfig() -> IntegrationConfig? {
    let env = ProcessInfo.processInfo.environment
    if let u = env["PROVGATE_TEST_USERNAME"], !u.isEmpty,
       let p = env["PROVGATE_TEST_PASSWORD"], !p.isEmpty {
        return IntegrationConfig(username: u, password: p)
    }
    let store = CredentialsStore(keychainAccessGroup: GateHelpers.appGroup,
                                 userDefaultsSuite: GateHelpers.appGroup)
    let creds = store.load()
    guard let u = creds.username, !u.isEmpty,
          let p = creds.password, !p.isEmpty else { return nil }
    return IntegrationConfig(username: u, password: p)
}

private func canRunIntegration() -> Bool {
    loadIntegrationConfig() != nil
}

// MARK: - TestObserver

/// Lightweight CocoaMQTT5 client used by integration tests to (a) observe what
/// the SUT publishes and (b) publish synthetic responses back to the SUT.
final class MQTTTestObserver: NSObject, @unchecked Sendable {

    struct Message {
        let topic: String
        let payload: String
        let correlationData: [UInt8]?
        let responseTopic: String?
    }

    private let mqtt: CocoaMQTT5
    private let lock = NSLock()
    private var buffer: [Message] = []
    private var connectCont: CheckedContinuation<Void, Error>?
    private var subscribeCont: CheckedContinuation<Void, Error>?
    private var pendingPredicate: ((Message) -> Bool)?
    private var pendingMessageCont: CheckedContinuation<Message, Error>?

    init(username: String, password: String) {
        let clientId = "test_obs_\(UUID().uuidString.prefix(8))"
        let socket = CocoaMQTTWebSocket(uri: "/mqtt")
        self.mqtt = CocoaMQTT5(clientID: clientId,
                               host: Config.brokerHost,
                               port: Config.brokerPort,
                               socket: socket)
        super.init()
        mqtt.username = username
        mqtt.password = password
        mqtt.enableSSL = true
        mqtt.autoReconnect = false
        mqtt.keepAlive = 30
        mqtt.delegate = self
    }

    func connect() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.lock()
            connectCont = cont
            lock.unlock()
            _ = mqtt.connect()
        }
    }

    func subscribe(_ topic: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.lock()
            subscribeCont = cont
            lock.unlock()
            mqtt.subscribe(topic, qos: .qos1)
        }
    }

    func publish(topic: String, payload: String, correlationData: [UInt8]? = nil) {
        let msg = CocoaMQTT5Message(topic: topic, string: payload, qos: .qos1)
        let props = MqttPublishProperties()
        if let cd = correlationData {
            // CocoaMQTT expects correlationData in bytesWithLength format on the way out
            // (delivers raw bytes on the way in — asymmetric). Re-add the 2-byte length prefix.
            let len = cd.count
            props.correlationData = [UInt8(len >> 8), UInt8(len & 0xFF)] + cd
        }
        mqtt.publish(msg, DUP: false, retained: false, properties: props)
    }

    /// Wait for a message matching `predicate`. Returns the first match (buffered or live).
    func waitForMessage(timeout: TimeInterval = 8,
                       where predicate: @escaping (Message) -> Bool) async throws -> Message {
        // Check buffered messages first.
        lock.lock()
        if let idx = buffer.firstIndex(where: predicate) {
            let m = buffer.remove(at: idx)
            lock.unlock()
            return m
        }
        lock.unlock()

        return try await withThrowingTaskGroup(of: Message.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Message, Error>) in
                    self.lock.lock()
                    self.pendingPredicate = predicate
                    self.pendingMessageCont = cont
                    self.lock.unlock()
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw ObserverError.timeout
            }
            for try await msg in group {
                group.cancelAll()
                return msg
            }
            throw ObserverError.timeout
        }
    }

    func disconnect() {
        mqtt.disconnect()
    }

    enum ObserverError: Error { case timeout, connectionFailed, subscribeFailed }
}

extension MQTTTestObserver: CocoaMQTT5Delegate {

    func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {
        lock.lock()
        let cont = connectCont; connectCont = nil
        lock.unlock()
        if ack == .success {
            cont?.resume(returning: ())
        } else {
            cont?.resume(throwing: ObserverError.connectionFailed)
        }
    }

    func mqtt5(_ mqtt5: CocoaMQTT5, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: MqttDecodeSubAck?) {
        lock.lock()
        let cont = subscribeCont; subscribeCont = nil
        lock.unlock()
        if failed.isEmpty {
            cont?.resume(returning: ())
        } else {
            cont?.resume(throwing: ObserverError.subscribeFailed)
        }
    }

    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?) {
        let msg = Message(
            topic: message.topic,
            payload: message.string ?? "",
            correlationData: publishData?.correlationData,
            responseTopic: publishData?.responseTopic
        )
        lock.lock()
        if let pred = pendingPredicate, pred(msg) {
            let cont = pendingMessageCont
            pendingPredicate = nil
            pendingMessageCont = nil
            lock.unlock()
            cont?.resume(returning: msg)
        } else {
            buffer.append(msg)
            lock.unlock()
        }
    }

    func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: Error?) {
        let error: Error = err ?? ObserverError.connectionFailed
        lock.lock()
        let cc = connectCont;        connectCont = nil
        let sc = subscribeCont;      subscribeCont = nil
        let mc = pendingMessageCont; pendingMessageCont = nil; pendingPredicate = nil
        lock.unlock()
        cc?.resume(throwing: error)
        sc?.resume(throwing: error)
        mc?.resume(throwing: error)
    }

    // CocoaMQTT bug: omitting this method causes TLS handshake to never complete (-1200).
    func mqtt5UrlSession(_ mqtt: CocoaMQTT5, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16) {}
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {}
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?) {}
    func mqtt5(_ mqtt5: CocoaMQTT5, didUnsubscribeTopics topics: [String], unsubAckData: MqttDecodeUnsubAck?) {}
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode) {}
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode) {}
    func mqtt5DidPing(_ mqtt5: CocoaMQTT5) {}
    func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5) {}
}

// MARK: - GateCommandSender integration tests

@Suite(.serialized, .enabled(if: canRunIntegration()))
struct GateCommandSenderIntegrationTests {

    private func makeTestStore(seedingFrom config: IntegrationConfig) -> CredentialsStore {
        let store = CredentialsStore(service: "ProvGate.MQTT.integration.test")
        store.clear()
        store.save(username: config.username, password: config.password, rememberMe: true)
        return store
    }

    // Always dry-run in tests — gate-remote only subscribes to gate/control, never gate/test/control.
    private func makeDryRunDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "ProvGate.integration.test.dryRun")!
        d.set(true, forKey: "provgate.isDryRun")
        return d
    }

    @Test func sendFullPublishesCorrectControlPayloadAndResolvesOnResponse() async throws {
        let config = loadIntegrationConfig()!
        let store = makeTestStore(seedingFrom: config)
        let defaults = makeDryRunDefaults()
        defer { store.clear() }

        let observer = MQTTTestObserver(username: config.username, password: config.password)
        try await observer.connect()
        defer { observer.disconnect() }
        try await observer.subscribe("gate/test/control")

        // Run sender concurrently. The observer below will see the publish and reply.
        async let sendResult: Void = GateCommandSender.sendForTesting(
            action: "full", store: store, defaults: defaults
        )

        let msg = try await observer.waitForMessage(timeout: 10) { $0.topic == "gate/test/control" }

        let json = try JSONSerialization.jsonObject(with: Data(msg.payload.utf8)) as? [String: Any]
        #expect(json?["action"] as? String == "full")
        #expect(msg.correlationData != nil)
        let rt = try #require(msg.responseTopic)
        #expect(rt.hasPrefix("gate/test/responses/"))

        // Reply on the response topic with matching correlationData so send() resolves.
        observer.publish(topic: rt,
                         payload: #"{"status":"success"}"#,
                         correlationData: msg.correlationData)

        try await sendResult
    }

    @Test func sendPedestrianPublishesCorrectAction() async throws {
        let config = loadIntegrationConfig()!
        let store = makeTestStore(seedingFrom: config)
        let defaults = makeDryRunDefaults()
        defer { store.clear() }

        let observer = MQTTTestObserver(username: config.username, password: config.password)
        try await observer.connect()
        defer { observer.disconnect() }
        try await observer.subscribe("gate/test/control")

        async let sendResult: Void = GateCommandSender.sendForTesting(
            action: "pedestrian", store: store, defaults: defaults
        )

        let msg = try await observer.waitForMessage(timeout: 10) { $0.topic == "gate/test/control" }
        let json = try JSONSerialization.jsonObject(with: Data(msg.payload.utf8)) as? [String: Any]
        #expect(json?["action"] as? String == "pedestrian")

        let rt = try #require(msg.responseTopic)
        observer.publish(topic: rt,
                         payload: #"{"status":"success"}"#,
                         correlationData: msg.correlationData)
        try await sendResult
    }

    @Test func timeoutThrowsWhenNoResponseArrives() async throws {
        let config = loadIntegrationConfig()!
        let store = makeTestStore(seedingFrom: config)
        let defaults = makeDryRunDefaults()
        defer { store.clear() }

        let observer = MQTTTestObserver(username: config.username, password: config.password)
        try await observer.connect()
        defer { observer.disconnect() }
        // Don't subscribe to anything — observer is a silent presence.

        let start = Date()
        do {
            try await GateCommandSender.sendForTesting(action: "full", store: store, defaults: defaults)
            Issue.record("Expected .timeout but send succeeded")
        } catch GateCommandError.timeout {
            let elapsed = Date().timeIntervalSince(start)
            // waitForResponse has a 10s timeout; allow generous slack for connect+subscribe.
            #expect(elapsed >= 9 && elapsed <= 30)
        } catch {
            Issue.record("Expected .timeout but got: \(error)")
        }
    }

    @Test func noCredentialsThrowsImmediately() async throws {
        // Fresh isolated store, no credentials saved.
        let store = CredentialsStore(service: "ProvGate.MQTT.integration.empty")
        store.clear()
        let defaults = makeDryRunDefaults()

        let start = Date()
        do {
            try await GateCommandSender.sendForTesting(action: "full", store: store, defaults: defaults)
            Issue.record("Expected .noCredentials but send succeeded")
        } catch GateCommandError.noCredentials {
            let elapsed = Date().timeIntervalSince(start)
            // Should fail without touching the network.
            #expect(elapsed < 1.0)
        } catch {
            Issue.record("Expected .noCredentials but got: \(error)")
        }
    }
}

// MARK: - MQTTManager integration tests

@MainActor
@Suite(.serialized, .enabled(if: canRunIntegration()))
struct MQTTManagerIntegrationTests {

    private func makeTestStore(seedingFrom config: IntegrationConfig) -> CredentialsStore {
        let store = CredentialsStore(service: "ProvGate.MQTT.integration.manager.test")
        store.clear()
        store.save(username: config.username, password: config.password, rememberMe: true)
        return store
    }

    // Always dry-run in tests — gate-remote only subscribes to gate/control, never gate/test/control.
    private func makeDryRunDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "ProvGate.integration.test.manager.dryRun")!
        d.set(true, forKey: "provgate.isDryRun")
        return d
    }

    /// Poll `mqtt.connectionState` until it equals `target` or `timeout` elapses.
    private func waitForState(_ mqtt: MQTTManager,
                              equals target: MQTTManager.ConnectionState,
                              timeout: TimeInterval = 12) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if mqtt.connectionState == target { return }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test func startupConnectsWhenCredentialsArePresent() async throws {
        let config = loadIntegrationConfig()!
        let store = makeTestStore(seedingFrom: config)
        let defaults = makeDryRunDefaults()
        defer { store.clear() }

        let mqtt = MQTTManager(store: store, defaults: defaults)
        try await waitForState(mqtt, equals: .connected)
        #expect(mqtt.connectionState == .connected)
        #expect(mqtt.statusMessage.contains("Connected"))
        #expect(mqtt.statusMessage.contains("DRY RUN"))
        mqtt.disconnect()
    }

    @Test func gateStatusUpdatesWhenObserverPublishesToStatusTopic() async throws {
        let config = loadIntegrationConfig()!
        let store = makeTestStore(seedingFrom: config)
        let defaults = makeDryRunDefaults()
        defer { store.clear() }

        let mqtt = MQTTManager(store: store, defaults: defaults)
        try await waitForState(mqtt, equals: .connected)

        let observer = MQTTTestObserver(username: config.username, password: config.password)
        try await observer.connect()
        defer { observer.disconnect() }

        observer.publish(topic: "gate/test/status", payload: "open")

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if mqtt.gateStatus == "open" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(mqtt.gateStatus == "open")
        mqtt.disconnect()
    }

    @Test func sendCommandPublishesAndCorrelatesResponse() async throws {
        let config = loadIntegrationConfig()!
        let store = makeTestStore(seedingFrom: config)
        let defaults = makeDryRunDefaults()
        defer { store.clear() }

        let mqtt = MQTTManager(store: store, defaults: defaults)
        try await waitForState(mqtt, equals: .connected)

        let observer = MQTTTestObserver(username: config.username, password: config.password)
        try await observer.connect()
        defer { observer.disconnect() }
        try await observer.subscribe("gate/test/control")

        mqtt.sendCommand("full")
        #expect(mqtt.sendingAction == "full")

        let controlMsg = try await observer.waitForMessage(timeout: 5) {
            $0.topic == "gate/test/control"
        }
        let json = try JSONSerialization.jsonObject(with: Data(controlMsg.payload.utf8)) as? [String: Any]
        #expect(json?["action"] as? String == "full")

        let rt = try #require(controlMsg.responseTopic)
        #expect(rt.hasPrefix("gate/test/responses/"))

        // Reply with success and the same correlationData; manager should update statusMessage.
        observer.publish(topic: rt,
                         payload: #"{"status":"success"}"#,
                         correlationData: controlMsg.correlationData)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if mqtt.statusMessage.contains("Success") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(mqtt.statusMessage == "Full: Success")
        mqtt.disconnect()
    }

    @Test func sendCommandOutsidePerspectiveSwapsLeftToRightOnTheWire() async throws {
        let config = loadIntegrationConfig()!
        let store = makeTestStore(seedingFrom: config)
        let defaults = makeDryRunDefaults()
        defer { store.clear() }

        let mqtt = MQTTManager(store: store, defaults: defaults)
        mqtt.isOutsideView = true
        try await waitForState(mqtt, equals: .connected)

        let observer = MQTTTestObserver(username: config.username, password: config.password)
        try await observer.connect()
        defer { observer.disconnect() }
        try await observer.subscribe("gate/test/control")

        mqtt.sendCommand("left")
        let msg = try await observer.waitForMessage(timeout: 5) { $0.topic == "gate/test/control" }
        let json = try JSONSerialization.jsonObject(with: Data(msg.payload.utf8)) as? [String: Any]
        // Outside-view swap means "left" on the button → "right" on the wire.
        #expect(json?["action"] as? String == "right")
        mqtt.disconnect()
    }
}
