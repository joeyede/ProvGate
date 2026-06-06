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
        let template = mqtt.connectionState == .connected ? makeStripTemplate() : makeConnectingTemplate()
        interfaceController.setRootTemplate(template, animated: animated, completion: nil)
    }

    private func makeStripTemplate() -> CPListTemplate {
        let specs = Self.buttonSpecs()
        let images = specs.map { Self.stripImage(symbol: $0.symbol, label: $0.title, showsLeaf: !$0.prominent) }
        let elements = images.map { CPListImageRowItemRowElement(image: $0, title: nil, subtitle: nil) }
        let strip = CPListImageRowItem(text: "Outside view", elements: elements, allowsMultipleLines: false)
        strip.handler = { _, completion in completion() }
        strip.listImageRowHandler = { [weak self] _, index, completion in
            guard index < specs.count else { completion(); return }
            self?.mqtt?.sendCommand(specs[index].action)
            completion()
        }
        return CPListTemplate(title: "ProvGate", sections: [CPListSection(items: [strip])])
    }

    private func makeConnectingTemplate() -> CPListTemplate {
        let item = CPListItem(text: "Connecting to gate\u{2026}", detailText: nil)
        return CPListTemplate(title: "ProvGate", sections: [CPListSection(items: [item])])
    }

    // Pedestrian omitted — not needed in CarPlay context.
    // Directional actions use the outside perspective (left/right swapped).
    internal static func buttonSpecs() -> [(title: String, symbol: String, action: String, prominent: Bool)] {
        [
            ("Left",      "arrow.left",                         GateHelpers.resolvedAction("left",  isOutsideView: true), false),
            ("Right",     "arrow.right",                        GateHelpers.resolvedAction("right", isOutsideView: true), false),
            ("Full Open", "arrow.up.left.and.arrow.down.right", "full",                                                   true),
        ]
    }

    // Blue rounded-rect button with white SF symbol, label, and optional leaf indicator — all
    // inside the button, matching the phone UI. Horizontal padding is transparent to gap icons.
    private static func stripImage(symbol: String, label: String, showsLeaf: Bool) -> UIImage {
        let s = CPListImageRowItemRowElement.maximumImageSize
        let hPad: CGFloat  = s.width * 0.18
        let iconW: CGFloat = s.width - hPad * 2

        let symbolH: CGFloat = s.height * (showsLeaf ? 0.52 : 0.60)
        let labelH: CGFloat  = s.height * (showsLeaf ? 0.26 : 0.40)
        let leafH: CGFloat   = s.height - symbolH - labelH

        let renderer = UIGraphicsImageRenderer(size: s)
        let image = renderer.image { _ in
            UIColor.systemBlue.setFill()
            UIBezierPath(roundedRect: CGRect(x: hPad, y: 0, width: iconW, height: s.height),
                         cornerRadius: iconW * 0.22).fill()

            let config = UIImage.SymbolConfiguration(pointSize: iconW * 0.40, weight: .semibold)
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(
                    x: hPad + (iconW - glyph.size.width) / 2,
                    y: (symbolH - glyph.size.height) / 2
                ))
            }

            let font = UIFont.systemFont(ofSize: iconW * 0.175, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let str = label as NSString
            let textSize = str.size(withAttributes: attrs)
            str.draw(at: CGPoint(
                x: (s.width - textSize.width) / 2,
                y: symbolH + (labelH - textSize.height) / 2
            ), withAttributes: attrs)

            if showsLeaf {
                let leafConfig = UIImage.SymbolConfiguration(pointSize: iconW * 0.16, weight: .medium)
                if let leaf = UIImage(systemName: "leaf", withConfiguration: leafConfig)?
                    .withTintColor(.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
                    leaf.draw(at: CGPoint(
                        x: (s.width - leaf.size.width) / 2,
                        y: symbolH + labelH + (leafH - leaf.size.height) / 2
                    ))
                }
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
