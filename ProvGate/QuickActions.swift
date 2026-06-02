import UIKit

/// Home Screen long-press Quick Actions (the icon context menu).
///
/// These are a different mechanism from the Siri App Shortcuts in
/// `GateShortcuts.swift`: those surface in Spotlight / Siri / the Shortcuts
/// app, while these populate the icon long-press menu via `UIApplicationShortcutItem`.
/// Left/right use the inside perspective (no left↔right swap), matching the
/// app's default view when you open it.
enum QuickActions {

    enum Kind: String, CaseIterable {
        case open       = "BitChor.ProvGate.quickaction.open"
        case pedestrian = "BitChor.ProvGate.quickaction.pedestrian"
        case left       = "BitChor.ProvGate.quickaction.left"
        case right      = "BitChor.ProvGate.quickaction.right"

        var title: String {
            switch self {
            case .open:       return "Open Gate"
            case .pedestrian: return "Pedestrian"
            case .left:       return "Open Inside Left"
            case .right:      return "Open Inside Right"
            }
        }

        var symbol: String {
            switch self {
            case .open:       return "arrow.up.left.and.arrow.down.right"
            case .pedestrian: return "figure.walk"
            case .left:       return "arrow.left"
            case .right:      return "arrow.right"
            }
        }

        var action: String {
            switch self {
            case .open:       return "full"
            case .pedestrian: return "pedestrian"
            case .left:       return "left"
            case .right:      return "right"
            }
        }

        var shortcutItem: UIApplicationShortcutItem {
            UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: title,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: symbol),
                userInfo: nil
            )
        }
    }

    /// Register the quick actions with the system. Safe to call on every launch.
    static func register(on application: UIApplication) {
        application.shortcutItems = Kind.allCases.map(\.shortcutItem)
    }

    /// Fire the gate command for a tapped quick action. Returns whether it was handled.
    @discardableResult
    static func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let kind = Kind(rawValue: shortcutItem.type) else { return false }
        let action = kind.action
        Task { try? await GateCommandSender.send(action: action) }
        return true
    }
}

/// Window-scene delegate whose only job is to deliver Home Screen Quick Actions.
///
/// It deliberately does **not** create or touch `window` — SwiftUI's
/// `WindowGroup` still owns the scene's content; assigning our own window here
/// would shadow it with a blank screen.
final class PhoneSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            QuickActions.handle(item)
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(QuickActions.handle(shortcutItem))
    }
}
