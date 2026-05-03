import SwiftUI

#Preview {
    GateControlView()
        .environment(MQTTManager())
}

struct GateControlView: View {
    @Environment(MQTTManager.self) private var mqtt

    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER ---
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 10, height: 10)
                    Text(mqtt.statusMessage.isEmpty ? " " : capitalized(mqtt.statusMessage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: { mqtt.disconnect() }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)

            // --- TITLE ---
            VStack(spacing: 4) {
                Text("Gate Control")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text("v\(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)

            // --- THE CONTROL GRID ---
            VStack(spacing: 12) { // Spacing between the top row and the gray box
                
                // 1. TOP ROW
                // Wrapped in a VStack with 16pt padding to match the gray box's "squeeze"
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        GateButton(
                            systemImage: "figure.walk",
                            label: "Pedestrian",
                            action: "pedestrian",
                            mqtt: mqtt
                        )
                        GateButton(
                            systemImage: "arrow.up.left.and.arrow.down.right",
                            label: "Full Open",
                            action: "full",
                            mqtt: mqtt
                        )
                    }
                }
                .padding(.horizontal, 16) // Matches the gray box internal padding
                .padding(.top, 8)          // Balance the visual weight

                // 2. BOTTOM GROUP (Gray Box)
                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        GateButton(
                            systemImage: "arrow.left",
                            label: "Left",
                            action: "left",
                            indicator: mqtt.isInsideView ? "house" : "leaf",
                            mqtt: mqtt
                        )
                        GateButton(
                            systemImage: "arrow.right",
                            label: "Right",
                            action: "right",
                            indicator: mqtt.isInsideView ? "house" : "leaf",
                            mqtt: mqtt
                        )
                    }

                    // Inside / Outside toggle
                    HStack(spacing: 12) {
                        Image(systemName: "house")
                            .foregroundStyle(mqtt.isInsideView ? Color.accentColor : .secondary)
                        Text("Inside")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(mqtt.isInsideView ? Color.accentColor : .secondary)

                        Toggle("", isOn: Binding(
                            get: { !mqtt.isInsideView },
                            set: { mqtt.isInsideView = !$0 }
                        ))
                        .tint(Color.accentColor)
                        .labelsHidden()

                        Text("Outside")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(!mqtt.isInsideView ? Color.accentColor : .secondary)
                        Image(systemName: "leaf")
                            .foregroundStyle(!mqtt.isInsideView ? Color.accentColor : .secondary)
                    }
                }
                .padding(16) // The gray margin
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
            }
            .padding(.horizontal, 20) // Outer screen padding
            .frame(maxWidth: 600)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .overlay {
            if mqtt.loadingAction != nil {
                ZStack {
                    Color(.systemBackground).opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
    }

    private var statusDotColor: Color {
        switch mqtt.connectionState {
        case .connected:  .green
        case .connecting: .yellow
        default:          .red
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}

// --- BUTTON COMPONENT ---
private struct GateButton: View {
    let systemImage: String
    let label: String
    let action: String
    var indicator: String? = nil
    let mqtt: MQTTManager

    private var isLoading: Bool { mqtt.loadingAction == action }
    private var isDisabled: Bool { mqtt.loadingAction != nil }

    var body: some View {
        Button { mqtt.sendCommand(action) } label: {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                if let indicator {
                    Image(systemName: indicator)
                        .font(.caption2)
                        .opacity(0.8)
                } else {
                    // Hidden spacer to keep height identical if no house/leaf icon
                    Image(systemName: "house")
                        .font(.caption2)
                        .opacity(0)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity) // Fill available width
            .padding(.vertical, 12)     // Internal button padding
            .background(isLoading ? Color.gray : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isLoading ? 0.7 : 1.0)
        }
        .disabled(isDisabled)
        .aspectRatio(1, contentMode: .fit) // Force the square shape
    }
}
