// The Pane components Settings draws (design/PaneTheme.swift, design/DIRECTIONS.md), reading the one palette
// (`\.tk`, TK.Palette) like everything else (v2 feedback 17). Pane's own derived palette, PaneColors, is gone, and
// with it the v1 components the AppKit list, sidebar and popovers replaced.

import SwiftUI

// MARK: - Interface style

public enum PaneInterfaceStyle: Hashable, Sendable { case classic, glass }

private struct PaneInterfaceStyleKey: EnvironmentKey {
    static let defaultValue: PaneInterfaceStyle = .classic
}

public extension EnvironmentValues {
    var paneInterfaceStyle: PaneInterfaceStyle {
        get { self[PaneInterfaceStyleKey.self] }
        set { self[PaneInterfaceStyleKey.self] = newValue }
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

// MARK: - Buttons

/// Pane's capsule buttons: 24 tall, padding 12, 13pt.
public struct PaneButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case tinted, neutral }

    var kind: Kind

    public init(_ kind: Kind = .neutral) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        PaneButtonBody(configuration: configuration, kind: kind)
    }
}

public extension ButtonStyle where Self == PaneButtonStyle {
    static func pane(_ kind: PaneButtonStyle.Kind = .neutral) -> PaneButtonStyle {
        PaneButtonStyle(kind)
    }
}

private struct PaneButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PaneButtonStyle.Kind
    @Environment(\.tk) private var tk
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle((kind == .tinted ? tk.accentText : tk.ink).swiftUI)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background((kind == .tinted ? tk.accentTint : tk.fillControl).swiftUI, in: Capsule())
            // Pressed darkens to 86%, as Pane's CSS `brightness(0.86)`, and eases back over 100 ms.
            .colorMultiply(configuration.isPressed ? Color(white: TK.Palette.pressBrightness) : .white)
            .animation(configuration.isPressed ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

// MARK: - Sections and rows

/// A header and a grouped card. Put PaneRow views inside, separated by PaneRowDivider.
public struct PaneSection<Content: View>: View {
    private let title: String?
    private let content: Content
    @Environment(\.tk) private var tk

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tk.ink.swiftUI)
            }
            VStack(spacing: 0) { content }
                .background(tk.card.swiftUI, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

public struct PaneRow<Trailing: View>: View {
    private let title: String
    private let description: String?
    private let trailing: Trailing
    @Environment(\.tk) private var tk

    public init(_ title: String, description: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.description = description
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(tk.ink.swiftUI)
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(tk.inkSecondary.swiftUI)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, description == nil ? 11 : 9)
    }
}

public extension PaneRow where Trailing == EmptyView {
    init(_ title: String, description: String? = nil) {
        self.init(title, description: description) { EmptyView() }
    }
}

/// Hairline between rows, inset to the row text.
public struct PaneRowDivider: View {
    @Environment(\.tk) private var tk
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(tk.lineSeparator.swiftUI)
            .frame(height: 1)
            .padding(.horizontal, 10)
    }
}
