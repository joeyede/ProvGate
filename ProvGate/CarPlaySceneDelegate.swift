import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var mqtt: MQTTManager?
    private var connectedTemplate: CPListTemplate?
    // Incremented on every connect/disconnect so stale onChange tasks don't re-register.
    private var observationVersion = 0

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        mqtt = AppDelegate.current!.mqtt
        observationVersion += 1
        setTemplate(animated: false)
        observe()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        observationVersion += 1  // kills any pending onChange tasks from this session
        self.interfaceController = nil
        connectedTemplate = nil
    }

    private func setTemplate(animated: Bool) {
        guard let mqtt, let interfaceController else { return }
        if mqtt.connectionState == .connected {
            let template = CPListTemplate(title: "ProvGate", sections: makeSections())
            connectedTemplate = template
            interfaceController.setRootTemplate(template, animated: animated, completion: nil)
        } else {
            connectedTemplate = nil
            interfaceController.setRootTemplate(makeConnectingTemplate(), animated: animated, completion: nil)
        }
    }

    private func refreshTemplate() {
        // Always recreate via setRootTemplate rather than updateSections — CarPlay's
        // first updateSections call after setRootTemplate triggers a layout recalculation
        // that causes a visible aspect shift. setRootTemplate(animated:false) is instant.
        let animated = connectedTemplate == nil || mqtt?.connectionState != .connected
        setTemplate(animated: animated)
    }

    // Three-column layout: left info/toggle panel + two action buttons per row.
    //   Row 1: [ Status       ] [ Pedestrian ] [ Full Open ]
    //   Row 2: [ Inside/Outside] [   Left    ] [   Right   ]
    private func makeSections() -> [CPListSection] {
        guard let mqtt else { return [] }
        let isOutside     = mqtt.isOutsideView
        let sendingAction = mqtt.sendingAction
        let specs         = Self.buttonSpecs(isOutsideView: isOutside)

        func buttonEl(_ i: Int) -> CPListImageRowItemRowElement {
            let s = specs[i]
            let indicator: String? = i >= 2 ? (isOutside ? "leaf" : "house") : nil
            return CPListImageRowItemRowElement(
                image: Self.buttonImage(symbol: s.symbol, label: s.title, prominent: s.prominent,
                                        dimmed: s.action == sendingAction, indicator: indicator),
                title: nil, subtitle: nil
            )
        }

        // Row 1: status panel + Pedestrian + Full Open
        let row1 = CPListImageRowItem(text: nil, elements: [
            CPListImageRowItemRowElement(
                image: Self.statusImage(online: mqtt.gateOnline, sendingAction: sendingAction,
                                        lastResult: mqtt.lastCommandResult, specs: specs),
                title: nil, subtitle: nil),
            buttonEl(0),
            buttonEl(1),
        ], allowsMultipleLines: false)
        row1.listImageRowHandler = { [weak self] _, col, completion in
            switch col {
            case 1: self?.mqtt?.sendCommand(specs[0].action)
            case 2: self?.mqtt?.sendCommand(specs[1].action)
            default: break
            }
            completion()
        }

        // Row 2: perspective toggle + Left + Right
        let row2 = CPListImageRowItem(text: nil, elements: [
            CPListImageRowItemRowElement(
                image: Self.toggleImage(isOutside: isOutside),
                title: nil, subtitle: nil),
            buttonEl(2),
            buttonEl(3),
        ], allowsMultipleLines: false)
        row2.listImageRowHandler = { [weak self] _, col, completion in
            switch col {
            case 0: self?.mqtt?.isOutsideView.toggle()
            case 1: self?.mqtt?.sendCommand(specs[2].action)
            case 2: self?.mqtt?.sendCommand(specs[3].action)
            default: break
            }
            completion()
        }

        return [CPListSection(items: [row1, row2])]
    }

    private func makeConnectingTemplate() -> CPListTemplate {
        let text: String
        if mqtt?.connectionState == .disconnected {
            text = "Please log in on your iPhone"
        } else {
            text = "Connecting to gate\u{2026}"
        }
        let item = CPListItem(text: text, detailText: nil)
        return CPListTemplate(title: "ProvGate", sections: [CPListSection(items: [item])])
    }

    // Directional actions resolve per perspective; Pedestrian/Full Open are always fixed.
    internal static func buttonSpecs(isOutsideView: Bool = true) -> [(title: String, symbol: String, action: String, prominent: Bool)] {
        [
            ("Pedestrian", "figure.walk",                        "pedestrian",                                                      false),
            ("Full Open",  "arrow.up.left.and.arrow.down.right", "full",                                                            true),
            ("Left",       "arrow.left",                         GateHelpers.resolvedAction("left",  isOutsideView: isOutsideView), false),
            ("Right",      "arrow.right",                        GateHelpers.resolvedAction("right", isOutsideView: isOutsideView), false),
        ]
    }

    // Blue (or gray when dimmed) rounded-rect with SF symbol + label — matches GateButton style.
    // Pass indicator ("leaf" or "house") to show a small perspective icon below the label.
    private static func buttonImage(symbol: String, label: String, prominent: Bool,
                                    dimmed: Bool = false, indicator: String? = nil) -> UIImage {
        let s = CPListImageRowItemRowElement.maximumImageSize
        let hasIndicator = indicator != nil
        let symbolH: CGFloat = s.height * (hasIndicator ? 0.50 : 0.58)
        let labelH:  CGFloat = s.height * (hasIndicator ? 0.28 : 0.42)
        let indicatorH: CGFloat = s.height - symbolH - labelH
        let renderer = UIGraphicsImageRenderer(size: s)
        return renderer.image { _ in
            (dimmed ? UIColor.systemGray : UIColor.systemBlue).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: s), cornerRadius: s.width * 0.22).fill()

            let pointSize = s.width * (prominent ? 0.38 : 0.32)
            let weight: UIImage.SymbolWeight = prominent ? .black : .semibold
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(
                    x: (s.width - glyph.size.width) / 2,
                    y: (symbolH - glyph.size.height) / 2
                ))
            }

            let font = UIFont.systemFont(ofSize: s.width * 0.18, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let str = label as NSString
            let textSize = str.size(withAttributes: attrs)
            str.draw(at: CGPoint(
                x: (s.width - textSize.width) / 2,
                y: symbolH + (labelH - textSize.height) / 2
            ), withAttributes: attrs)

            if let indicator {
                let iConfig = UIImage.SymbolConfiguration(pointSize: s.width * 0.16, weight: .medium)
                if let icon = UIImage(systemName: indicator, withConfiguration: iConfig)?
                    .withTintColor(.white.withAlphaComponent(0.8), renderingMode: .alwaysOriginal) {
                    icon.draw(at: CGPoint(
                        x: (s.width - icon.size.width) / 2,
                        y: symbolH + labelH + (indicatorH - icon.size.height) / 2
                    ))
                }
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    // Left-column info panel: in-flight command > last result > liveness.
    private static func statusImage(online: Bool?, sendingAction: String?,
                                    lastResult: MQTTManager.CommandResult?,
                                    specs: [(title: String, symbol: String, action: String, prominent: Bool)]) -> UIImage {
        let s = CPListImageRowItemRowElement.maximumImageSize
        let renderer = UIGraphicsImageRenderer(size: s)
        return renderer.image { _ in
            UIColor.systemGray5.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: s), cornerRadius: s.width * 0.22).fill()

            let heading: String
            let body: String
            let bodyColor: UIColor
            if let action = sendingAction {
                let title = specs.first(where: { $0.action == action })?.title ?? action
                heading   = "Sending"
                body      = title + "\u{2026}"
                bodyColor = .label
            } else if let result = lastResult {
                heading   = result.action.capitalized
                body      = result.success ? "Success" : "Failed"
                bodyColor = result.success ? .systemGreen : .systemRed
            } else {
                heading   = "Gate"
                switch online {
                case true:  body = "Online";  bodyColor = .label
                case false: body = "Offline"; bodyColor = .label
                case nil:   body = "Ready";   bodyColor = .label
                }
            }

            let headingFont = UIFont.systemFont(ofSize: s.width * 0.14, weight: .semibold)
            let bodyFont    = UIFont.systemFont(ofSize: s.width * 0.18, weight: .bold)
            let headingAttrs: [NSAttributedString.Key: Any] = [.font: headingFont, .foregroundColor: UIColor.secondaryLabel]
            let bodyAttrs:    [NSAttributedString.Key: Any] = [.font: bodyFont,    .foregroundColor: bodyColor]

            let h1 = (heading as NSString).size(withAttributes: headingAttrs)
            let h2 = (body    as NSString).size(withAttributes: bodyAttrs)
            let totalH = h1.height + 3 + h2.height
            let startY = (s.height - totalH) / 2

            (heading as NSString).draw(at: CGPoint(x: (s.width - h1.width) / 2, y: startY),
                                       withAttributes: headingAttrs)
            (body    as NSString).draw(at: CGPoint(x: (s.width - h2.width) / 2, y: startY + h1.height + 3),
                                       withAttributes: bodyAttrs)
        }.withRenderingMode(.alwaysOriginal)
    }

    // Left-column toggle panel: shows current perspective; tap to switch.
    private static func toggleImage(isOutside: Bool) -> UIImage {
        let s = CPListImageRowItemRowElement.maximumImageSize
        let symbolH = s.height * 0.54
        let labelH  = s.height - symbolH
        let tint: UIColor = isOutside ? .systemGreen : .systemBlue
        let renderer = UIGraphicsImageRenderer(size: s)
        return renderer.image { _ in
            UIColor.systemGray5.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: s), cornerRadius: s.width * 0.22).fill()

            let iconName = isOutside ? "leaf.fill" : "house.fill"
            let label    = isOutside ? "Outside"   : "Inside"
            let config = UIImage.SymbolConfiguration(pointSize: s.width * 0.30, weight: .semibold)
            if let glyph = UIImage(systemName: iconName, withConfiguration: config)?
                .withTintColor(tint, renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(
                    x: (s.width - glyph.size.width) / 2,
                    y: (symbolH - glyph.size.height) / 2
                ))
            }

            let font = UIFont.systemFont(ofSize: s.width * 0.17, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: tint]
            let str = label as NSString
            let textSize = str.size(withAttributes: attrs)
            str.draw(at: CGPoint(
                x: (s.width - textSize.width) / 2,
                y: symbolH + (labelH - textSize.height) / 2
            ), withAttributes: attrs)
        }.withRenderingMode(.alwaysOriginal)
    }

    private func observe() {
        guard let mqtt else { return }
        let version = observationVersion
        withObservationTracking {
            _ = mqtt.connectionState
            _ = mqtt.sendingAction
            _ = mqtt.gateOnline
            _ = mqtt.lastCommandResult
            _ = mqtt.isOutsideView
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationVersion == version else { return }
                self.refreshTemplate()
                self.observe()
            }
        }
    }
}
