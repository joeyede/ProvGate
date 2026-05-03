import Foundation
import Testing
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

// MARK: - CredentialsStore

@Suite(.serialized)
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
