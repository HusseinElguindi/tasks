// Pane components new in Tasks (design/DIRECTIONS.md, "New Pane components and tokens"). Every color comes from
// the theme through PaneColors; nothing here hard-codes a value the theme derives.

import SwiftUI

// MARK: - Checkbox

/// 16pt circle. Ring in line-field; done is an accent fill with an on-accent 2.2pt check. The placeholder ring marks
/// the quick-add editor row.
struct PaneCheckbox: View {
    enum Style { case normal, placeholder }
    var isDone: Bool
    var style: Style = .normal
    @Environment(\.pane) private var pane

    var body: some View {
        ZStack {
            if isDone {
                Circle().fill(pane.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(pane.onAccent)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                Circle().strokeBorder(style == .placeholder ? pane.inkQuiet : pane.fieldEdge, lineWidth: 1.5)
                    .opacity(style == .placeholder ? 0.6 : 1)
            }
        }
        .frame(width: PaneSize.check, height: PaneSize.check)
        .animation(PaneMotion.snappy, value: isDone)
    }
}

// MARK: - Date chip

/// Capsule, 18pt (22pt in editors), with an optional 11pt calendar or flag icon.
struct PaneChip: View {
    enum Kind { case neutral, due, late, accent, ghost }
    var text: String
    var systemImage: String? = nil
    var kind: Kind = .neutral
    var large = false
    @Environment(\.pane) private var pane

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: large ? 11 : 10, weight: .medium))
            }
            Text(text)
                .font(.system(size: large ? 12 : 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, large ? 9 : 7)
        .frame(height: large ? PaneSize.chipLarge : PaneSize.chip)
        .background(background, in: Capsule())
        .overlay {
            if kind == .ghost { Capsule().strokeBorder(pane.separator, lineWidth: 1) }
        }
        .fixedSize()
    }

    private var foreground: Color {
        switch kind {
        case .neutral, .ghost: pane.inkSecondary
        case .due: pane.attention
        case .late: pane.dangerText
        case .accent: pane.accentText
        }
    }

    private var background: Color {
        switch kind {
        case .neutral: pane.control
        case .due: pane.attentionTint
        case .late: pane.dangerTint
        case .accent: pane.accentTint
        case .ghost: .clear
        }
    }
}

// MARK: - List mark

/// A list's program tile: fill-strong with the capsule hairline, a monogram in the list's ANSI color. Rex's tiles
/// are 5:4, 20 × 16 in the sidebar; `size` is the width: 20 in the sidebar, 16 in pane headers and menus, 12 in chips.
struct PaneListMark: View {
    var monogram: String
    var color: Color
    var size: CGFloat = PaneSize.tile
    var systemImage: String? = nil
    @Environment(\.pane) private var pane

    var body: some View {
        let height = (size * 0.8).rounded()
        let shape = RoundedRectangle(cornerRadius: height * 0.25, style: .continuous)
        ZStack {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: size * 0.55, weight: .semibold))
            } else {
                Text(monogram).font(PaneFont.mono(size * 0.5, weight: .bold))
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: height)
        .background(pane.strong, in: shape)
        .paneShadow(.capsule, in: shape)
        .accessibilityHidden(true)
    }
}

// MARK: - Insertion line

/// A 2pt accent line with an 8pt ring (filled with surface-base) at its leading end.
struct PaneInsertionLine: View {
    @Environment(\.pane) private var pane

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .strokeBorder(pane.accent, lineWidth: 2)
                .background(Circle().fill(pane.base))
                .frame(width: 8, height: 8)
            Rectangle().fill(pane.accent).frame(height: 2)
        }
        .frame(height: 8)
        .allowsHitTesting(false)
    }
}

// MARK: - Popover surface

/// 12pt radius, 6pt padding: surface-card in dark, surface-base in light, with shadow-popover.
struct PanePopoverSurface<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.pane) private var pane

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PaneRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(6)
            .background(pane.isDark ? pane.card : pane.base, in: shape)
            .paneShadow(.popover, in: shape)
    }
}

