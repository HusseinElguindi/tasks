#if DEBUG
import AppKit
import Foundation
import TasksCore

/// Debug aid for the sync indicator (§26). Debug builds sync through `DebugSync.Transport`, the real transport with a
/// delay and forced outcomes that `-debugScript` steps set:
///
///     sync:delay:MS        every request takes at least MS
///     sync:mode:M          none (the server's answer), offline (a network error), server (HTTP 503), token (401),
///                          stop (400 bad_request)
///     sync:now             ⌘R's sync
///     sync:rec:/f.txt      a line per change of what the cloud shows, with the time since `rec`; `sync:recstop`
///     sync:log:/f.txt      appends the cloud's state now: phase, dot, tooltip, VoiceOver's value, pulse, the band
///     sync:click           a click on the header's cloud through the window (or the band's, if it shows)
///     sync:rowhover:on|off the pointer over the header row
///     sync:sidebar:show|hide, sync:sidebarscroll:Y
///
/// `-debugAppActive YES` treats the app as active (a scratch instance runs in the background, which is inactive: no
/// pulse, no fades).
@MainActor
enum DebugSync {
    final class Control: @unchecked Sendable {
        private let lock = NSLock()
        private var _delay = 0
        private var _mode = "none"
        var delay: Int { get { lock.withLock { _delay } } set { lock.withLock { _delay = newValue } } }
        var mode: String { get { lock.withLock { _mode } } set { lock.withLock { _mode = newValue } } }
    }

    nonisolated static let control = Control()

    struct Transport: SyncTransport {
        let real = HTTPSyncTransport()

        func send(_ body: Data, config: SyncConfig) async -> SyncOutcome {
            let started = ContinuousClock.now
            let outcome: SyncOutcome
            switch DebugSync.control.mode {
            case "offline": outcome = .transient("The Internet connection appears to be offline.")
            case "server": outcome = .transient("HTTP 503")
            case "token": outcome = .badToken
            case "stop": outcome = .badRequest("The server’s log keeps changing.")
            default: outcome = await real.send(body, config: config)
            }
            let rest = Duration.milliseconds(DebugSync.control.delay) - (ContinuousClock.now - started)
            if rest > .zero { try? await Task.sleep(for: rest) }
            return outcome
        }
    }

    static var activations = 0
    private static var recording: String?
    private static var recStart: CFTimeInterval = 0
    private static var last = ""

    static var appActive: Bool { UserDefaults.standard.bool(forKey: "debugAppActive") }

    /// Every evaluation of the indicator; a line when what it shows changed.
    static func note(_ s: SyncIndicator) {
        guard let path = recording else { return }
        let line = describe(s)
        guard line != last else { return }
        last = line
        append(String(format: "%7.0f ", (CACurrentMediaTime() - recStart) * 1000) + line, to: path)
    }

    private static func describe(_ s: SyncIndicator) -> String {
        let state: String = switch s.store.syncState {
        case .off: "off"
        case .idle: "idle"
        case .syncing: "syncing"
        case .retrying: "retrying"
        case .checkToken: "checkToken"
        case .failed: "failed"
        }
        return "phase=\(s.phase) dot=\(s.waiting ? 1 : 0) state=\(state) pending=\(s.store.pendingCount)"
    }

    private static func append(_ line: String, to path: String) {
        let l = line + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(l.utf8)); h.closeFile() }
        else { try? l.write(toFile: path, atomically: true, encoding: .utf8) }
    }

    static func step(_ arg: String, window: WindowState, store: Store) async {
        let parts = arg.split(separator: ":", maxSplits: 1).map(String.init)
        let rest = parts.count > 1 ? parts[1] : ""
        let s = window.sync(store)
        switch parts[0] {
        case "delay": control.delay = Int(rest) ?? 0
        case "mode": control.mode = rest
        case "now": store.requestSync(force: true)
        case "rec":
            recording = rest
            recStart = CACurrentMediaTime()
            last = ""
            try? "".write(toFile: rest, atomically: true, encoding: .utf8)
            note(s)
        case "recstop": recording = nil
        case "rowhover": window.sidebarHeaderHovered = rest == "on"
        case "activate": s.activate(openSettings: window.openSettings)
        case "sidebarscroll": window.sidebarView?.debugScroll(CGFloat(Double(rest) ?? 0))
        case "sidebar": if window.sidebarVisible != (rest == "show") { WindowActions(store: store, window: window).toggleSidebar() }
        case "log":
            let t = s.tip()
            var line = describe(s) + " tip='\(t.title)' detail='\(t.detail)' keys='\(t.keys)' spoken='\(s.spoken())'"
            line += " band=\((!window.sidebarVisible || window.sidebarHeaderHidden) && s.showsInBand ? 1 : 0)"
            line += " activations=\(activations) headerHidden=\(window.sidebarHeaderHidden ? 1 : 0) rowHover=\(window.sidebarHeaderHovered ? 1 : 0)"
            if let v = window.nsWindow?.contentView {
                let glyphs = cloudGlyphs(in: v)
                line += " glyphs=" + glyphs.map { g in
                    let f = g.convert(g.bounds, to: nil)
                    return String(format: "(%.0f,%.0f pulse=%d alpha=%.2f)", f.midX, v.bounds.height - f.midY, g.debugPulsing ? 1 : 0, g.debugAlpha)
                }.joined(separator: ",")
            }
            line += " windows=" + NSApp.windows.map { "'\($0.title)'\($0.isVisible ? "" : "(hidden)")" }.joined(separator: ",")
            line += " tipShown='\(window.overlays.tip.map { $0.text + "|" + $0.detail } ?? "-")'"
            append(line, to: rest)
        default: break
        }
    }

    /// The point to click on a cloud, in window coordinates from the top left: the band's if it shows, else the header's.
    static func cloudPoint(window: WindowState, store: Store) -> CGPoint? {
        let s = window.sync(store)
        if (!window.sidebarVisible || window.sidebarHeaderHidden) && s.showsInBand { return CGPoint(x: 139, y: 25) }
        return window.sidebarView?.debugCloudCenter()
    }

    private static func cloudGlyphs(in v: NSView) -> [CloudGlyphView] {
        var out: [CloudGlyphView] = []
        func walk(_ v: NSView) {
            if let g = v as? CloudGlyphView { out.append(g) }
            v.subviews.forEach(walk)
        }
        walk(v)
        return out
    }
}
#endif
