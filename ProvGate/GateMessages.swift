import Foundation

// Shared MQTT topic names and message types used by MQTTManager and GateCommandSender.

let gateControlTopic = "gate/control"

struct GateCommand: Encodable {
    let action: String
}
