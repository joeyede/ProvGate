import Foundation
import CocoaMQTT
import CocoaMQTTWebSocket

enum GateCommandError: LocalizedError {
    case noCredentials
    case connectionFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .noCredentials:     return "Open ProvGate and log in first."
        case .connectionFailed:  return "Couldn't connect to the gate."
        case .timeout:           return "The gate didn't respond in time."
        }
    }
}

/// Standalone MQTT sender used by App Intents (Siri / Shortcuts).
/// Creates a fresh connection per invocation — no shared state with the main app session.
final class GateCommandSender: NSObject, @unchecked Sendable {

    private let store: CredentialsStore
    private let defaults: UserDefaults?
    private var client: CocoaMQTT5?
    private var clientID = ""
    private var topicPrefix = "gate"

    override init() {
        self.store = CredentialsStore(keychainAccessGroup: GateHelpers.appGroup, userDefaultsSuite: GateHelpers.appGroup)
        self.defaults = UserDefaults(suiteName: GateHelpers.appGroup)
        super.init()
    }

    #if DEBUG
    init(store: CredentialsStore, defaults: UserDefaults?) {
        self.store = store
        self.defaults = defaults
        super.init()
    }
    #endif

    // All mutable state touched from both the async task and CocoaMQTT
    // delegate callbacks lives here. The inner class is @unchecked Sendable
    // so the compiler accepts cross-context access; the NSLock provides safety.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        // nonisolated(unsafe): accessed from multiple contexts; the lock above provides safety.
        nonisolated(unsafe) var connectCont: CheckedContinuation<Void, Error>?
        nonisolated(unsafe) var subscribeCont: CheckedContinuation<Void, Error>?
        nonisolated(unsafe) var responseCont: CheckedContinuation<Void, Error>?
        nonisolated(unsafe) var pendingCorrelationId: String?
    }
    private let state = State()

    // MARK: - Entry point

    static func send(action: String) async throws {
        let sender = GateCommandSender()
        try await sender.perform(action: action)
    }

    #if DEBUG
    /// Test entry point — lets integration tests inject an isolated credential store and dry-run flag.
    static func sendForTesting(action: String, store: CredentialsStore, defaults: UserDefaults?) async throws {
        let sender = GateCommandSender(store: store, defaults: defaults)
        try await sender.perform(action: action)
    }
    #endif

    // MARK: - Private flow

    private func perform(action: String) async throws {
        let creds = store.load()
        guard creds.rememberMe, let username = creds.username, let password = creds.password else {
            throw GateCommandError.noCredentials
        }
        topicPrefix = (defaults?.bool(forKey: "provgate.isDryRun") ?? false) ? "gate/test" : "gate"

        // Register defer before connecting so disconnect runs even on timeout.
        defer { client?.disconnect() }

        try await withTimeout(seconds: 10) {
            try await self.connectToMQTT(username: username, password: password)
        }

        // Wait for SUBACK before publishing so we don't miss the response.
        try await withTimeout(seconds: 5) {
            try await self.subscribeToResponses()
        }

        let correlationId = UUID().uuidString
        try publishCommand(action: action, correlationId: correlationId)

        // Wait for the gate remote to confirm it processed the command,
        // not just for the broker to ACK delivery. This gives an honest result.
        try await withTimeout(seconds: 10) {
            try await self.waitForResponse(correlationId: correlationId)
        }
    }

    private func connectToMQTT(username: String, password: String) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.state.lock.lock()
                if Task.isCancelled {
                    self.state.lock.unlock()
                    cont.resume(throwing: CancellationError())
                    return
                }
                self.state.connectCont = cont
                self.state.lock.unlock()
                self.buildAndConnect(username: username, password: password)
            }
        } onCancel: { [self] in
            state.lock.lock()
            let cont = state.connectCont
            state.connectCont = nil
            state.lock.unlock()
            cont?.resume(throwing: CancellationError())
        }
    }

    private func subscribeToResponses() async throws {
        guard let mqtt = client else { throw GateCommandError.connectionFailed }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.state.lock.lock()
                if Task.isCancelled {
                    self.state.lock.unlock()
                    cont.resume(throwing: CancellationError())
                    return
                }
                self.state.subscribeCont = cont
                self.state.lock.unlock()
                mqtt.subscribe("\(self.topicPrefix)/responses/\(self.clientID)", qos: .qos1)
            }
        } onCancel: { [self] in
            state.lock.lock()
            let cont = state.subscribeCont
            state.subscribeCont = nil
            state.lock.unlock()
            cont?.resume(throwing: CancellationError())
        }
    }

    private func buildAndConnect(username: String, password: String) {
        let id = "gate_siri_\(UUID().uuidString.prefix(8))"
        clientID = id
        let socket = CocoaMQTTWebSocket(uri: "/mqtt")
        let mqtt = CocoaMQTT5(clientID: id, host: Config.brokerHost, port: Config.brokerPort, socket: socket)
        mqtt.username = username
        mqtt.password = password
        mqtt.enableSSL = true
        mqtt.autoReconnect = false
        mqtt.keepAlive = 30
        mqtt.delegate = self
        let cp = MqttConnectProperties()
        cp.sessionExpiryInterval = 0
        mqtt.connectProperties = cp
        client = mqtt
        _ = mqtt.connect()
    }

    private func publishCommand(action: String, correlationId: String) throws {
        guard let mqtt = client,
              let payload = try? JSONEncoder().encode(GateCommand(action: action)),
              let str = String(data: payload, encoding: .utf8) else {
            throw GateCommandError.connectionFailed
        }
        let msg = CocoaMQTT5Message(topic: "\(topicPrefix)/control", string: str, qos: .qos1)
        let props = MqttPublishProperties()
        props.messageExpiryInterval = 60
        props.responseTopic = "\(topicPrefix)/responses/\(clientID)"
        props.correlationData = GateHelpers.encodeCorrelationId(correlationId)
        mqtt.publish(msg, DUP: false, retained: false, properties: props)
    }

    private func waitForResponse(correlationId: String) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.state.lock.lock()
                if Task.isCancelled {
                    self.state.lock.unlock()
                    cont.resume(throwing: CancellationError())
                    return
                }
                self.state.pendingCorrelationId = correlationId
                self.state.responseCont = cont
                self.state.lock.unlock()
            }
        } onCancel: { [self] in
            state.lock.lock()
            let cont = state.responseCont
            state.responseCont = nil
            state.pendingCorrelationId = nil
            state.lock.unlock()
            cont?.resume(throwing: CancellationError())
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: Double,
        _ body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw GateCommandError.timeout
            }
            // Yield the result of whichever task finishes first.
            for try await value in group {
                group.cancelAll()
                return value
            }
            throw GateCommandError.timeout
        }
    }
}

