// Pane — chrome derived from a terminal-style theme.
// Drop this file into a SwiftUI target (macOS 14+ / iOS 17+). Values match tokens.json.
//
// Tasks: this is design/PaneTheme.swift plus the new tokens design/DIRECTIONS.md proposes, derived by the same
// mix rules and marked "Tasks:" below (attention-tint, shadow-popover, shadow-lift, the check and chip sizes).
// The new components live in PaneComponents.swift.
//
//   ContentView()
//       .paneTheme(.dark)              // or .light, or your own PaneTheme
//       .paneInterfaceStyle(.classic)  // or .glass
//
// Every surface, fill, line and text color is computed from four inputs:
// background, foreground, accent and the 16 ANSI colors. Change the theme
// and the whole app follows, the way a terminal's chrome follows its theme.

import SwiftUI
import CoreText

// MARK: - Color math

public struct PaneRGB: Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Straight blend in sRGB, the same math that produced tokens.json.
    public func mixed(with other: PaneRGB, _ t: Double) -> PaneRGB {
        PaneRGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public func contrast(with other: PaneRGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public static let black = PaneRGB(0x000000)
    public static let white = PaneRGB(0xFFFFFF)
}

// MARK: - Theme (the only input)

public struct PaneTheme: Hashable, Sendable {
    public enum Appearance: Hashable, Sendable { case dark, light }

    public var name: String
    public var appearance: Appearance
    public var background: PaneRGB
    public var foreground: PaneRGB
    /// The cursor color. Becomes the app's accent.
    public var accent: PaneRGB
    public var selection: PaneRGB
    public var selectionText: PaneRGB
    /// 16 colors: 0–7 standard (black, red, green, yellow, blue, magenta, cyan, white), 8–15 bright.
    public var ansi: [PaneRGB]

    public init(name: String, appearance: Appearance, background: PaneRGB, foreground: PaneRGB,
                accent: PaneRGB, selection: PaneRGB, selectionText: PaneRGB, ansi: [PaneRGB]) {
        precondition(ansi.count == 16, "A Pane theme needs 16 ANSI colors.")
        self.name = name
        self.appearance = appearance
        self.background = background
        self.foreground = foreground
        self.accent = accent
        self.selection = selection
        self.selectionText = selectionText
        self.ansi = ansi
    }

    public static let dark = PaneTheme(
        name: "Dark", appearance: .dark,
        background: PaneRGB(0x1C1C1C), foreground: PaneRGB(0xE6EDF3), accent: PaneRGB(0x2F81F7),
        selection: PaneRGB(0xE6EDF3), selectionText: PaneRGB(0x0D1117),
        ansi: [0x484F58, 0xFF7B72, 0x3FB950, 0xD29922, 0x58A6FF, 0xBC8CFF, 0x39C5CF, 0xB1BAC4,
               0x6E7681, 0xFFA198, 0x56D364, 0xE3B341, 0x79C0FF, 0xD2A8FF, 0x56D4DD, 0xFFFFFF].map(PaneRGB.init)
    )

    public static let light = PaneTheme(
        name: "Light", appearance: .light,
        background: PaneRGB(0xFFFFFF), foreground: PaneRGB(0x1F2328), accent: PaneRGB(0x0969DA),
        selection: PaneRGB(0x1F2328), selectionText: PaneRGB(0xFFFFFF),
        ansi: [0x24292F, 0xCF222E, 0x116329, 0x9A6700, 0x0969DA, 0x8250DF, 0x1B7C83, 0x6E7781,
               0x57606A, 0xA40E26, 0x1A7F37, 0x633C01, 0x218BFF, 0xA475F9, 0x3192AA, 0x8C959F].map(PaneRGB.init)
    )
}

// MARK: - Derivation rules (mix amounts toward the foreground)

struct PaneRules: Sendable {
    var groundFromBlack: Bool
    var ground, dim: Double?
    var card, selected, control, track, thumb, strong, capsule, band: Double
    var separator, edge, edgeDim: Double
    var ink2, ink3, quiet, fieldEdge: Double
    var tint, dangerTint: Double
    // Tasks: attention-tint, the bg → ANSI yellow mix. Light needs 0.05: the light yellow on a 0.09 mix is 4.33:1.
    var attentionTint: Double

    static let dark = PaneRules(groundFromBlack: true, ground: 0.14, dim: nil,
                                card: 0.015, selected: 0.055, control: 0.085, track: 0.10, thumb: 0.23,
                                strong: 0.20, capsule: 0.125, band: 0.13,
                                separator: 0.13, edge: 0.11, edgeDim: 0.06,
                                ink2: 0.42, ink3: 0.48, quiet: 0.60, fieldEdge: 0.62,
                                tint: 0.13, dangerTint: 0.14, attentionTint: 0.14)

    static let light = PaneRules(groundFromBlack: false, ground: 0.045, dim: 0.022,
                                 card: 0, selected: 0.075, control: 0.08, track: 0.10, thumb: 0,
                                 strong: 0.14, capsule: 0.10, band: 0.055,
                                 separator: 0.105, edge: 0.19, edgeDim: 0.09,
                                 ink2: 0.30, ink3: 0.345, quiet: 0.47, fieldEdge: 0.45,
                                 tint: 0.10, dangerTint: 0.09, attentionTint: 0.05)
}

// MARK: - Derived palette

public struct PaneColors: Sendable {
    // Surfaces
    public let ground, base, dim, card: Color
    // Fills
    public let selected, control, track, thumb, strong, capsule, band: Color
    // Lines
    public let separator, paneEdge, paneEdgeDim, fieldEdge: Color
    // Ink
    public let ink, inkSecondary, inkTertiary, inkQuiet: Color
    // Accent and state
    public let accent, accentText, accentTint, onAccent, focusRing: Color
    public let dangerText, dangerTint, running, attention: Color
    public let selection, onSelection: Color
    public let ansi: [Color]
    // Tasks: new tokens.
    public let attentionTint: Color
    public let isDark: Bool

    public init(_ theme: PaneTheme) {
        let rules: PaneRules = theme.appearance == .dark ? .dark : .light
        let bg = theme.background, fg = theme.foreground, ac = theme.accent
        func up(_ t: Double) -> Color { bg.mixed(with: fg, t).color }

        let groundRGB = rules.groundFromBlack
            ? bg.mixed(with: .black, rules.ground ?? 0)
            : bg.mixed(with: fg, rules.ground ?? 0)
        ground = groundRGB.color
        base = bg.color
        dim = rules.dim.map { bg.mixed(with: fg, $0).color } ?? groundRGB.color
        card = up(rules.card)

        selected = up(rules.selected)
        control = up(rules.control)
        track = up(rules.track)
        thumb = up(rules.thumb)
        strong = up(rules.strong)
        capsule = up(rules.capsule)
        band = up(rules.band)

        separator = up(rules.separator)
        paneEdge = up(rules.edge)
        paneEdgeDim = up(rules.edgeDim)
        fieldEdge = fg.mixed(with: bg, rules.fieldEdge).color

        ink = fg.color
        inkSecondary = fg.mixed(with: bg, rules.ink2).color
        inkTertiary = fg.mixed(with: bg, rules.ink3).color
        inkQuiet = fg.mixed(with: bg, rules.quiet).color

        accent = ac.color
        accentText = (theme.appearance == .dark ? ac.mixed(with: fg, 0.22) : ac).color
        accentTint = bg.mixed(with: ac, rules.tint).color
        // Text on an accent fill is the theme background when it reads (4.5:1), so buttons look cut out of the theme.
        let onAccentRGB: PaneRGB = bg.contrast(with: ac) >= 4.5
            ? bg
            : (theme.appearance == .dark ? PaneRGB(0x0D1117) : .white)
        onAccent = onAccentRGB.color
        focusRing = ac.color

        let red = theme.ansi[1]
        dangerText = red.color
        dangerTint = bg.mixed(with: red, rules.dangerTint).color
        running = (theme.appearance == .dark ? theme.ansi[2] : theme.ansi[10]).color
        attention = theme.ansi[3].color

        selection = theme.selection.color
        onSelection = theme.selectionText.color
        ansi = theme.ansi.map(\.color)

        attentionTint = bg.mixed(with: theme.ansi[3], rules.attentionTint).color
        isDark = theme.appearance == .dark
    }

    /// Tasks: a list's mark color, by its 7-slot index: ink, blue, magenta, green, cyan, yellow, red.
    public func listColor(slot: Int) -> Color {
        [ink, ansi[4], ansi[5], ansi[2], ansi[6], ansi[3], ansi[1]][((slot % 7) + 7) % 7]
    }
}

/// Category tile fills. White glyphs hold 3:1 on each.
public enum PaneTileColor {
    public static let red = PaneRGB(0xDA3633).color
    public static let orange = PaneRGB(0xBD561D).color
    public static let green = PaneRGB(0x1F883D).color
    public static let blue = PaneRGB(0x1F6FEB).color
    public static let purple = PaneRGB(0x8250DF).color
    public static let graphite = PaneRGB(0x3D444D).color
}

// MARK: - Environment

public enum PaneInterfaceStyle: Hashable, Sendable { case classic, glass }

private struct PaneColorsKey: EnvironmentKey {
    static let defaultValue = PaneColors(.dark)
}

private struct PaneInterfaceStyleKey: EnvironmentKey {
    static let defaultValue: PaneInterfaceStyle = .classic
}

private struct PaneHeaderInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

public extension EnvironmentValues {
    /// Tasks: extra leading room in a pane header, for window controls drawn over it.
    var paneHeaderInset: CGFloat {
        get { self[PaneHeaderInsetKey.self] }
        set { self[PaneHeaderInsetKey.self] = newValue }
    }

    var pane: PaneColors {
        get { self[PaneColorsKey.self] }
        set { self[PaneColorsKey.self] = newValue }
    }

    var paneInterfaceStyle: PaneInterfaceStyle {
        get { self[PaneInterfaceStyleKey.self] }
        set { self[PaneInterfaceStyleKey.self] = newValue }
    }
}

public extension View {
    /// Applies a theme: derived colors in the environment, the accent as tint, and the matching color scheme.
    func paneTheme(_ theme: PaneTheme) -> some View {
        let colors = PaneColors(theme)
        return self
            .environment(\.pane, colors)
            .tint(colors.accent)
            .preferredColorScheme(theme.appearance == .dark ? .dark : .light)
    }

    func paneInterfaceStyle(_ style: PaneInterfaceStyle) -> some View {
        environment(\.paneInterfaceStyle, style)
    }
}

// MARK: - Metrics

public enum PaneSpace {
    public static let s2: CGFloat = 2
    public static let s4: CGFloat = 4
    public static let s6: CGFloat = 6
    public static let s8: CGFloat = 8
    public static let s10: CGFloat = 10
    public static let s12: CGFloat = 12
    public static let s16: CGFloat = 16
    public static let s20: CGFloat = 20
    public static let s24: CGFloat = 24
    public static let s32: CGFloat = 32
}

public enum PaneRadius {
    public static let tile: CGFloat = 5
    public static let field: CGFloat = 6
    public static let swatch: CGFloat = 8
    public static let pane: CGFloat = 10
    public static let row: CGFloat = 10
    public static let card: CGFloat = 12
    public static let theme: CGFloat = 16
    public static let sheet: CGFloat = 20
}

public enum PaneSize {
    // Tasks: size-check, size-chip, size-chip-large. Task rows use sidebarRow (32).
    public static let check: CGFloat = 16
    public static let chip: CGFloat = 18
    public static let chipLarge: CGFloat = 22
    public static let tile: CGFloat = 20
    public static let tileLarge: CGFloat = 28
    public static let controlSmall: CGFloat = 24
    public static let control: CGFloat = 28
    public static let field: CGFloat = 22
    public static let sidebarRow: CGFloat = 32
    public static let paneHeader: CGFloat = 32
    public static let sidebar: CGFloat = 220
}

// MARK: - Shadows (Tasks: shadow-popover and shadow-lift are shadow-sheet with shorter blurs)

public enum PaneShadow: Sendable {
    /// A 1pt inset hairline: white 7% in dark, ink 6% in light.
    case capsule
    /// shadow-sheet with a 12/32 blur.
    case popover
    /// shadow-sheet with an 8/24 blur: a dragged row.
    case lift
}

public extension View {
    func paneShadow<S: InsettableShape>(_ kind: PaneShadow, in shape: S) -> some View {
        modifier(PaneShadowModifier(kind: kind, shape: shape))
    }
}

private struct PaneShadowModifier<S: InsettableShape>: ViewModifier {
    let kind: PaneShadow
    let shape: S
    @Environment(\.pane) private var pane

    private static var ink: Color { Color(red: 31 / 255, green: 35 / 255, blue: 40 / 255) }

    func body(content: Content) -> some View {
        let ring = pane.isDark ? Color.white.opacity(0.08) : Self.ink.opacity(0.10)
        let drop = pane.isDark ? Color.black.opacity(0.50) : Self.ink.opacity(0.18)
        switch kind {
        case .capsule:
            content.overlay { shape.strokeBorder(pane.isDark ? Color.white.opacity(0.07) : Self.ink.opacity(0.06), lineWidth: 1) }
        case .popover:
            content
                .overlay { shape.strokeBorder(ring, lineWidth: 1) }
                .shadow(color: drop, radius: 16, y: 12)
        case .lift:
            content
                .overlay { shape.strokeBorder(ring, lineWidth: 1) }
                .shadow(color: drop, radius: 12, y: 8)
        }
    }
}

// MARK: - Type

public enum PaneFont {
    public static let title = Font.system(size: 15, weight: .bold)
    public static let headline = Font.system(size: 13, weight: .semibold)
    public static let body = Font.system(size: 13)
    public static let bodyMedium = Font.system(size: 13, weight: .medium)
    public static let subheadline = Font.system(size: 11)
    public static let label = Font.system(size: 11, weight: .semibold)

    /// JetBrains Mono when installed or bundled, otherwise SF Mono.
    public static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        jetBrainsMonoAvailable
            ? Font.custom("JetBrains Mono", size: size).weight(weight)
            : Font.system(size: size, weight: weight, design: .monospaced)
    }

    static let jetBrainsMonoAvailable: Bool = {
        let font = CTFontCreateWithName("JetBrainsMono-Regular" as CFString, 13, nil)
        return (CTFontCopyFamilyName(font) as String) == "JetBrains Mono"
    }()
}

