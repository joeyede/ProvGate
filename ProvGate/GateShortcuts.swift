import AppIntents

// MARK: - App Shortcuts (registers Siri phrases automatically)

struct GateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PedestrianIntent(),
            phrases: [
                "Open pedestrian gate with \(.applicationName)",
                "Open pedestrian with \(.applicationName)"
            ],
            shortTitle: "Pedestrian Gate",
            systemImageName: "figure.walk"
        )
        AppShortcut(
            intent: OpenGateIntent(),
            phrases: [
                "Open Gate with \(.applicationName)",
                "Open the gate with \(.applicationName)"
            ],
            shortTitle: "Open Gate",
            systemImageName: "arrow.up.left.and.arrow.down.right"
        )
        AppShortcut(
            intent: OpenInsideRightIntent(),
            phrases: ["Open inside right with \(.applicationName)"],
            shortTitle: "Inside Right",
            systemImageName: "arrow.right"
        )
        AppShortcut(
            intent: OpenInsideLeftIntent(),
            phrases: ["Open inside left with \(.applicationName)"],
            shortTitle: "Inside Left",
            systemImageName: "arrow.left"
        )
        AppShortcut(
            intent: OpenOutsideRightIntent(),
            phrases: ["Open outside right with \(.applicationName)"],
            shortTitle: "Outside Right",
            systemImageName: "arrow.right"
        )
        AppShortcut(
            intent: OpenOutsideLeftIntent(),
            phrases: ["Open outside left with \(.applicationName)"],
            shortTitle: "Outside Left",
            systemImageName: "arrow.left"
        )
    }
}
