import SwiftUI
import WidgetKit

/// The Today widget (WIDGETS.md §1.1, MVP 1): small, medium and large, read-only for now. Its rows open the task, its
/// + a new task in Today, and the rest of it Today.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetGroup.Kind.today, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("What’s planned and due today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // The views keep the mock-ups' own margins (14 above, 16 at the sides, 12 below).
        .contentMarginsDisabled()
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = WidgetPalette.of(scheme)
        Group {
            switch entry.content {
            case .setUp:
                SetUpView()
            case let .today(s):
                switch family {
                case .systemSmall: TodaySmallView(s: s)
                case .systemLarge: TodayLargeView(s: s)
                default: TodayMediumView(s: s)
                }
            }
        }
        .environment(\.widgetPalette, p)
        .widgetURL(DeepLink.today.url)
        .containerBackground(p.base, for: .widget)
    }
}

// MARK: - Environment

private struct WidgetPaletteKey: EnvironmentKey {
    static let defaultValue = WidgetPalette.dark
}

extension EnvironmentValues {
    var widgetPalette: WidgetPalette {
        get { self[WidgetPaletteKey.self] }
        set { self[WidgetPaletteKey.self] = newValue }
    }
}
