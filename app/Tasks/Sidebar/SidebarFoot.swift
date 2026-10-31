import AppKit
import SwiftUI

// The sidebar's foot (INTERACTIONS-v2 §27, direction A; design/prototype-v2/Foot.dc.html with foot.css): 36pt pinned
// under the sidebar's scroll view, no fill of its own and no divider. "+ New List" at the left, Settings at the right.

/// Which control the pointer is over or pressing (observable, so the debug steps can set hover too).
@MainActor
@Observable
final class FootState {
    enum Item { case newList, settings }
    var hovered: Item?
}

/// Takes the first click, as the sidebar's rows do.
final class FootHost: NSHostingView<SidebarFoot> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct SidebarFoot: View {
    static let height: CGFloat = 36

    let state: FootState
    let palette: TK.Palette
    let onNewList: () -> Void
    let onSettings: () -> Void
    /// Shows the tooltip for an item at its frame in this view (top-left origin), or hides it (nil).
    let tip: (FootState.Item?, CGRect) -> Void

    var body: some View {
        HStack(spacing: 2) {
            // + New List (css .fnew): 26 tall, padding 7 / 8, radius 6, a 14pt + and 12pt "New List" 6 apart.
            FootButton(item: .newList, state: state, rest: \.inkTertiary, action: onNewList, tip: tip) { color in
                HStack(spacing: 6) {
                    GlyphView(glyph: .plus, size: 14, color: color)
                    Text("New List").font(.system(size: 12)).foregroundStyle(color).lineLimit(1).fixedSize()
                }
                .padding(.leading, 7)
                .padding(.trailing, 8)
                .frame(height: 26)
            }
            .accessibilityLabel("New List")
            Spacer(minLength: 0)
            // Settings (css .fb): 26 × 26, radius 6, `slider.horizontal.3` at 14pt in `ink-quiet`.
            FootButton(item: .settings, state: state, rest: \.inkQuiet, action: onSettings, tip: tip) { color in
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.leading, 10)
        .padding(.trailing, 11)
        .frame(height: Self.height)
        .coordinateSpace(name: "foot")
        .environment(\.tk, palette)
    }
}

/// Rest in its colour on nothing; hover `ink` on the `hover` fill, both on `icon` (100 ms); press the `press` fill at
/// once. A real button for VoiceOver; Tab doesn't stop on it (§27 Keys).
private struct FootButton<Label: View>: View {
    let item: FootState.Item
    let state: FootState
    let rest: KeyPath<TK.Palette, NSColor>
    let action: () -> Void
    let tip: (FootState.Item?, CGRect) -> Void
    @ViewBuilder let label: (Color) -> Label
    @Environment(\.tk) private var tk
    @State private var frame: CGRect = .zero

    var body: some View {
        let hovered = state.hovered == item
        Button {
            tip(nil, .zero)
            action()
        } label: {
            label((hovered ? tk.ink : tk[keyPath: rest]).swiftUI)
                .animation(TK.Motion.icon, value: hovered)
        }
        .buttonStyle(FootButtonStyle(hovered: hovered))
        .focusable(false)
        .modifier(FootFirstMouse())
        .background(GeometryReader { g in
            Color.clear
                .onAppear { frame = g.frame(in: .named("foot")) }
                .onChange(of: g.frame(in: .named("foot"))) { _, f in frame = f }
        })
        .onHover { inside in
            if inside { state.hovered = item } else if state.hovered == item { state.hovered = nil }
            tip(inside ? item : nil, frame)
        }
    }
}

private struct FootButtonStyle: ButtonStyle {
    let hovered: Bool
    @Environment(\.tk) private var tk

    func makeBody(configuration: Configuration) -> some View {
        let fill: NSColor = configuration.isPressed ? tk.press : hovered ? tk.hover : .clear
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 6, style: .circular)
                    .fill(fill.swiftUI)
                    .animation(configuration.isPressed ? nil : TK.Motion.icon, value: hovered)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .circular))
    }
}

private struct FootFirstMouse: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.allowsWindowActivationEvents(true) } else { content }
    }
}
