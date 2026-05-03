import Foundation
import Observation
import CocoaMQTT
import CocoaMQTTWebSocket

@Observable
@MainActor
final class MQTTManager: NSObject {

    enum ConnectionState { case initializing, connecting, reconnecting, connected, disconnected }

    private(set) var connectionState: ConnectionState = .initializing
    private(set) var statusMessage = "Disconnected"
    private(set) var connectionError: String? = nil
    var isOutsideView = false
    private(set) var sendingAction: String? = nil
    private(set) var notificationMessage: String? = nil
    private(set) var gateStatus: String? = nil


    @ObservationIgnored private var client: CocoaMQTT5?
    @ObservationIgnored private var pendingCommands: [String: String] = [:]
    @ObservationIgnored private let store = CredentialsStore()
    @ObservationIgnored private var connectionTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectAttempt = 0
    private static let maxReconnectAttempts = 5
    private static let connectionTimeoutSeconds = 10.0

    @ObservationIgnored private let controlTopic = "gate/control"

    override init() {
        super.init()
        startup()
    }

    // MARK: - Public interface

    func loadSavedCredentials() -> (username: String, password: String, rememberMe: Bool) {
        let c = store.load()
        return (c.username ?? "", c.password ?? "", c.rememberMe)
    }

    func connect(username: String, password: String, rememberMe: Bool) {
        cancelReconnect()
        teardown()
        connectionState = .connecting
        statusMessage = "Connecting..."
        connectionError = nil
        if rememberMe {
            store.save(username: username, password: password, rememberMe: true)
        } else {
            store.clear()
        }
        createClient(username: username, password: password)
    }

    func disconnect() {
        cancelReconnect()
        teardown()
        store.clear()
        connectionState = .disconnected
        statusMessage = "Disconnected"
        connectionError = nil
        notify("Logged out successfully")
    }

    func sendCommand(_ action: String) {
        guard let mqtt = client, connectionState == .connected else {
            statusMessage = "Not connected"
            notify("Not connected to MQTT")
            return
        }

        let actual = MQTTManager.resolvedAction(action, isOutsideView: isOutsideView)

        sendingAction = action

        let correlationId = UUID().uuidString
        pendingCommands[correlationId] = action

        guard let payload = try? JSONEncoder().encode(GateCommand(action: actual)),
              let payloadString = String(data: payload, encoding: .utf8) else { return }
        let msg = CocoaMQTT5Message(topic: controlTopic, string: payloadString, qos: .qos1)
        let props = MqttPublishProperties()
        props.messageExpiryInterval = 60
        props.responseTopic = "gate/responses/\(mqtt.clientID)"
        props.correlationData = MQTTManager.encodeCorrelationId(correlationId)

        mqtt.publish(msg, DUP: false, retained: false, properties: props)
        statusMessage = "Sent: \(action)"

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            self?.pendingCommands.removeValue(forKey: correlationId)
        }
    }

    // Called from ContentView when app becomes active
    func handleAppBecameActive() {
        guard connectionState == .disconnected || connectionState == .reconnecting else { return }
        let creds = store.load()
        guard creds.rememberMe, let u = creds.username, let p = creds.password else { return }
        cancelReconnect()
        teardown()
        connectionState = .connecting
        statusMessage = "Connecting..."
        createClient(username: u, password: p)
    }

    // MARK: - Internal helpers (exposed for testing)

    nonisolated static func resolvedAction(_ action: String, isOutsideView: Bool) -> String {
        if (action == "left" || action == "right") && isOutsideView {
            return action == "left" ? "right" : "left"
        }
        return action
    }

    nonisolated static func encodeCorrelationId(_ id: String) -> [UInt8] {
        let bytes = Array(id.utf8)
        return [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)] + bytes
    }

    // MARK: - Private

    private func startup() {
        let creds = store.load()
        if creds.rememberMe, let u = creds.username, let p = creds.password {
            connectionState = .connecting
            statusMessage = "Connecting..."
            createClient(username: u, password: p)
        } else {
            connectionState = .disconnected
            statusMessage = "Disconnected"
        }
    }

    private func createClient(username: String, password: String) {
        let clientId = "gate_app_\(UUID().uuidString.prefix(8))"
        let socket = CocoaMQTTWebSocket(uri: "/mqtt")
        let mqtt = CocoaMQTT5(clientID: clientId, host: Config.brokerHost, port: Config.brokerPort, socket: socket)
        mqtt.username = username
        mqtt.password = password
        mqtt.enableSSL = true
        mqtt.autoReconnect = false
        mqtt.keepAlive = 30
        mqtt.delegate = self

        let cp = MqttConnectProperties()
        cp.sessionExpiryInterval = 300
        cp.receiveMaximum = 100
        cp.maximumPacketSize = 1024
        mqtt.connectProperties = cp

        client = mqtt
        _ = mqtt.connect()

        connectionTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.connectionTimeoutSeconds))
            guard let self, connectionState == .connecting else { return }
            teardown()
            scheduleReconnect()
        }
    }

    private func teardown() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        client?.disconnect()
        client = nil
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
    }

    private func scheduleReconnect() {
        teardown()
        let creds = store.load()
        guard creds.rememberMe, let u = creds.username, let p = creds.password else {
            connectionState = .disconnected
            statusMessage = "Disconnected"
            return
        }
        guard reconnectAttempt < Self.maxReconnectAttempts else {
            connectionState = .disconnected
            connectionError = "Could not reconnect — please log in again"
            reconnectAttempt = 0
            return
        }
        let delay = pow(2.0, Double(reconnectAttempt))   // 1, 2, 4, 8, 16 s
        reconnectAttempt += 1
        connectionState = .reconnecting
        statusMessage = "Reconnecting..."
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, connectionState == .reconnecting else { return }
            connectionState = .connecting
            createClient(username: u, password: p)
        }
    }

    nonisolated func notify(_ message: String) {
        Task { @MainActor [weak self] in
            self?.notificationMessage = message
            try? await Task.sleep(for: .seconds(2.5))
            if self?.notificationMessage == message {
                self?.notificationMessage = nil
            }
        }
    }
}

