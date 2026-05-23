import AppIntents

// MARK: - App Shortcuts (registers Siri phrases automatically)

struct GateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenGateIntent(),
            phrases: [
                "Open the gate with \(.applicationName)",
                "Open gate with \(.applicationName)",
                "Full open with \(.applicationName)",
                "Open the \(.applicationName)",
            ],
            shortTitle: "Open Gate",
            systemImageName: "arrow.up.left.and.arrow.down.right"
        )
        AppShortcut(
            intent: PedestrianIntent(),
            phrases: [
                "Open pedestrian gate with \(.applicationName)",
                "Pedestrian gate with \(.applicationName)",
                "Open pedestrian with \(.applicationName)",
            ],
            shortTitle: "Pedestrian Gate",
            systemImageName: "figure.walk"
        )
        AppShortcut(
            intent: OpenOutsideLeftIntent(),
            phrases: [
                "Open left gate with \(.applicationName)",
                "Left gate with \(.applicationName)",
            ],
            shortTitle: "Left Gate",
            systemImageName: "arrow.left"
        )
        AppShortcut(
            intent: OpenOutsideRightIntent(),
            phrases: [
                "Open right gate with \(.applicationName)",
                "Right gate with \(.applicationName)",
            ],
            shortTitle: "Right Gate",
            systemImageName: "arrow.right"
        )
    }
}
