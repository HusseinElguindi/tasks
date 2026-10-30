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

/// Pane's program tile for a list: fill-strong with the capsule hairline, a monogram in the list's ANSI color.
/// 20pt in the sidebar, 16pt in pane headers, 12–14pt in chips and menus.
struct PaneListMark: View {
    var monogram: String
    var color: Color
    var size: CGFloat = PaneSize.tile
    var systemImage: String? = nil
    @Environment(\.pane) private var pane

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        ZStack {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: size * 0.55, weight: .semibold))
            } else {
                Text(monogram).font(PaneFont.mono(size * 0.5, weight: .bold))
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .background(pane.strong, in: shape)
        .paneShadow(.capsule, in: shape)
        .accessibilityHidden(true)
    }
}

// MARK: - Grip

/// The six-dot drag grip (8×14), shown in a row's leading padding on hover so nothing shifts.
struct PaneGrip: View {
    @Environment(\.pane) private var pane

    var body: some View {
        Canvas { context, _ in
            for (x, y) in [(2.0, 3.0), (6, 3), (2, 7), (6, 7), (2, 11), (6, 11)] {
                context.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)), with: .color(pane.inkQuiet))
            }
        }
        .frame(width: 8, height: 14)
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

    private var hot: Bool { isHot || hovering }
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
