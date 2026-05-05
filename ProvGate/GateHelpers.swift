import Foundation

enum GateHelpers {
    // Shared by the main app and the GateWidget extension for keychain + UserDefaults sharing.
    static let appGroup = "group.BitChor.ProvGate"

    // Swaps left↔right when the user is viewing the gate from outside.
    nonisolated static func resolvedAction(_ action: String, isOutsideView: Bool) -> String {
        if (action == "left" || action == "right") && isOutsideView {
            return action == "left" ? "right" : "left"
        }
        return action
    }

    // CocoaMQTT5 expects correlationData in MQTT5 Binary Data wire format:
    // a 2-byte big-endian length prefix followed by the raw bytes. The library
    // strips the prefix before delivering corrData to didReceiveMessage.
    nonisolated static func encodeCorrelationId(_ id: String) -> [UInt8] {
        let bytes = Array(id.utf8)
        return [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)] + bytes
    }
}
