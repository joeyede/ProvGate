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

    private let store = CredentialsStore()
    private var client: CocoaMQTT5?

    // NSLock guards the three mutable fields below, which are touched from both
    // the async task and CocoaMQTT delegate callbacks (different threads).
    private let lock = NSLock()
    private var connectCont: CheckedContinuation<Void, Error>?
    private var ackCont: CheckedContinuation<Void, Error>?
    private var pendingMsgId: Int?

    // MARK: - Entry point

    static func send(action: String) async throws {
        let sender = GateCommandSender()
        try await sender.perform(action: action)
    }

    // MARK: - Private flow

    private func perform(action: String) async throws {
        let creds = store.load()
        guard creds.rememberMe, let username = creds.username, let password = creds.password else {
            throw GateCommandError.noCredentials
        }

        // Register defer before connecting so disconnect runs even on timeout.
        defer { client?.disconnect() }

        try await withTimeout(seconds: 10) {
            try await self.connectToMQTT(username: username, password: password)
        }

        let msgId = publishCommand(action: action)
        guard msgId != 0 else { return }

        try await withTimeout(seconds: 5) {
            try await self.waitForAck(msgId: msgId)
        }
    }

    private func connectToMQTT(username: String, password: String) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    cont.resume(throwing: CancellationError())
                    return
                }
                connectCont = cont
                lock.unlock()
                buildAndConnect(username: username, password: password)
            }
        } onCancel: { [self] in
            lock.lock()
            let cont = connectCont
            connectCont = nil
            lock.unlock()
            cont?.resume(throwing: CancellationError())
        }
    }

    private func buildAndConnect(username: String, password: String) {
        let clientId = "gate_siri_\(UUID().uuidString.prefix(8))"
        let socket = CocoaMQTTWebSocket(uri: "/mqtt")
        let mqtt = CocoaMQTT5(clientID: clientId, host: Config.brokerHost, port: Config.brokerPort, socket: socket)
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

    private func publishCommand(action: String) -> Int {
        guard let mqtt = client,
              let payload = try? JSONEncoder().encode(GateCommand(action: action)),
              let str = String(data: payload, encoding: .utf8) else { return 0 }
        let msg = CocoaMQTT5Message(topic: "gate/control", string: str, qos: .qos1)
        let props = MqttPublishProperties()
        props.messageExpiryInterval = 60
        return mqtt.publish(msg, DUP: false, retained: false, properties: props)
    }

    private func waitForAck(msgId: Int) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    cont.resume(throwing: CancellationError())
                    return
                }
                pendingMsgId = msgId
                ackCont = cont
                lock.unlock()
            }
        } onCancel: { [self] in
            lock.lock()
            let cont = ackCont
            ackCont = nil
            pendingMsgId = nil
            lock.unlock()
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
        lock.lock()
        let cont = connectCont
        connectCont = nil
        lock.unlock()
        if ack == .success {
            cont?.resume(returning: ())
        } else {
            cont?.resume(throwing: GateCommandError.connectionFailed)
        }
    }

    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {
        lock.lock()
        guard Int(id) == pendingMsgId else { lock.unlock(); return }
        let cont = ackCont
        ackCont = nil
        pendingMsgId = nil
        lock.unlock()
        cont?.resume(returning: ())
    }

    nonisolated func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: Error?) {
        let error: Error = err ?? GateCommandError.connectionFailed
        lock.lock()
        let cc = connectCont; connectCont = nil
        let ac = ackCont;     ackCont = nil
        lock.unlock()
        cc?.resume(throwing: error)
        ac?.resume(throwing: error)
    }

    // Required for TLS — without this CocoaMQTT raises error -1200.
    nonisolated func mqtt5UrlSession(_ mqtt: CocoaMQTT5, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: MqttDecodeSubAck?) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didUnsubscribeTopics topics: [String], unsubAckData: MqttDecodeUnsubAck?) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode) {}
    nonisolated func mqtt5DidPing(_ mqtt5: CocoaMQTT5) {}
    nonisolated func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5) {}
}

// MARK: - Model

private struct GateCommand: Encodable {
    let action: String
}
