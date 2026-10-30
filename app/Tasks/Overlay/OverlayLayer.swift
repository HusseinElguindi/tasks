import SwiftUI
import TasksCore

/// The window-level layer above the panes (§18.8–9): the date popover with its press catcher, and the tooltip. The
/// notice lives in the list pane's corner (`NoticeView`), so it rides the pane's edge.
struct OverlayLayer: View {
    let store: Store
    @Bindable var window: WindowState
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let picker = window.overlays.picker {
                // A press outside closes the popover and does nothing else (it never reaches what's under it).
                PressCatcher { WindowActions(store: store, window: window).closePicker() }
                DatePopoverHost(store: store, window: window, picker: picker, windowSize: size)
            }
            TooltipView(overlays: window.overlays)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        #if DEBUG
        .onAppear { DebugPicker.runIfRequested(store, window) }
        #endif
    }
}

extension WindowActions {
    /// Esc or a press outside: closes the popover; the keys go back to the window and the focused pane stays (§11).
    func closePicker() {
        overlays.picker = nil
        focus(window.focus)
    }
}

/// A full-window view that swallows the mouse-down (so a press outside a popover doesn't also select a row).
struct PressCatcher: NSViewRepresentable {
    let onPress: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onPress = onPress
        return v
    }

    func updateNSView(_ nsView: CatcherView, context: Context) { nsView.onPress = onPress }

    final class CatcherView: NSView {
        var onPress: (() -> Void)?
        override func mouseDown(with event: NSEvent) { onPress?() }
        override func rightMouseDown(with event: NSEvent) { onPress?() }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

// MARK: - Tooltip (css:349–350): `surface-popover`, `shadow-popover`, radius 6, padding 4 / 7, 11/14; keys 6 after
// the name in `ink-secondary`; in over 100 ms ease-out, out at once.

struct TooltipView: View {
    let overlays: Overlays
    @Environment(\.tk) private var tk

    var body: some View {
        if let tip = overlays.tip {
            HStack(spacing: 6) {
                Text(tip.text).foregroundStyle(tk.ink.swiftUI)
                if !tip.keys.isEmpty { Text(tip.keys).foregroundStyle(tk.ink2.swiftUI) }
            }
            .font(Font(TK.Font.tooltip))
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .popoverSurface(radius: 6)
            .offset(x: tip.origin.x, y: tip.origin.y)
            .transition(.asymmetric(insertion: .opacity.animation(TK.Motion.tooltipIn), removal: .identity))
            .allowsHitTesting(false)
            .id(tip.text + tip.keys + "\(tip.origin)")
        }
    }
}

extension View {
    /// `surface-popover` with `shadow-popover`: a 0.5pt ring plus `0 12 32` (css:57, 74).
    func popoverSurface(radius: CGFloat) -> some View { modifier(PopoverSurface(radius: radius)) }
}

private struct PopoverSurface: ViewModifier {
    let radius: CGFloat
    @Environment(\.tk) private var tk

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        // The surface alone casts the shadow (its children mustn't).
        content
            .background(shape.fill(tk.popover.swiftUI).shadow(color: tk.popoverShadow.swiftUI, radius: 16, x: 0, y: 12))
            .overlay(shape.stroke(tk.popoverRing.swiftUI, lineWidth: 0.5).padding(-0.25))
    }
}

// MARK: - Notice (§9, css:344–347)

/// 34 tall, `surface-popover`, `shadow-popover`, radius 10, padding 12 / 5, 10 between the text and the Undo capsule.
/// In: 220 ms rising 8; out: 160 ms ease-in sinking 4. A new notice replaces the text in place.
struct NoticeView: View {
    let overlays: Overlays
    let actions: WindowActions
    @Environment(\.tk) private var tk
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let n = overlays.notice {
                HStack(spacing: 10) {
                    Text(n.text).foregroundStyle(tk.ink.swiftUI).lineLimit(1).fixedSize()
                    if n.undo {
                        CapsuleButton(tinted: true) {
                            overlays.hideNotice()
                            actions.performUndo()
                        } label: {
                            HStack(spacing: 6) {
                                Text("Undo")
                                Text("⌘Z").font(Font(TK.Font.small)).foregroundStyle(tk.ink3.swiftUI)
                            }
                        }
                    }
                }
                .font(Font(TK.Font.body))
                .padding(.leading, 12)
                .padding(.trailing, n.undo ? 5 : 12)
                .frame(height: 34)
                .popoverSurface(radius: 10)
                .opacity(shown && !n.leaving ? 1 : 0)
                .offset(y: !shown ? 8 : n.leaving ? 4 : 0)
                .animation(n.leaving ? TK.Motion.noticeOut : TK.Motion.noticeIn, value: n.leaving)
                .animation(TK.Motion.noticeIn, value: shown)
                .onHover { overlays.noticeHover($0) }
                .onAppear { shown = true }
                .onDisappear { shown = false }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                .id(n.id)
            }
        }
    }
}

/// Pane's capsule button (css:291–296): 24 tall, padding 12, radius 12, gap 6; hover brightness 1.12 / 0.97 on
/// `icon`, press 0.86 at once. Tinted: `accent-tint` with `accent-text`.
struct CapsuleButton<Label: View>: View {
    var tinted = false
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(CapsuleStyle(tinted: tinted, hovered: hovered))
            .onHover { hovered = $0 }
    }
}

private struct CapsuleStyle: ButtonStyle {
    let tinted: Bool
    let hovered: Bool
    @Environment(\.tk) private var tk

    func makeBody(configuration: Configuration) -> some View {
        let b = configuration.isPressed ? TK.Palette.pressBrightness : hovered ? tk.buttonHoverBrightness : 1
        let bg = (tinted ? tk.accentTint : tk.fillTrack).brightness(b)
        let fg = (tinted ? tk.accentText : tk.ink).brightness(b)
        configuration.label
            .font(Font(TK.Font.body))
            .foregroundStyle(fg.swiftUI)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(bg.swiftUI, in: Capsule(style: .circular))
            .contentShape(Capsule(style: .circular))
            .animation(configuration.isPressed ? nil : TK.Motion.icon, value: hovered)
            .animation(configuration.isPressed ? nil : TK.Motion.icon, value: configuration.isPressed)
    }
}