/// A 26pt menu item; the hot item is accent with on-accent text.
struct PaneMenuItem<Label: View>: View {
    var isHot: Bool
    var shortcut: String? = nil
    var action: () -> Void
    @ViewBuilder var label: Label
    @Environment(\.pane) private var pane
    @Environment(\.paneForcedState) private var forced
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label
                Spacer(minLength: 16)
                if let shortcut {
                    Text(shortcut).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hot ? pane.onAccent : pane.inkSecondary)
                }
            }
            .font(PaneFont.body)
            .foregroundStyle(hot ? pane.onAccent : pane.ink)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(hot ? pane.accent : .clear, in: RoundedRectangle(cornerRadius: PaneRadius.field, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var hot: Bool { isHot || (forced?.hovered ?? hovering) }
}

struct PaneMenuSeparator: View {
    @Environment(\.pane) private var pane
    var body: some View {
        Rectangle().fill(pane.separator).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
    }
}

// MARK: - Key hint

/// `kbd` style: 11/14 medium in ink-secondary.
struct PaneKeyHint: View {
    var text: String
    @Environment(\.pane) private var pane
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(pane.inkSecondary)
    }
}

// MARK: - Labels

/// Rex's group label: 11 semibold in ink-tertiary.
struct PaneGroupLabel: View {
    var text: String
    @Environment(\.pane) private var pane
    var body: some View {
        Text(text).font(PaneFont.label).foregroundStyle(pane.inkTertiary).lineLimit(1)
    }
}

/// A group label that reveals ⊕ on hover, as Rex's group headers do: the ⊕ sits in the rows' trailing-action slot,
/// in ink-tertiary like the label. The caller owns the hover (a PaneHoverRegion) and the leading inset.
struct PaneGroupLabelRow: View {
    var text: String
    var help: String
    var isHovered: Bool
    var action: () -> Void
    var labelOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            PaneGroupLabel(text: text).offset(y: labelOffset)
            Spacer(minLength: 0)
            PaneIconButton("plus.circle", help: help, action: action)
                .environment(\.paneGhostLevel, .label)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
        }
        .padding(.trailing, PaneSize.rowActionInset)
        .contentShape(Rectangle())
    }
}

// MARK: - Markdown notes

/// Notes render inline-only Markdown (spec §2): bold, italic, code, links, line breaks kept. Links in accent-text
/// with an underline; inline code in mono 12 on fill-control.
struct PaneMarkdownText: View {
    var source: String
    @Environment(\.pane) private var pane

    var body: some View {
        Text(rendered)
            .font(PaneFont.body)
            .lineSpacing(3)
            .foregroundStyle(pane.ink)
            .tint(pane.accentText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rendered: AttributedString {
        guard var s = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(source)
        }
        for run in s.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                s[run.range].font = PaneFont.mono(12)
                s[run.range].backgroundColor = pane.control
            }
            if run.link != nil {
                s[run.range].foregroundColor = pane.accentText
                s[run.range].underlineStyle = .single
            }
        }
        return s
    }
}

// MARK: - Segmented control (A3's notes Edit / Preview)

struct PaneSegmented<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value
    @Environment(\.pane) private var pane
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    selection = value
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selection == value ? pane.ink : pane.inkSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 20)
                        .background {
                            if selection == value {
                                Capsule().fill(pane.isDark ? pane.thumb : pane.base)
                                    .shadow(color: .black.opacity(pane.isDark ? 0.4 : 0.14), radius: 1, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(pane.track, in: Capsule())
        .animation(PaneMotion.snappy, value: selection)
    }
}

// MARK: - Interaction states (design/INTERACTIONS.md)

/// Debug-only: forces a hover or press look so the state gallery can render every state without a pointer.
struct PaneForcedState: Equatable, Sendable {
    var hovered = false
    var pressed = false
}

private struct PaneForcedStateKey: EnvironmentKey { static let defaultValue: PaneForcedState? = nil }

extension EnvironmentValues {
    var paneForcedState: PaneForcedState? {
        get { self[PaneForcedStateKey.self] }
        set { self[PaneForcedStateKey.self] = newValue }
    }
}

/// Rex's measured timings (design/REX-REFERENCE.md, design/INTERACTIONS.md).
extension PaneMotion {
    /// A row's hover appearing: near-instant, about 80% on the first frame and settled within 60 ms, as Rex.
    static var hoverIn: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: 0.06) }
    /// A row's hover fading, from the moment the pointer leaves (Rex holds nothing).
    static var hoverOut: Animation { .easeOut(duration: 0.085) }
    /// Icon-button hover and press release, both ways.
    static var icon: Animation { .easeOut(duration: 0.1) }
    /// The focused pane coming forward.
    static var focus: Animation { .easeOut(duration: 0.06) }
    /// Sidebar collapse and expand: decelerating.
    static var sidebar: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: 0.3) }
}

