import SwiftUI
import WidgetKit
import AppIntents

// Action-only widgets have no live data — a single static entry is enough.
private struct GateEntry: TimelineEntry { let date: Date }

private struct GateProvider: TimelineProvider {
    func placeholder(in context: Context) -> GateEntry { .init(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (GateEntry) -> Void) {
        completion(.init(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GateEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now)], policy: .never))
    }
}

// MARK: - Shared button layout

private struct GateWidgetButton<I: AppIntent>: View {
    let systemImage: String
    let label: String
    let intent: I

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .medium))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .containerBackground(Color.accentColor, for: .widget)
    }
}

// MARK: - Full Open widget

struct FullOpenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FullOpenWidget", provider: GateProvider()) { _ in
            GateWidgetButton(
                systemImage: "arrow.up.left.and.arrow.down.right",
                label: "Full Open",
                intent: OpenGateIntent()
            )
        }
        .configurationDisplayName("Full Open")
        .description("Fully opens the gate.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Pedestrian widget

struct PedestrianWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PedestrianWidget", provider: GateProvider()) { _ in
            GateWidgetButton(
                systemImage: "figure.walk",
                label: "Pedestrian",
                intent: PedestrianIntent()
            )
        }
        .configurationDisplayName("Pedestrian")
        .description("Opens the pedestrian gate.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Entry point

@main
struct GateWidgetBundle: WidgetBundle {
    var body: some Widget {
        FullOpenWidget()
        PedestrianWidget()
    }
}