// MARK: - Models

private struct GateCommand: Encodable {
    let action: String
}

// MARK: - CocoaMQTT5Delegate

extension MQTTManager: CocoaMQTT5Delegate {

    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            if ack == .success {
                reconnectAttempt = 0
                reconnectTask = nil
                connectionState = .connected
                statusMessage = "Connected"
                notify("Connected successfully")
                mqtt5.subscribe("gate/status", qos: .qos1)
                mqtt5.subscribe("gate/responses/#", qos: .qos1)
            } else {
                connectionState = .disconnected
                statusMessage = "Disconnected"
                let isBadCreds = ack == .badUsernameOrPassword || ack == .notAuthorized
                connectionError = isBadCreds
                    ? "Invalid username or password"
                    : "Connection failed"
                notify("Connection failed")
            }
        }
    }

    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?) {
        if message.topic == "gate/status" {
            let status = message.string
            Task { @MainActor [weak self] in self?.gateStatus = status }
            return
        }

        guard message.topic.hasPrefix("gate/responses/") else { return }

        guard let payload = message.string,
              let jsonData = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let corrData = publishData?.correlationData,
              let correlationId = String(bytes: corrData, encoding: .utf8)
        else { return }

        let success = (json["status"] as? String) == "success"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let action = pendingCommands.removeValue(forKey: correlationId)
            if let action { statusMessage = "\(action): \(success ? "Success" : "Failed")" }
        }
    }

    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {
        Task { @MainActor [weak self] in self?.sendingAction = nil }
    }

    nonisolated func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: Error?) {
        Task { @MainActor [weak self] in
            guard let self, mqtt5 === client,
                  connectionState == .connected || connectionState == .connecting else { return }
            sendingAction = nil
            scheduleReconnect()
        }
    }

    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: MqttDecodeSubAck?) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didUnsubscribeTopics topics: [String], unsubAckData: MqttDecodeUnsubAck?) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode) {}
    nonisolated func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode) {}
    nonisolated func mqtt5DidPing(_ mqtt5: CocoaMQTT5) {}
    nonisolated func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5) {}

    // CocoaMQTT bug: if this optional method is not implemented the TLS completion
    // handler is never called, causing error -1200 (NSURLErrorSecureConnectionFailed).
    nonisolated func mqtt5UrlSession(_ mqtt: CocoaMQTT5, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}
