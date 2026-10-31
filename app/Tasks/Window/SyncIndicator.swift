import AppKit
import QuartzCore
import SwiftUI
import TasksCore

// The sync indicator (INTERACTIONS-v2 §26): a cloud at the right end of the sidebar's header row, and, while the
// sidebar is hidden or its header has scrolled away, offline and stopped beside the sidebar toggle in the title band.
// The mock-up is design/prototype-v2/Sync.dc.html with sync.css.

/// What the cloud shows, from the store's `syncState`, `recovery` and `pendingCount`, and how long each has lasted
/// (§26 Timing): a sync shows after 300 ms and then for at least 600 ms, with "Syncing…" after 3 s; offline after 5 s
/// of retrying without a success, until the next one; the waiting dot after 3 s of changes waiting; stopped and a bad
/// token at once. One per window.
@MainActor
@Observable
final class SyncIndicator {
    enum Phase: Equatable {
        case synced, syncing(long: Bool), offline, stopped, badToken, off
    }

    private(set) var phase: Phase = .synced
    /// The dot: changes have waited more than 3 s (on the syncing, offline or stopped cloud only).
    private(set) var waiting = false

    @ObservationIgnored let store: Store
    @ObservationIgnored private var syncingSince: Date?
    @ObservationIgnored private var troubleSince: Date?
    @ObservationIgnored private var waitingSince: Date?
    @ObservationIgnored private var shownAt: Date?
    @ObservationIgnored private var timer: Timer?

    static let showAfter: TimeInterval = 0.3
    static let holdAtLeast: TimeInterval = 0.6
    static let longAfter: TimeInterval = 3
    static let offlineAfter: TimeInterval = 5
    static let waitingAfter: TimeInterval = 3

