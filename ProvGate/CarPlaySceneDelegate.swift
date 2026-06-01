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
        let template = CPGridTemplate(title: "ProvGate", gridButtons: makeButtons(enabled: connected))
        interfaceController.setRootTemplate(template, animated: animated, completion: nil)
    }

    // 3-button row: Left | Right | Full Open (rightmost, visually dominant).
    // Pedestrian omitted — not needed in CarPlay context.
    internal static func buttonSpecs() -> [(titles: [String], symbol: String, action: String, prominent: Bool)] {
        [
            (["Left (Outside)",   "Outside L", "Left"], "arrow.left",                        GateHelpers.resolvedAction("left",  isOutsideView: true), false),
            (["Right (Outside)",  "Outside R", "Right"],"arrow.right",                      GateHelpers.resolvedAction("right", isOutsideView: true), false),
            (["Full Open",        "Full"],               "arrow.up.left.and.arrow.down.right", "full",                                                 true),
        ]
    }

    private func makeButtons(enabled: Bool) -> [CPGridButton] {
        return Self.buttonSpecs().map { spec in
            let img = Self.buttonImage(symbol: spec.symbol, prominent: spec.prominent)
            let btn = CPGridButton(titleVariants: spec.titles, image: img) { [weak self] _ in
                self?.mqtt?.sendCommand(spec.action)
            }
            btn.isEnabled = enabled
            return btn
        }
    }

    // Renders the arrow glyph centred inside a rounded-rectangle border on a
    // fixed square canvas. The uniform canvas size keeps every button's label
    // vertically aligned, and the border gives each icon a tappable button look.
    // Returned as a template image so CarPlay tints it for light/dark dashboards.
    private static func buttonImage(symbol: String, prominent: Bool) -> UIImage {
        let canvas = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { _ in
            let border = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: canvas).insetBy(dx: 4, dy: 4),
                cornerRadius: 18)
            border.lineWidth = prominent ? 6 : 4
            UIColor.black.setStroke()
            border.stroke()

            let weight: UIImage.SymbolWeight = prominent ? .black : .heavy
            let config = UIImage.SymbolConfiguration(pointSize: 44, weight: weight)
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(.black, renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(x: (canvas.width - glyph.size.width) / 2,
                                       y: (canvas.height - glyph.size.height) / 2))
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
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
