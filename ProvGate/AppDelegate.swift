import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    let mqtt = MQTTManager()

    // UIApplication.shared.delegate is SwiftUI's internal wrapper in iOS 26+,
    // so CarPlaySceneDelegate can't cast it. Stash ourselves here instead.
    private(set) static var current: AppDelegate?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppDelegate.current = self
        QuickActions.register(on: application)
        return true
    }

    // Route the phone window scene through PhoneSceneDelegate so we receive
    // Home Screen Quick Actions (cold + warm launch). CarPlay keeps its own
    // Info.plist-defined delegate.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Raw value avoids importing CarPlay just to name the role enum case.
        if connectingSceneSession.role.rawValue == "CPTemplateApplicationSceneSessionRoleApplication" {
            return UISceneConfiguration(name: "CarPlay Configuration", sessionRole: connectingSceneSession.role)
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = PhoneSceneDelegate.self
        return config
    }
}
