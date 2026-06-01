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
        mqtt = (UIApplication.shared.delegate as! AppDelegate).mqtt
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

    private func makeButtons(enabled: Bool) -> [CPGridButton] {
        let specs: [(title: String, symbol: String, action: String)] = [
            ("Pedestrian", "figure.walk",       "pedestrian"),
            ("Full Open",  "door.garage.open",  "full"),
            ("Left",       "arrow.left",        GateHelpers.resolvedAction("left",  isOutsideView: true)),
            ("Right",      "arrow.right",       GateHelpers.resolvedAction("right", isOutsideView: true)),
        ]
        return specs.map { spec in
            let img = UIImage(systemName: spec.symbol,
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 60))
                ?? UIImage(systemName: "square")!
            let btn = CPGridButton(titleVariants: [spec.title], image: img) { [weak self] _ in
                self?.mqtt?.sendCommand(spec.action)
            }
            btn.isEnabled = enabled
            return btn
        }
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
