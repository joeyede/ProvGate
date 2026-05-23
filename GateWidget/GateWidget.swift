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

// MARK: - All-buttons (2×2 grid, inside view)

private struct GateGridButton<I: AppIntent>: View {
    let systemImage: String
    let label: String
    let intent: I

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct GateControlWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                GateGridButton(systemImage: "figure.walk",                        label: "Pedestrian", intent: PedestrianIntent())
                GateGridButton(systemImage: "arrow.up.left.and.arrow.down.right", label: "Full Open",  intent: OpenGateIntent())
            }
            HStack(spacing: 8) {
                GateGridButton(systemImage: "arrow.left",  label: "Left",  intent: OpenInsideLeftIntent())
                GateGridButton(systemImage: "arrow.right", label: "Right", intent: OpenInsideRightIntent())
            }
        }
        .padding(10)
        .containerBackground(Color(.systemBackground), for: .widget)
    }
}

struct GateControlWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GateControlWidget", provider: GateProvider()) { _ in
            GateControlWidgetView()
        }
        .configurationDisplayName("Gate Control")
        .description("All four gate buttons — inside view.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Entry point

@main
struct GateWidgetBundle: WidgetBundle {
    var body: some Widget {
        GateControlWidget()
        FullOpenWidget()
        PedestrianWidget()
    }
}