    init(store: Store) {
        self.store = store
        inputsChanged()
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = store.syncState
            _ = store.recovery
            _ = store.pendingCount
        } onChange: { [weak self] in
            // `onChange` comes before the change lands: read it on the next turn.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.inputsChanged()
                    self?.observe()
                }
            }
        }
    }

    /// Notes when the current sync, the current trouble and the current wait began.
    private func inputsChanged() {
        let now = Date()
        let s = store.syncState
        if case .syncing = s { if syncingSince == nil { syncingSince = now } } else { syncingSince = nil }
        switch s {
        case .retrying: if troubleSince == nil { troubleSince = now }
        // A retry is a sync too; only a success ends the trouble.
        case .syncing: break
        default: troubleSince = nil
        }
        if store.pendingCount > 0 { if waitingSince == nil { waitingSince = now } } else { waitingSince = nil }
        evaluate()
    }

    private func evaluate() {
        timer?.invalidate()
        timer = nil
        let now = Date()
        var next: Date?
        func recheck(at d: Date) { if d > now, next.map({ d < $0 }) ?? true { next = d } }
        let s = store.syncState
        var p: Phase
        switch s {
        case .off: p = .off
        case .checkToken: p = .badToken
        case .failed: p = .stopped
        case .idle, .syncing, .retrying:
            if let t = troubleSince, now.timeIntervalSince(t) >= Self.offlineAfter {
                p = .offline
            } else {
                if let t = troubleSince { recheck(at: t + Self.offlineAfter) }
                p = .synced
                if case .syncing = s, let since = syncingSince {
                    let ran = now.timeIntervalSince(since)
                    if ran >= Self.showAfter {
                        let long = store.recovery != nil || ran >= Self.longAfter
                        p = .syncing(long: long)
                        if !long { recheck(at: since + Self.longAfter) }
                    } else {
                        recheck(at: since + Self.showAfter)
                    }
                }
                // A sync that showed stays at least 600 ms, so one that ends at 350 ms doesn't blink.
                if p == .synced, case .syncing = phase, let shown = shownAt, now.timeIntervalSince(shown) < Self.holdAtLeast {
                    p = phase
                    recheck(at: shown + Self.holdAtLeast)
                }
            }
        }
        if case .syncing = p {
            if shownAt == nil { shownAt = now }
        } else {
            shownAt = nil
        }
        var w = false
        if let since = waitingSince {
            if now.timeIntervalSince(since) >= Self.waitingAfter { w = true } else { recheck(at: since + Self.waitingAfter) }
        }
        switch p {
        case .syncing, .offline, .stopped: break
        default: w = false
        }
        let entering = p != phase && (p == .stopped || p == .badToken)
        if p != phase { phase = p }
        if w != waiting { waiting = w }
        if entering { announce() }
        #if DEBUG
        DebugSync.note(self)
        #endif
        if let next {
            timer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSince(now) + 0.005, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
        }
    }

    // MARK: What it says

    /// Shows at rest; synced and off show only under the pointer.
    var showsAtRest: Bool { phase != .synced && phase != .off }

    /// Shows in the title band, with the sidebar hidden or its header scrolled away: offline and stopped only.
    var showsInBand: Bool { phase == .offline || phase == .stopped || phase == .badToken }

    /// A click opens Settings (off, a bad token) rather than syncing.
    var opensSettings: Bool { phase == .off || phase == .badToken }

    struct Tip: Equatable {
        var title: String
        var detail = ""
        var keys = ""
    }

    /// The tooltip, as of now (§26 States).
    func tip(now: Date = Date()) -> Tip {
        let n = store.pendingCount
        let changes = n == 1 ? "1 change" : "\(n.formatted()) changes"
        switch phase {
        case .synced:
            if case .idle(let at?) = store.syncState { return Tip(title: "Synced " + Self.ago(at, now: now), keys: "⌘R") }
            return Tip(title: "Synced", keys: "⌘R")
        case .syncing(let long):
            if long, let r = store.recovery { return Tip(title: "Restoring sync · \(r.confirmed.formatted()) of \(r.total.formatted())") }
            return Tip(title: waiting ? "Syncing · \(changes) waiting" : "Syncing…")
        case .offline:
            var title = "Can’t reach the server"
            if case .retrying(_, let reason) = store.syncState, let code = Self.httpStatus(reason) { title = "The server isn’t answering (\(code))" }
            if waiting { return Tip(title: title, detail: "\(changes.prefix(1).uppercased() + changes.dropFirst()) will go out when it’s back", keys: "⌘R") }
            return Tip(title: title, detail: retryWords(now: now), keys: "⌘R")
        case .stopped:
            let message = { if case .failed(let m) = store.syncState { return m } else { return "" } }()
            let detail = (message.isEmpty ? "" : message.hasSuffix(".") ? message + " " : message + ". ") + "Click to retry."
            return Tip(title: waiting ? "Sync stopped · \(changes) waiting" : "Sync stopped", detail: detail, keys: "⌘R")
        case .badToken:
            return Tip(title: "The server didn’t accept the token", detail: "Click to open Settings")
        case .off:
            return Tip(title: "Sync is off", detail: "Click to set it up in Settings")
        }
    }

    /// VoiceOver's value for the "Sync" button: the tooltip in words.
    func spoken(now: Date = Date()) -> String {
        let n = store.pendingCount
        let changes = (n == 1 ? "1 change" : "\(n.formatted()) changes") + " waiting to send"
        switch phase {
        case .synced:
            if case .idle(let at?) = store.syncState { return "Synced " + Self.ago(at, now: now, spoken: true) }
            return "Synced"
        case .syncing(let long):
            if long, let r = store.recovery { return "Restoring sync, \(r.confirmed.formatted()) of \(r.total.formatted())" }
            return waiting ? "Syncing, " + changes : "Syncing"
        case .offline:
            return waiting ? "Offline, " + changes : "Offline. " + retryWords(now: now, spoken: true)
        case .stopped:
            if case .failed(let m) = store.syncState, !m.isEmpty { return "Sync stopped. " + m }
            return "Sync stopped"
        case .badToken: return "Sync stopped. The server didn’t accept the token"
        case .off: return "Sync is off"
        }
    }

    private func retryWords(now: Date, spoken: Bool = false) -> String {
        guard case .retrying(let at, _) = store.syncState else { return "Trying again now" }
        let s = max(1, Int(at.timeIntervalSince(now).rounded(.up)))
        if s >= 60 { return "Trying again in a minute" }
        return "Trying again in \(s)" + (spoken ? (s == 1 ? " second" : " seconds") : " s")
    }

    /// "HTTP 503" → 503: a server error, not the network.
    private static func httpStatus(_ reason: String) -> Int? {
        guard reason.hasPrefix("HTTP ") else { return nil }
        return Int(reason.dropFirst(5))
    }

    /// "just now" under a minute, "N min ago" under an hour, then "at 9:41", then "yesterday at 9:41".
    static func ago(_ d: Date, now: Date, spoken: Bool = false) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { let m = Int(s / 60); return spoken ? (m == 1 ? "1 minute ago" : "\(m) minutes ago") : "\(m) min ago" }
        let cal = Calendar.current
        let time = d.formatted(date: .omitted, time: .shortened)
        if cal.isDate(d, inSameDayAs: now) { return "at " + time }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(d, inSameDayAs: y) { return "yesterday at " + time }
        return d.formatted(.dateTime.month(.abbreviated).day()) + " at " + time
    }

    /// Going into stopped or a bad token says so once (§26 VoiceOver). Syncing never does.
    private func announce() {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: spoken(), .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    /// A click: sync now, as ⌘R does; or open Settings for off and a bad token.
    func activate(openSettings: (() -> Void)?) {
        #if DEBUG
        DebugSync.activations += 1
        #endif
        if opensSettings { openSettings?() } else { store.requestSync(force: true) }
    }
}

