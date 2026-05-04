import AppIntents

// MARK: - Open Gate (full open)

struct OpenGateIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Gate"
    static let description = IntentDescription("Fully open the gate")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await GateCommandSender.send(action: "full")
        return .result(dialog: "Gate opened")
    }
}

// MARK: - Directional (inside perspective)

struct OpenInsideRightIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Inside Right"
    static let description = IntentDescription("Open the right gate panel from inside")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await GateCommandSender.send(action: "right")
        return .result(dialog: "Right panel opened")
    }
}

struct OpenInsideLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Inside Left"
    static let description = IntentDescription("Open the left gate panel from inside")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await GateCommandSender.send(action: "left")
        return .result(dialog: "Left panel opened")
    }
}

// MARK: - Directional (outside perspective — left/right mirrored)
// resolvedAction(isOutsideView: true) swaps left↔right so the physical
// panel matches the user's perspective when standing outside the gate.

struct OpenOutsideRightIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Outside Right"
    static let description = IntentDescription("Open the right gate panel from outside")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let action = MQTTManager.resolvedAction("right", isOutsideView: true)
        try await GateCommandSender.send(action: action)
        return .result(dialog: "Right panel opened")
    }
}

struct OpenOutsideLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Outside Left"
    static let description = IntentDescription("Open the left gate panel from outside")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let action = MQTTManager.resolvedAction("left", isOutsideView: true)
        try await GateCommandSender.send(action: action)
        return .result(dialog: "Left panel opened")
    }
}

// MARK: - App Shortcuts (registers Siri phrases automatically)

struct GateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
