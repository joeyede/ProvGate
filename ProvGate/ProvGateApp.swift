import SwiftUI
import AppIntents

@main
struct ProvGateApp: App {
    @State private var mqtt = MQTTManager()

    init() {
        GateShortcuts.updateAppShortcutParameters()
        #if DEBUG
        // Clear saved credentials so UI tests always start from a known state.
        if CommandLine.arguments.contains("-UITestMode") ||
           CommandLine.arguments.contains("-UITestForceConnected") ||
           CommandLine.arguments.contains("-UITestForceConnecting") {
            CredentialsStore(keychainAccessGroup: GateHelpers.appGroup,
                             userDefaultsSuite: GateHelpers.appGroup).clear()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(mqtt)
        }
    }
}