// MARK: - The view

/// The cloud: a 22pt hit area (radius 6) with a 14pt glyph in the header row, or the toggle's 28pt circle with a 16pt
/// glyph in the band (`round`). Synced and off show only while the header row is hovered (`rowHovered`) or the cloud
/// itself. Appearing fades in over 100 ms, leaving over 200 ms; the glyphs crossfade over 150 ms; a sync pulses
/// (1 → 0.35 → 1 over 1.6 s). With Reduce Motion, no pulse; with the app inactive, no pulse and no fades.
struct SyncCloud: View {
    let indicator: SyncIndicator
    let overlays: Overlays
    var round = false
    /// In the band: shown only for offline and stopped, and only while the sidebar is hidden or its header is away.
    var inBand = false
    var rowHovered = false
    /// The cloud's frame in window coordinates (top-left origin), for its tooltip.
    let anchor: () -> CGRect
    let openSettings: (() -> Void)?
    @Environment(\.tk) private var tk
    @State private var hovered = false
    @State private var active = SyncCloud.appActive

    private static var appActive: Bool {
        #if DEBUG
        if DebugSync.appActive { return true }
        #endif
        return NSApp.isActive
    }

    var body: some View {
        let phase = indicator.phase
        let shown = round ? inBand && indicator.showsInBand : indicator.showsAtRest || rowHovered || hovered
        let alert = phase == .stopped || phase == .badToken
        let long: Bool = { if case .syncing(true) = phase { return true } else { return false } }()
        HStack(spacing: 5) {
                if long, !round {
                    Text("Syncing…").font(.system(size: 11)).foregroundStyle(tk.inkTertiary.swiftUI).fixedSize()
                }
                CloudGlyph(symbol: Self.symbol(phase), color: color(phase), dot: indicator.waiting ? tk.accentText : nil,
                           size: round ? 16 : 14, pulsing: pulsing && shown, animated: active)
                    .frame(width: round ? 16 : 14, height: round ? 16 : 14)
        }
        .padding(.horizontal, round ? 6 : 4)
        .frame(minWidth: round ? 28 : 22, minHeight: round ? 28 : 22)
        .background {
            // The `hover` fill under the pointer (`attention-tint` when stopped), on `icon`.
            RoundedRectangle(cornerRadius: round ? 14 : 6, style: .circular)
                .fill((hovered ? (alert ? tk.attentionTint : tk.hover) : .clear).swiftUI)
                .animation(TK.Motion.icon, value: hovered)
        }
        .contentShape(RoundedRectangle(cornerRadius: round ? 14 : 6, style: .circular))
        .onTapGesture {
            overlays.hideTip()
            indicator.activate(openSettings: openSettings)
        }
        // A click counts while the window isn't key, as the sidebar's rows do.
        .modifier(CloudFirstMouse())
        .opacity(shown ? 1 : 0)
        .animation(active ? .timingCurve(0, 0, 0.2, 1, duration: shown ? 0.1 : 0.2) : nil, value: shown)
        // The band's cloud takes no clicks and says nothing while it doesn't show; the header's is always there.
        .allowsHitTesting(!round || shown)
        .accessibilityHidden(round && !shown)
        .onHover { inside in
            hovered = inside
            if inside {
                let t = indicator.tip()
                overlays.hoverTip(t.title, detail: t.detail, keys: t.keys, for: anchor(), windowWidth: NSApp.keyWindow?.frame.width ?? 1200)
            } else {
                overlays.hideTip()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in active = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in active = Self.appActive }
        .accessibilityElement()
        .accessibilityLabel("Sync")
        .accessibilityValue(indicator.spoken())
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { indicator.activate(openSettings: openSettings) }
    }

    private var pulsing: Bool {
        guard case .syncing = indicator.phase else { return false }
        return active && !TK.Motion.reduce
    }

    private func color(_ p: SyncIndicator.Phase) -> NSColor {
        switch p {
        case .syncing: tk.inkTertiary
        case .stopped, .badToken: tk.attention
        case .synced, .offline, .off: tk.inkQuiet
        }
    }

    static func symbol(_ p: SyncIndicator.Phase) -> String {
        switch p {
        case .synced, .syncing: "icloud"
        case .offline, .off: "icloud.slash"
        case .stopped, .badToken: "exclamationmark.icloud.fill"
        }
    }
}

private struct CloudFirstMouse: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.allowsWindowActivationEvents(true) } else { content }
    }
}