// MARK: - CocoaMQTT5Delegate

extension GateCommandSender: CocoaMQTT5Delegate {

    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {
        state.lock.lock()
        let cont = state.connectCont
        state.connectCont = nil
        state.lock.unlock()
        if ack == .success {
            cont?.resume(returning: ())
        } else {
            cont?.resume(throwing: GateCommandError.connectionFailed)
        }
    }

    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: MqttDecodeSubAck?) {
        state.lock.lock()
        let cont = state.subscribeCont
        state.subscribeCont = nil
        state.lock.unlock()
        if failed.isEmpty {
            cont?.resume(returning: ())
        } else {
            cont?.resume(throwing: GateCommandError.connectionFailed)
        }
    }

    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?) {
        // CocoaMQTT strips the 2-byte length prefix before delivering corrData.
        guard let corrData = publishData?.correlationData,
              let correlationId = String(bytes: corrData, encoding: .utf8) else { return }
        state.lock.lock()
        guard correlationId == state.pendingCorrelationId else { state.lock.unlock(); return }
        let cont = state.responseCont
        state.responseCont = nil
        state.pendingCorrelationId = nil
        state.lock.unlock()
        cont?.resume(returning: ())
    }

    nonisolated func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: Error?) {
        let error: Error = err ?? GateCommandError.connectionFailed
        state.lock.lock()
        let cc = state.connectCont;   state.connectCont = nil
        let sc = state.subscribeCont; state.subscribeCont = nil
        let rc = state.responseCont;  state.responseCont = nil
        state.lock.unlock()
        cc?.resume(throwing: error)
        sc?.resume(throwing: error)
        rc?.resume(throwing: error)
    }

    // Required for TLS — without this CocoaMQTT raises error -1200.
    nonisolated func mqtt5UrlSession(_ mqtt: CocoaMQTT5, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didUnsubscribeTopics topics: [String], unsubAckData: MqttDecodeUnsubAck?) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode) {}
    nonisolated func mqtt5DidPing(_ mqtt5: CocoaMQTT5) {}
    nonisolated func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5) {}
}
