import Foundation
import Testing
import CocoaMQTT
import UIKit
@testable import ProvGate

// MARK: - Helpers

/// Isolated credential store for tests — never touches the real app-group keychain.
private func testStore() -> CredentialsStore {
    CredentialsStore(service: "ProvGate.MQTT.test")
}

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

// MARK: - Home Screen Quick Actions

struct QuickActionTests {
    @Test func actionMappingUsesInsidePerspective() {
        #expect(QuickActions.Kind.open.action       == "full")
        #expect(QuickActions.Kind.pedestrian.action == "pedestrian")
        // Inside perspective: no left↔right swap.
        #expect(QuickActions.Kind.left.action  == "left")
        #expect(QuickActions.Kind.right.action == "right")
    }

    @Test func shortcutTypesAreUniqueAndRoundTrip() {
        let types = QuickActions.Kind.allCases.map(\.rawValue)
        #expect(Set(types).count == types.count)
        for kind in QuickActions.Kind.allCases {
            #expect(QuickActions.Kind(rawValue: kind.shortcutItem.type) == kind)
        }
    }

    @Test func unknownShortcutTypeIsNotHandled() {
        let unknown = UIApplicationShortcutItem(type: "BitChor.ProvGate.quickaction.bogus", localizedTitle: "x")
        #expect(QuickActions.handle(unknown) == false)
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
        let rawBytes = Array(encoded.dropFirst(2))
        let decoded = String(bytes: rawBytes, encoding: .utf8)
        #expect(decoded == id)
    }
}

// MARK: - Credential-sensitive tests
// Serialized so keychain reads/writes don't race across suites.

@Suite(.serialized)
struct CredentialSensitiveTests {

    // MARK: CredentialsStore

    struct CredentialsStoreTests {
        let store = testStore()
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
    }

    // MARK: scheduleReconnect backoff and state transitions

    @MainActor
    struct ScheduleReconnectTests {
        let store = testStore()
        init() { store.clear() }

        @Test func noCredentialsGuardTransitionsToDisconnected() {
            let manager = MQTTManager(store: store)
            manager.testHook_scheduleReconnect()
            #expect(manager.connectionState == .disconnected)
            #expect(manager.statusMessage == "Disconnected")
        }

        @Test func firstCallGoesToReconnectingAndIncrementsAttempt() {
            let manager = MQTTManager(store: store)
            store.save(username: "u", password: "p", rememberMe: true)
            manager.testHook_scheduleReconnect()
            #expect(manager.connectionState == .reconnecting)
            #expect(manager.reconnectAttempt == 1)
            manager.disconnect()
        }

        @Test func exceedingMaxAttemptsTransitionsToDisconnectedWithError() {
            let manager = MQTTManager(store: store)
            store.save(username: "u", password: "p", rememberMe: true)
            for _ in 0...MQTTManager.maxReconnectAttempts {
                manager.testHook_scheduleReconnect()
            }
            #expect(manager.connectionState == .disconnected)
            #expect(manager.connectionError != nil)
            manager.disconnect()
        }
    }

    // MARK: sendingAction guards

    @MainActor
    struct SendingActionTests {
        let store = testStore()
        init() { store.clear() }

        @Test func sendingActionIsNilOnStartup() {
            let manager = MQTTManager(store: store)
            #expect(manager.sendingAction == nil)
        }

        @Test func sendCommandWhenNotConnectedDoesNotSetSendingAction() {
            let manager = MQTTManager(store: store)
            manager.sendCommand("full")
            #expect(manager.sendingAction == nil)
            #expect(manager.statusMessage == "Not connected")
        }
    }

    // MARK: handleAppBecameActive guards

    @MainActor
    struct HandleAppBecameActiveGuardTests {
        let store = testStore()
        init() { store.clear() }

        @Test func noOpWhenDisconnectedAndNoCredentialsSaved() {
            let manager = MQTTManager(store: store)
            #expect(manager.connectionState == .disconnected)
            manager.handleAppBecameActive()
            #expect(manager.connectionState == .disconnected)
        }

        @Test func withSavedCredentialsTransitionsToConnecting() {
            let manager = MQTTManager(store: store)
            store.save(username: "u", password: "p", rememberMe: true)
            manager.handleAppBecameActive()
            #expect(manager.connectionState == .connecting)
            manager.disconnect()
        }

        @Test func connectingStateIsNoOp() {
            let manager = MQTTManager(store: store)
            manager.connect(username: "u", password: "p", rememberMe: false)
            #expect(manager.connectionState == .connecting)
            manager.handleAppBecameActive()
            #expect(manager.connectionState == .connecting)
            manager.disconnect()
        }
    }

    // MARK: notify deduplication

    @MainActor
    struct NotifyTests {
        let store = testStore()
        init() { store.clear() }