// MARK: - Motion

public enum PaneMotion {
    /// Switches, segment thumb, active-pane edge.
    public static var snappy: Animation { .snappy(duration: 0.2) }
    /// Panes opening, closing, resizing.
    public static var natural: Animation { .smooth(duration: 0.3) }
    /// First-load reveal: 12pt rise, blur clearing.
    public static var reveal: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: 0.6) }
    public static let stagger: Double = 0.04
}

// MARK: - Buttons

public struct PaneButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, tinted, neutral, destructive }
    public enum Size: Sendable { case small, regular }

    var kind: Kind
    var size: Size

    public init(_ kind: Kind = .neutral, size: Size = .small) {
        self.kind = kind
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        PaneButtonBody(configuration: configuration, kind: kind, size: size)
    }
}

public extension ButtonStyle where Self == PaneButtonStyle {
    static func pane(_ kind: PaneButtonStyle.Kind = .neutral, size: PaneButtonStyle.Size = .small) -> PaneButtonStyle {
        PaneButtonStyle(kind, size: size)
    }
}

private struct PaneButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PaneButtonStyle.Kind
    let size: PaneButtonStyle.Size
    @Environment(\.pane) private var pane
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(size == .small ? PaneFont.body : PaneFont.bodyMedium)
            .foregroundStyle(labelColor)
            .padding(.horizontal, size == .small ? 12 : 16)
            .frame(height: size == .small ? PaneSize.controlSmall : PaneSize.control)
            .background(fillColor, in: Capsule())
            // Tasks: pressed darkens to 86%, as Pane's CSS `brightness(0.86)`, and eases back over duration-hover.
            .colorMultiply(configuration.isPressed ? Color(white: 0.86) : .white)
            .animation(configuration.isPressed ? nil : PaneMotion.icon, value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }

    private var fillColor: Color {
        switch kind {
        case .primary: pane.accent
        case .tinted: pane.accentTint
        case .neutral: pane.control
        case .destructive: pane.dangerTint
        }
    }

    private var labelColor: Color {
        switch kind {
        case .primary: pane.onAccent
        case .tinted: pane.accentText
        case .neutral: pane.ink
        case .destructive: pane.dangerText
        }
    }
}