/// The symbol in layers, so the pulse runs in Core Animation (no SwiftUI pass a frame) and the dot can cut the cloud
/// away 1.3pt around it.
private struct CloudGlyph: NSViewRepresentable {
    let symbol: String
    let color: NSColor
    let dot: NSColor?
    let size: CGFloat
    let pulsing: Bool
    let animated: Bool

    func makeNSView(context: Context) -> CloudGlyphView { CloudGlyphView() }

    func updateNSView(_ v: CloudGlyphView, context: Context) {
        v.set(symbol: symbol, color: color, dot: dot, size: size, pulsing: pulsing, animated: animated)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CloudGlyphView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

final class CloudGlyphView: NSView {
    private let glyph = CALayer()
    private let hole = CAShapeLayer()
    private let dot = CALayer()
    private var key = ""
    private var pulsing = false
    private var last: (String, NSColor, NSColor?, CGFloat)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        glyph.contentsGravity = .center
        hole.fillRule = .evenOdd
        hole.fillColor = NSColor.black.cgColor
        layer?.addSublayer(glyph)
        layer?.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// The pointer goes through to the button around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func set(symbol: String, color: NSColor, dot dotColor: NSColor?, size: CGFloat, pulsing p: Bool, animated: Bool) {
        last = (symbol, color, dotColor, size)
        let scale = window?.backingScaleFactor ?? 2
        let k = "\(symbol)|\(color)|\(size)|\(scale)|\(dotColor.map { "\($0)" } ?? "-")"
        if k != key {
            let changed = !key.isEmpty && !key.hasPrefix(symbol + "|") && animated && !TK.Motion.reduce
            key = k
            // Monochrome, tinted: the filled cloud's "!" stays cut out (a one-colour palette would fill it in).
            let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular).applying(.preferringMonochrome())
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
                .map { Self.tinted($0, color) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if changed {
                // The glyphs crossfade over 150 ms.
                let t = CATransition()
                t.type = .fade
                t.duration = 0.15
                glyph.add(t, forKey: "crossfade")
            }
            let s = image.map { $0.recommendedLayerContentsScale(scale) } ?? scale
            glyph.contents = image?.layerContents(forContentsScale: s)
            glyph.contentsScale = s
            // The symbol's own box, centred: a cloud is wider than it's tall, so it overhangs the square.
            let w = image?.size.width ?? size, h = image?.size.height ?? size
            glyph.frame = CGRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h)
            // The dot: 4pt at the cloud's top right, the cloud cut away 1.3pt around it.
            let c = CGPoint(x: glyph.frame.maxX - 2, y: glyph.frame.minY + 2)
            dot.frame = CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)
            dot.cornerRadius = 2
            if let dotColor {
                dot.backgroundColor = dotColor.cgColor
                dot.isHidden = false
                let path = CGMutablePath()
                path.addRect(glyph.bounds.insetBy(dx: -4, dy: -4))
                let r: CGFloat = 2 + 1.3
                let local = CGPoint(x: c.x - glyph.frame.minX, y: c.y - glyph.frame.minY)
                path.addEllipse(in: CGRect(x: local.x - r, y: local.y - r, width: 2 * r, height: 2 * r))
                hole.path = path
                hole.frame = glyph.bounds
                glyph.mask = hole
            } else {
                dot.isHidden = true
                glyph.mask = nil
            }
            CATransaction.commit()
        }
        if p != pulsing {
            pulsing = p
            if p {
                // 1 → 0.35 → 1 over 1.6 s, ease-in-out, looping.
                let a = CAKeyframeAnimation(keyPath: "opacity")
                a.values = [1, 0.35, 1]
                a.keyTimes = [0, 0.5, 1]
                a.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
                a.duration = 1.6
                a.repeatCount = .infinity
                glyph.add(a, forKey: "pulse")
                dot.add(a, forKey: "pulse")
            } else {
                glyph.removeAnimation(forKey: "pulse")
                dot.removeAnimation(forKey: "pulse")
            }
        }
    }

    private static func tinted(_ symbol: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
    }

    #if DEBUG
    var debugPulsing: Bool { glyph.animation(forKey: "pulse") != nil }
    var debugAlpha: Float { glyph.presentation()?.opacity ?? glyph.opacity }
    #endif

    /// A new screen scale draws the symbol again.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let (symbol, color, dot, size) = last else { return }
        key = ""
        set(symbol: symbol, color: color, dot: dot, size: size, pulsing: pulsing, animated: false)
    }
}
