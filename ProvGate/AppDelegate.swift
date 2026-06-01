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
        return true
    }
}