// MARK: - Settings: sections, rows, tiles

/// A header and a grouped card. Put PaneRow views inside, separated by PaneRowDivider.
public struct PaneSection<Content: View>: View {
    private let title: String?
    private let content: Content
    @Environment(\.pane) private var pane

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PaneSpace.s12) {
            if let title {
                Text(title)
                    .font(PaneFont.headline)
                    .foregroundStyle(pane.ink)
            }
            VStack(spacing: 0) { content }
                .background(pane.card, in: RoundedRectangle(cornerRadius: PaneRadius.card, style: .continuous))
        }
    }
}

public struct PaneRow<Trailing: View>: View {
    private let title: String
    private let description: String?
    private let trailing: Trailing
    @Environment(\.pane) private var pane

    public init(_ title: String, description: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.description = description
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: PaneSpace.s12) {
            VStack(alignment: .leading, spacing: PaneSpace.s2) {
                Text(title)
                    .font(PaneFont.body)
                    .foregroundStyle(pane.ink)
                if let description {
                    Text(description)
                        .font(PaneFont.subheadline)
                        .foregroundStyle(pane.inkSecondary)
                }
            }
            Spacer(minLength: PaneSpace.s12)
            trailing
        }
        .padding(.horizontal, PaneSpace.s10)
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
    @Environment(\.pane) private var pane
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(pane.separator)
            .frame(height: 1)
            .padding(.horizontal, PaneSpace.s10)
    }
}

