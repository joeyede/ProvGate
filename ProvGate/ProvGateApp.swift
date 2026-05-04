import SwiftUI
import AppIntents

@main
struct ProvGateApp: App {
    @State private var mqtt = MQTTManager()

    init() {
        GateShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(mqtt)
        }
    }
}
