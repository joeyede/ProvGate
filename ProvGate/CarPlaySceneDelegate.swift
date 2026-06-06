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
            let specs = Self.buttonSpecs()
            let images = specs.map { Self.stripImage(symbol: $0.symbol, prominent: $0.prominent) }
            let strip = CPListImageRowItem(text: "Outside view", images: images)
            strip.listImageRowHandler = { [weak self] _, index, completion in
                guard index < specs.count else { completion(); return }
                self?.mqtt?.sendCommand(specs[index].action)
                completion()
            }
            let section = CPListSection(items: [strip])
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
            ("Left",      "Outside view", "arrow.left",                          GateHelpers.resolvedAction("left",  isOutsideView: true), false),
            ("Right",     "Outside view", "arrow.right",                         GateHelpers.resolvedAction("right", isOutsideView: true), false),
            ("Full Open", "",             "arrow.up.left.and.arrow.down.right",  "full",                                                   true),
        ]
    }

    // Colored rounded-rect button image for the image strip.
    private static func stripImage(symbol: String, prominent: Bool) -> UIImage {
        let size = CPListImageRowItem.maximumImageSize
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let bg = UIBezierPath(roundedRect: rect, cornerRadius: size.width * 0.22)
            (prominent ? UIColor.systemBlue : UIColor.secondarySystemFill).setFill()
            bg.fill()

            let weight: UIImage.SymbolWeight = prominent ? .black : .semibold
            let config = UIImage.SymbolConfiguration(pointSize: size.width * 0.42, weight: weight)
            let tint: UIColor = prominent ? .white : .label
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(tint, renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(
                    x: (size.width  - glyph.size.width)  / 2,
                    y: (size.height - glyph.size.height) / 2
                ))
            }
        }
        return image.withRenderingMode(.alwaysOriginal)
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