/// A 20pt squircle with a white SF Symbol: settings categories, programs in a tab list.
public struct PaneTile: View {
    private let systemImage: String
    private let fill: Color
    private let size: CGFloat

    public init(_ systemImage: String, fill: Color, size: CGFloat = PaneSize.tile) {
        self.systemImage = systemImage
        self.fill = fill
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Search field

public struct PaneSearchField: View {
    @Binding private var text: String
    private let prompt: String
    @Environment(\.pane) private var pane
    @FocusState private var focused: Bool

    public init(_ prompt: String = "Search", text: Binding<String>) {
        self.prompt = prompt
        self._text = text
    }

    public var body: some View {
        HStack(spacing: PaneSpace.s6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(pane.inkSecondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(PaneFont.body)
                .foregroundStyle(pane.ink)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(pane.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, PaneSpace.s10)
        .frame(height: PaneSize.control)
        .background(pane.control, in: Capsule())
        .overlay {
            Capsule().strokeBorder(focused ? pane.focusRing : Color.clear, lineWidth: 2)
        }
        .animation(PaneMotion.snappy, value: focused)
    }
}

// MARK: - Panes

/// A pane: header with icon, title and actions over content. The focused pane uses the theme
/// background and a brighter edge; others fade toward the ground.
public struct PaneChrome<Actions: View, Content: View>: View {
    private let title: String
    private let systemImage: String?
    // Tasks: list panes show a list mark instead of a symbol, and a subtitle ("7 tasks", "Fri, Oct 30").
    private var leading: AnyView? = nil
    private var subtitle: String? = nil
    private let isActive: Bool
    private let actions: Actions
    private let content: Content
    @Environment(\.pane) private var pane
    @Environment(\.paneInterfaceStyle) private var style
    @Environment(\.paneHeaderInset) private var headerInset

    public init(_ title: String, systemImage: String? = nil, isActive: Bool,
                @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.isActive = isActive
        self.actions = actions()
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: PaneRadius.pane, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: PaneSpace.s8) {
                if let leading {
                    leading
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(pane.ink)
                }
                Text(title)
                    .font(PaneFont.bodyMedium)
                    .foregroundStyle(pane.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(PaneFont.body)
                        .foregroundStyle(pane.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: PaneSpace.s8)
                HStack(spacing: PaneSpace.s4) { actions }
                    .foregroundStyle(pane.inkQuiet)
                    // Tasks: an unfocused pane's header icons fade, as in Rex.
                    .opacity(isActive ? 1 : 0.55)
            }
            .padding(.horizontal, PaneSpace.s12)
            // Tasks: room for the window controls when the sidebar is collapsed and this is the leftmost pane.
            .padding(.leading, headerInset)
            .frame(height: PaneSize.paneHeader)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background { paneBackground(shape) }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isActive ? pane.paneEdge : pane.paneEdgeDim, lineWidth: 1)
        }
        // Tasks: Rex's measured focus change is ~60 ms.
        .animation(.easeOut(duration: 0.06), value: isActive)
    }

    @ViewBuilder
    private func paneBackground(_ shape: RoundedRectangle) -> some View {
        switch style {
        case .classic:
            shape.fill(isActive ? pane.base : pane.dim)
        case .glass:
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, *) {
                shape.fill(Color.clear).glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
            #else
            shape.fill(.ultraThinMaterial)
            #endif
        }
    }
}

public extension PaneChrome {
    /// Tasks: a header with a custom leading view (a list mark) and a subtitle.
    init<Leading: View>(_ title: String, subtitle: String?, isActive: Bool, @ViewBuilder leading: () -> Leading,
                        @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Content) {
        self.init(title, systemImage: nil, isActive: isActive, actions: actions, content: content)
        self.leading = AnyView(leading())
        self.subtitle = subtitle
    }

    init(_ title: String, systemImage: String, subtitle: String?, isActive: Bool,
         @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Content) {
        self.init(title, systemImage: systemImage, isActive: isActive, actions: actions, content: content)
        self.subtitle = subtitle
    }
}

public extension PaneChrome where Actions == EmptyView {
    init(_ title: String, systemImage: String? = nil, isActive: Bool, @ViewBuilder content: () -> Content) {
        self.init(title, systemImage: systemImage, isActive: isActive, actions: { EmptyView() }, content: content)
    }
}

/// A 22pt icon button for pane headers and toolbars, drawn in ink-quiet.
public struct PaneIconButton: View {
    private let systemImage: String
    private let help: String
    private let action: () -> Void

    public init(_ systemImage: String, help: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        // Tasks: hover brightens the glyph one step, pressed goes to ink (design/INTERACTIONS.md).
        .buttonStyle(PaneGhostButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}