/// Capsule buttons, chips and checkboxes: pressed darkens the whole control to 86% (Pane's `brightness(0.86)`),
/// instantly, and eases back over `duration-hover`. No hover state.
struct PanePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }

    private struct PressBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.paneForcedState) private var forced

        var body: some View {
            let pressed = forced?.pressed ?? configuration.isPressed
            configuration.label
                .colorMultiply(pressed ? Color(white: 0.86) : .white)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(configuration.isPressed ? nil : PaneMotion.icon, value: configuration.isPressed)
                .contentShape(Rectangle())
        }
    }
}

/// Which icon button, as Rex draws them: pane-header actions (quiet glyph, rounded-square hover), toolbar actions
/// beside the traffic lights (secondary glyph, circular hover), a row's revealed action (secondary glyph, like the
/// row's resting title) and a group label's (tertiary, like the label). Revealed actions hover with a translucent
/// rounded square, so they read on the ground, a selected row and the current capsule alike.
enum PaneGhostLevel: Sendable { case quiet, secondary, row, label }

private struct PaneGhostLevelKey: EnvironmentKey { static let defaultValue = PaneGhostLevel.quiet }

extension EnvironmentValues {
    var paneGhostLevel: PaneGhostLevel {
        get { self[PaneGhostLevelKey.self] }
        set { self[PaneGhostLevelKey.self] = newValue }
    }
}

/// Icon-only buttons, as in Rex: on hover a small fill appears behind the glyph (a rounded square in pane headers, a
/// circle in the toolbar) and the glyph goes one step stronger; pressed fills one step more. `icon` (100 ms) both ways.
struct PaneGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostBody(configuration: configuration)
    }

    private struct GhostBody: View {
        let configuration: Configuration
        @Environment(\.pane) private var pane
        @Environment(\.paneGhostLevel) private var level
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.paneForcedState) private var forced
        @State private var hovering = false

        var body: some View {
            let (rest, hover): (Color, Color) = switch level {
            case .quiet: (pane.inkQuiet, pane.inkSecondary)
            case .secondary, .row: (pane.inkSecondary, pane.ink)
            case .label: (pane.inkTertiary, pane.inkSecondary)
            }
            let pressed = forced?.pressed ?? configuration.isPressed
            let hovered = (forced?.hovered ?? hovering) && isEnabled
            configuration.label
                .foregroundStyle(pressed ? pane.ink : (hovered ? hover : rest))
                .background {
                    switch level {
                    case .quiet:
                        RoundedRectangle(cornerRadius: PaneRadius.field, style: .continuous)
                            .fill(pressed ? pane.control : pane.selected).opacity(hovered || pressed ? 1 : 0)
                    case .secondary:
                        Circle().fill(pressed ? pane.control : pane.track).frame(width: 26, height: 26)
                            .opacity(hovered || pressed ? 1 : 0)
                    case .row, .label:
                        RoundedRectangle(cornerRadius: PaneRadius.field, style: .continuous)
                            .fill(pane.isDark ? Color.white.opacity(pressed ? 0.12 : 0.07) : Color.black.opacity(pressed ? 0.09 : 0.05))
                            .opacity(hovered || pressed ? 1 : 0)
                    }
                }
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { h in
                    withAnimation(PaneMotion.icon) { hovering = h }
                }
        }
    }
}

/// Sidebar rows (Rex's session tabs): the current row is `fill-strong` with the capsule edge; pressing another row
/// gives it one step of fill until the selection moves. A drop target fills `accent-tint` with a focus-ring edge.
/// No hover.
struct PaneSidebarRowStyle: ButtonStyle {
    var isCurrent: Bool
    var isDropTarget: Bool

    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration, isCurrent: isCurrent, isDropTarget: isDropTarget)
    }

    private struct RowBody: View {
        let configuration: Configuration
        let isCurrent: Bool
        let isDropTarget: Bool
        @Environment(\.pane) private var pane
        @Environment(\.paneForcedState) private var forced

        var body: some View {
            configuration.label
                .background {
                    if isDropTarget {
                        Capsule().fill(pane.accentTint)
                            .overlay { Capsule().strokeBorder(pane.focusRing, lineWidth: 2) }
                    } else if isCurrent {
                        Capsule().fill(pane.strong).paneShadow(.capsule, in: Capsule())
                    } else if forced?.pressed ?? configuration.isPressed {
                        Capsule().fill(pane.selected)
                    }
                }
                .animation(isDropTarget ? PaneMotion.hoverIn : nil, value: isDropTarget)
                .contentShape(Capsule())
        }
    }
}