        @Test func secondNotificationReplacesFirst() async {
            let manager = MQTTManager(store: store)
            manager.notify("first")
            await Task.yield()
            #expect(manager.notificationMessage == "first")
            manager.notify("second")
            await Task.yield()
            #expect(manager.notificationMessage == "second")
        }
    }

    // MARK: stale-client disconnect guard

    @MainActor
    struct StaleDisconnectGuardTests {
        let store = testStore()
        init() { store.clear() }

        @Test func staleClientDisconnectDoesNotTriggerReconnect() async throws {
            let manager = MQTTManager(store: store)
            let stale = CocoaMQTT5(clientID: "stale", host: "192.0.2.1", port: 8884)
            manager.mqtt5DidDisconnect(stale, withError: nil)
            try await Task.sleep(for: .milliseconds(50))
            #expect(manager.connectionState == .disconnected)
        }
    }

    // MARK: Dry run flag

    @MainActor
    struct DryRunFlagTests {
        let store = testStore()
        // Isolated UserDefaults suite — actually injected into MQTTManager so we
        // never touch the real app-group flag.
        let dryRunDefaults = UserDefaults(suiteName: "ProvGate.test.dryRun")!

        init() {
            store.clear()
            dryRunDefaults.removeObject(forKey: "provgate.isDryRun")
        }

        @Test func defaultsToFalseWhenSuiteIsEmpty() {
            let manager = MQTTManager(store: store, defaults: dryRunDefaults)
            #expect(manager.isDryRun == false)
        }

        @Test func initialValueIsReadFromInjectedDefaults() {
            dryRunDefaults.set(true, forKey: "provgate.isDryRun")
            let manager = MQTTManager(store: store, defaults: dryRunDefaults)
            #expect(manager.isDryRun == true)
        }

        @Test func setDryRunToSameValueIsNoOp() {
            let manager = MQTTManager(store: store, defaults: dryRunDefaults)
            let before = manager.connectionState
            manager.setDryRun(false)
            #expect(manager.connectionState == before)
        }

        @Test func setDryRunWhileDisconnectedUpdatesFlagAndPersists() {
            let manager = MQTTManager(store: store, defaults: dryRunDefaults)
            #expect(manager.connectionState == .disconnected)
            manager.setDryRun(true)
            #expect(manager.isDryRun == true)
            #expect(dryRunDefaults.bool(forKey: "provgate.isDryRun") == true)
            // No reconnect attempt — state stays disconnected
            #expect(manager.connectionState == .disconnected)
            manager.setDryRun(false)
            #expect(manager.isDryRun == false)
            #expect(dryRunDefaults.bool(forKey: "provgate.isDryRun") == false)
        }

        @Test func setDryRunWithSavedCredsWhileConnectingTriggersNoReconnect() {
            // setDryRun only reconnects when already .connected
            let manager = MQTTManager(store: store, defaults: dryRunDefaults)
            store.save(username: "u", password: "p", rememberMe: true)
            manager.connect(username: "u", password: "p", rememberMe: true)
            #expect(manager.connectionState == .connecting)
            manager.setDryRun(true)
            // Still connecting — setDryRun guard fires (not .connected), no extra reconnect
            #expect(manager.isDryRun == true)
            #expect(manager.connectionState == .connecting)
            manager.disconnect()
        }
    }

}

// MARK: - CarPlay button specs

struct CarPlayButtonTests {
    let specs = CarPlaySceneDelegate.buttonSpecs()

    @Test func exactlyThreeButtons() {
        #expect(specs.count == 3)
    }

    @Test func noPedestrianInCarPlay() {
        #expect(!specs.contains { $0.title == "Pedestrian" })
    }

    @Test func leftButtonUsesOutsidePerspective() {
        let spec = specs.first { $0.title == "Left" }!
        #expect(spec.action == "right")
    }

    @Test func rightButtonUsesOutsidePerspective() {
        let spec = specs.first { $0.title == "Right" }!
        #expect(spec.action == "left")
    }

    @Test func fullOpenActionIsCorrect() {
        let full = specs.first { $0.title == "Full Open" }!
        #expect(full.action == "full")
    }

    @Test func fullOpenIsProminentAndOthersAreNot() {
        let full   = specs.first { $0.title == "Full Open" }!
        let others = specs.filter { $0.title != "Full Open" }
        #expect(full.prominent == true)
        #expect(others.allSatisfy { !$0.prominent })
    }

    @Test func leftAndRightDetailIndicatesOutsideView() {
        let left  = specs.first { $0.title == "Left" }!
        let right = specs.first { $0.title == "Right" }!
        let full  = specs.first { $0.title == "Full Open" }!
        #expect(left.detail == "Outside view")
        #expect(right.detail == "Outside view")
        #expect(full.detail == "")
    }

    @Test func fullOpenIsFirst() {
        #expect(specs[0].title == "Full Open")
    }
}
