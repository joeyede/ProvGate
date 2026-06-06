import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var mqtt: MQTTManager?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        mqtt = AppDelegate.current!.mqtt
        setTemplate(animated: false)
        observe()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func setTemplate(animated: Bool) {
        guard let mqtt, let interfaceController else { return }
        let connected = mqtt.connectionState == .connected
        let template: CPListTemplate
        if connected {
            let items = Self.buttonSpecs().map { spec -> CPListItem in
                let item = CPListItem(
                    text: spec.title,
                    detailText: spec.detail,
                    image: Self.listImage(symbol: spec.symbol, prominent: spec.prominent)
                )
                item.handler = { [weak self] _, completion in
                    self?.mqtt?.sendCommand(spec.action)
                    completion()
                }
                return item
            }
            let section = CPListSection(items: items, header: "Actions", sectionIndexTitle: nil)
            template = CPListTemplate(title: "ProvGate", sections: [section])
        } else {
            let item = CPListItem(text: "Connecting to gate\u{2026}", detailText: nil)
            let section = CPListSection(items: [item])
            template = CPListTemplate(title: "ProvGate", sections: [section])
        }
        interfaceController.setRootTemplate(template, animated: animated, completion: nil)
    }

    // Pedestrian omitted — not needed in CarPlay context.
    // Directional actions use the outside perspective (left/right swapped).
    internal static func buttonSpecs() -> [(title: String, detail: String, symbol: String, action: String, prominent: Bool)] {
        [
            ("Full Open", "",             "arrow.up.left.and.arrow.down.right",  "full",                                                   true),
            ("Left",      "Outside view", "arrow.left",                          GateHelpers.resolvedAction("left",  isOutsideView: true), false),
            ("Right",     "Outside view", "arrow.right",                         GateHelpers.resolvedAction("right", isOutsideView: true), false),
        ]
    }

    // Full-color SF Symbol for list row leading image.
    private static func listImage(symbol: String, prominent: Bool) -> UIImage {
        let pointSize: CGFloat = prominent ? 28 : 24
        let weight: UIImage.SymbolWeight = prominent ? .black : .semibold
        let color: UIColor = prominent ? .systemBlue : .label
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return (UIImage(systemName: symbol, withConfiguration: config) ?? UIImage())
            .withTintColor(color, renderingMode: .alwaysOriginal)
    }

    private func observe() {
        guard let mqtt else { return }
        withObservationTracking {
            _ = mqtt.connectionState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.setTemplate(animated: true)
                self?.observe()
            }
        }
    }
}