extension View {
    /// Reduce Motion turns every animation off (Pane: "Respect Reduce Motion as Off").
    func paneRespectsReduceMotion() -> some View { modifier(ReduceMotionOff()) }
}

private struct ReduceMotionOff: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction { t in
            if reduceMotion {
                t.animation = nil
                t.disablesAnimations = true
            }
        }
    }
}

/// A row's trailing •••: a menu in the `rowAction` slot the layout always reserves, revealed while the row is hovered
/// or selected, as Rex reveals a session row's action (in with `hoverIn`, out with `hoverOut`). Never shifts the row.
/// Rows place it `rowActionInset` from their trailing edge.
struct PaneRowMenu<Items: View>: View {
    var visible: Bool
    var help: String
    @ViewBuilder var items: Items

    var body: some View {
        Menu { items } label: {
            PaneDots()
                .frame(width: PaneSize.rowAction, height: PaneSize.rowAction)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(PaneGhostButtonStyle())
        .environment(\.paneGhostLevel, .row)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(visible ? PaneMotion.hoverIn : PaneMotion.hoverOut, value: visible)
        .accessibilityHidden(!visible)
    }
}

/// Rex's •••: three 3.75pt dots on a 5.5pt pitch, in the foreground style.
struct PaneDots: View {
    var body: some View {
        HStack(spacing: 1.75) {
            Circle().frame(width: 3.75, height: 3.75)
            Circle().frame(width: 3.75, height: 3.75)
            Circle().frame(width: 3.75, height: 3.75)
        }
    }
}

/// Hover for a region of rows (a pane's rows, the sidebar), with Rex's timing: entering an item hovers it at once
/// (`hoverIn`) and leaving fades it at once (`hoverOut`); nothing lingers. The region holds one hovered key, so a
/// missed exit can never leave two items hovered; leaving the region, the item disappearing and a drag starting all
/// clear it. Each item reads its own flag, so moving the pointer redraws the two rows involved, not every row.
@MainActor
final class PaneHoverRegion<Key: Hashable> {
    private var flags: [Key: PaneHoverFlag] = [:]
    private var current: Key?

    /// Read in a body: that view, and only it, follows the item's hover.
    func isHovered(_ key: Key) -> Bool { flag(key).isOn }

    /// For `onHover`.
    func update(_ key: Key, inside: Bool) {
        #if DEBUG
        PaneHoverDebug.log?("hover \(inside ? "enter" : "exit") \(key) current=\(String(describing: current))")
        #endif
        if inside {
            guard current != key else { return }
            clear()
            current = key
            withAnimation(PaneMotion.hoverIn) { flag(key).isOn = true }
        } else if current == key {
            clear()
        }
    }

    func clear(_ reason: String = "") {
        guard let old = current else { return }
        #if DEBUG
        PaneHoverDebug.log?("hover clear \(old) \(reason)")
        #endif
        current = nil
        withAnimation(PaneMotion.hoverOut) { flags[old]?.isOn = false }
    }

    /// The item left the screen (scrolled away, deleted, another list opened): it can't stay hovered.
    func vanished(_ key: Key) {
        #if DEBUG
        if current == key { PaneHoverDebug.log?("hover vanished \(key)") }
        #endif
        if current == key { clear() }
    }

    private func flag(_ key: Key) -> PaneHoverFlag {
        if let f = flags[key] { return f }
        let f = PaneHoverFlag()
        flags[key] = f
        return f
    }
}

@MainActor
@Observable
final class PaneHoverFlag {
    var isOn = false
}

#if DEBUG
/// Set by `-debugKeyLog`: hover events go to the same log.
@MainActor
enum PaneHoverDebug {
    static var log: ((String) -> Void)?
}
#endif

/// One line of text that fades out under a gradient at the trailing edge instead of ending in "…", as Rex does
/// before a row's trailing action.
struct PaneFadingText: View {
    var text: String

    var body: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 18)
                }
            }
    }
}
