import Foundation
import Testing
import CocoaMQTT
@testable import ProvGate

// MARK: - Left/right action swap

struct ActionSwapTests {
    @Test func insideViewPreservesLeftRight() {
        #expect(MQTTManager.resolvedAction("left",  isOutsideView: false) == "left")
        #expect(MQTTManager.resolvedAction("right", isOutsideView: false) == "right")
    }

    @Test func outsideViewSwapsLeftRight() {
        #expect(MQTTManager.resolvedAction("left",  isOutsideView: true) == "right")
        #expect(MQTTManager.resolvedAction("right", isOutsideView: true) == "left")
    }

    @Test func nonDirectionalActionsAreUnaffected() {
        #expect(MQTTManager.resolvedAction("pedestrian", isOutsideView: true)  == "pedestrian")
        #expect(MQTTManager.resolvedAction("full",       isOutsideView: true)  == "full")
        #expect(MQTTManager.resolvedAction("pedestrian", isOutsideView: false) == "pedestrian")
    }
}

// MARK: - Correlation ID encoding

struct CorrelationIdTests {
    @Test func encodingHasCorrectLengthPrefix() {
        let id = "hello"
        let encoded = MQTTManager.encodeCorrelationId(id)
        let expectedLength = id.utf8.count
        #expect(encoded[0] == UInt8(expectedLength >> 8))
        #expect(encoded[1] == UInt8(expectedLength & 0xFF))
        #expect(encoded.count == 2 + expectedLength)
    }

    @Test func uuidRoundTrip() {
        let id = "123e4567-e89b-12d3-a456-426614174000"
        let encoded = MQTTManager.encodeCorrelationId(id)
        // The broker strips the two-byte length prefix before delivering correlationData
        let rawBytes = Array(encoded.dropFirst(2))
        let decoded = String(bytes: rawBytes, encoding: .utf8)
        #expect(decoded == id)
    }
}

// MARK: - Credential-sensitive tests
// Serialized so that keychain reads/writes across suites don't race.

@Suite(.serialized)
struct CredentialSensitiveTests {

    // MARK: CredentialsStore

    struct CredentialsStoreTests {
        let store = CredentialsStore()

        init() { store.clear() }

        @Test func freshStoreReturnsNilCredentials() {
            let c = store.load()
            #expect(c.username == nil)
            #expect(c.password == nil)
            #expect(c.rememberMe == false)
        }

        @Test func saveAndLoadRoundTrip() {
            store.save(username: "testuser", password: "s3cret", rememberMe: true)
            let c = store.load()
            #expect(c.username == "testuser")
            #expect(c.password == "s3cret")
            #expect(c.rememberMe == true)
        }

        @Test func clearRemovesAllCredentials() {
            store.save(username: "testuser", password: "s3cret", rememberMe: true)
            store.clear()
            let c = store.load()
            #expect(c.username == nil)
            #expect(c.password == nil)
            #expect(c.rememberMe == false)
        }

        @Test func saveWithRememberMeFalseDoesNotPersistCredentials() {
            store.save(username: "user", password: "pass", rememberMe: false)
            let c = store.load()
            #expect(c.username == nil)
            #expect(c.password == nil)
            #expect(c.rememberMe == false)
        }
    }

    // MARK: Bug fix 1 — loadingAction → sendingAction rename

    @MainActor
    struct SendingActionTests {
        init() { CredentialsStore().clear() }

        @Test func sendingActionIsNilOnStartup() {
            let manager = MQTTManager()
            #expect(manager.sendingAction == nil)
        }

        // sendCommand guard must not set sendingAction when not connected
        @Test func sendCommandWhenNotConnectedDoesNotSetSendingAction() {
            let manager = MQTTManager()
            manager.sendCommand("full")
            #expect(manager.sendingAction == nil)
            #expect(manager.statusMessage == "Not connected")
        }
    }

    // MARK: Bug fix 2 — handleAppBecameActive .reconnecting guard

    @MainActor
    struct HandleAppBecameActiveGuardTests {
        init() { CredentialsStore().clear() }

        // .disconnected + no credentials → credentials guard fires, state unchanged
        @Test func noOpWhenDisconnectedAndNoCredentialsSaved() {
            let manager = MQTTManager()
            #expect(manager.connectionState == .disconnected)
            manager.handleAppBecameActive()
            #expect(manager.connectionState == .disconnected)
        }
    }

    // MARK: Bug fix 3 — mqtt5DidDisconnect stale-client guard

    @MainActor
    struct StaleDisconnectGuardTests {
        init() { CredentialsStore().clear() }

        // client is nil after clean startup; mqtt5 === client is false for any non-nil instance
        @Test func staleClientDisconnectDoesNotTriggerReconnect() async throws {
            let manager = MQTTManager()
            let stale = CocoaMQTT5(clientID: "stale", host: "test.example.com", port: 8884)
            manager.mqtt5DidDisconnect(stale, withError: nil)
            try await Task.sleep(for: .milliseconds(50))
            #expect(manager.connectionState == .disconnected)
        }
    }
}
