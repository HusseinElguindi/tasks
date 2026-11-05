import QuartzCore
import UIKit

/// Main-thread time in the drag's own work, per frame, for FrameProbe's log (`Perf.begin` … `Perf.end`). Compiled in
/// only in Debug builds and in builds with the `PERF_PROBE` condition (the phone's measuring build, below); elsewhere
/// these are empty and inlined away. Counted only with `-frameProbe YES`.
enum PerfKey: Int, CaseIterable {
    /// CollectionDrag's / Home's `follow` (the copy and the gap, each frame or drop update).
    case follow
    /// The collection view's `layoutIfNeeded` in `follow`.
    case layout
    /// `moveGap`: the shown cells' transforms (and the spring's set-up).
    case moveGap
    /// A diffable snapshot applied (`apply`).
    case apply
    /// A cell configured (dequeued or reconfigured): its hosting configuration made.
    case configure
    /// A cell's layout attributes applied (`apply(_:)` on the cell).
    case cellApply
    /// A cell laid out (`layoutSubviews`: its hosting view, SwiftUI's update of the row).
    case cellLayout
    /// A cell measured for self-sizing (`preferredLayoutAttributesFitting`).
    case cellSize
    /// A drop session update (`dropSessionDidUpdate`).
    case update
    /// The probes' own work (FrameProbe, DragProbe's trace).
    case probe

    var name: String {
        switch self {
        case .follow: "follow"
        case .layout: "layout"
        case .moveGap: "moveGap"
        case .apply: "apply"
        case .configure: "configure"
        case .cellApply: "cellApply"
        case .cellLayout: "cellLayout"
        case .cellSize: "cellSize"
        case .update: "update"
        case .probe: "probe"
        }
    }
}

#if DEBUG || PERF_PROBE
@MainActor
enum Perf {
    static let on = UserDefaults.standard.bool(forKey: "frameProbe")
    fileprivate static var time = [CFTimeInterval](repeating: 0, count: PerfKey.allCases.count)
    fileprivate static var count = [Int](repeating: 0, count: PerfKey.allCases.count)
    /// Nested measures of one key count once (the outermost).
    private static var depth = [Int](repeating: 0, count: PerfKey.allCases.count)

    static func begin(_ k: PerfKey) -> CFTimeInterval {
        guard on else { return 0 }
        depth[k.rawValue] += 1
        return CACurrentMediaTime()
    }

    static func end(_ k: PerfKey, _ t0: CFTimeInterval) {
        guard on, t0 > 0 else { return }
        depth[k.rawValue] -= 1
        guard depth[k.rawValue] == 0 else { return }
        time[k.rawValue] += CACurrentMediaTime() - t0
        count[k.rawValue] += 1
    }

    static func measure<T>(_ k: PerfKey, _ body: () -> T) -> T {
        let t = begin(k)
        defer { end(k, t) }
        return body()
    }
}
#else
enum Perf {
    @inline(__always) static func begin(_ k: PerfKey) -> CFTimeInterval { 0 }
    @inline(__always) static func end(_ k: PerfKey, _ t0: CFTimeInterval) {}
    @inline(__always) static func measure<T>(_ k: PerfKey, _ body: () -> T) -> T { body() }
}
#endif

#if DEBUG || PERF_PROBE
/// `-frameProbe YES`, in Debug builds and in the phone's measuring build (`PERF_PROBE`, a Release build with the
/// condition added on the xcodebuild line: ios/Tools/perf/README.md). Never in a shipped build.
///
/// Every display frame from launch, to tmp/frame-trace.log in the app's container, one line each:
///   F <epoch s> <dt ms> <miss> <work ms> <commit ms> <pass ms> <touches> <ticks> [key=n/ms …]
/// - dt: since the last frame; miss: frames missed (the frame's timestamp past the last one's target, in frames).
/// - work: the main thread's run-loop passes that ended since the last frame, from waking to their before-waiting
///   (events, timers, display links, our code and, on iOS 26, UIKit's update cycle: layout, SwiftUI's hosting-cell
///   updates and the CA commit, run as a source at the frame's start); commit: what runs after that, in the run loop's
///   before-waiting observers (Core Animation's commit on older systems: about 0 here); pass: the longest pass. The
///   Perf buckets (`cellLayout`, `cellSize`, `configure`) tell UIKit's and SwiftUI's share of it from ours.
/// - touches: fingers down on the window (UIKit cancels them as a drag begins: the system has the touch then);
///   ticks: the drag's haptic ticks so far (one per new slot).
/// - key=n/ms: `Perf` buckets since the last frame (PerfKey), calls and main-thread ms.
/// Marks: "M <epoch s> <text>" (`mark`).
///
/// For FlowTests: the longest frame in the 1.2 s after the last touch UIKit cancelled (a drag's begin), as the
/// accessibility value of an element "frameProbe" ("dragWorst=287.6").
@MainActor
enum FrameProbe {
    private static var link: CADisplayLink?
    private static var last: CFTimeInterval = 0
    private static var lastTarget: CFTimeInterval = 0
    private static var woke: CFTimeInterval = 0
    private static var workEnd: CFTimeInterval = 0
    private static var work: CFTimeInterval = 0
    private static var commit: CFTimeInterval = 0
    private static var pass: CFTimeInterval = 0
    private static var lines: [String] = []
    private static var flushed: CFTimeInterval = 0
    static let epoch = Date().timeIntervalSince1970 - CACurrentMediaTime()
    private static var file: FileHandle?
    private static let disk = DispatchQueue(label: "frameProbe.disk", qos: .utility)
    fileprivate static var touches = 0
    /// The last finger's place in its window, while UIKit still delivers its touch (until a drag begins).
    static var touch: (point: CGPoint, window: UIWindow)?
    private static weak var watched: UIWindow?
    fileprivate static var cancelled: CFTimeInterval = 0
    fileprivate static var worst: CFTimeInterval = 0
    private static let marker: UIView = {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = true
        v.accessibilityIdentifier = "frameProbe"
        v.accessibilityValue = "dragWorst=-"
        return v
    }()

    static func install() {
        guard Perf.on, link == nil else { return }
        file = Trace.open("frame-trace.log")
        // The pass's phases: waking (first of all), before waiting ahead of Core Animation's commit (order 2000000)
        // and UIKit's layout, and before waiting after them all.
        func observe(_ a: CFRunLoopActivity, _ order: CFIndex, _ body: @escaping @MainActor (CFTimeInterval) -> Void) {
            let o = CFRunLoopObserverCreateWithHandler(nil, a.rawValue, true, order) { _, _ in
                let now = CACurrentMediaTime()
                MainActor.assumeIsolated { body(now) }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), o, .commonModes)
        }
        observe(.afterWaiting, CFIndex.min) { now in woke = now; workEnd = 0 }
        observe(.beforeWaiting, CFIndex.min) { now in
            guard woke > 0 else { return }
            workEnd = now
            work += now - woke
        }
        observe(.beforeWaiting, CFIndex.max) { now in
            guard woke > 0 else { return }
            if workEnd > 0 { commit += now - workEnd }
            pass = max(pass, now - woke)
            woke = 0
            workEnd = 0
        }
        let l = CADisplayLink(target: Fire.shared, selector: #selector(Fire.fire(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        let nc = NotificationCenter.default
        for n in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { _ in MainActor.assumeIsolated { flush() } }
        }
        mark("launch frameProbe" + (UserDefaults.standard.bool(forKey: "noKeyboardWarmUp") ? " noKeyboardWarmUp" : ""))
    }

    /// A line "M <epoch s> <text>" in the frame log.
    static func mark(_ s: String) {
        guard Perf.on, file != nil else { return }
        lines.append(String(format: "M %.4f ", CACurrentMediaTime() + epoch) + s)
    }

    fileprivate static func frame(_ l: CADisplayLink) {
        let t0 = CACurrentMediaTime()
        if watched == nil, let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            watched = w
            w.addGestureRecognizer(Fingers())
            w.addSubview(marker)
        }
        let t = l.timestamp
        if last > 0 {
            let miss = lastTarget > 0 && l.duration > 0 ? max(0, Int(((t - lastTarget) / l.duration).rounded())) : 0
            var s = String(format: "F %.4f %.2f %d %.2f %.2f %.2f %d %d", t + epoch, (t - last) * 1000, miss, work * 1000,
                           commit * 1000, pass * 1000, touches, DragProbe.shared.ticks)
            for k in PerfKey.allCases where Perf.count[k.rawValue] > 0 {
                s += String(format: " %@=%d/%.2f", k.name, Perf.count[k.rawValue], Perf.time[k.rawValue] * 1000)
            }
            lines.append(s)
        }
        for i in Perf.count.indices { Perf.count[i] = 0; Perf.time[i] = 0 }
        if cancelled > 0, last > 0 {
            if t - cancelled < 1.2 { worst = max(worst, t - last) } else {
                marker.accessibilityValue = String(format: "dragWorst=%.1f", worst * 1000)
                cancelled = 0
            }
        }
        last = t
        lastTarget = l.targetTimestamp
        work = 0
        commit = 0
        pass = 0
        if t - flushed > 1 { flush() }
        // This frame's own cost, in the next line.
        Perf.time[PerfKey.probe.rawValue] += CACurrentMediaTime() - t0
        Perf.count[PerfKey.probe.rawValue] += 1
    }

    private static func flush() {
        flushed = last
        guard !lines.isEmpty, let file else { return }
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        lines.removeAll(keepingCapacity: true)
        let f = Trace.Handle(file)
        disk.async { f.write(data) }
    }

    @MainActor private final class Fire: NSObject {
        static let shared = Fire()
        @objc func fire(_ l: CADisplayLink) { FrameProbe.frame(l) }
    }

    /// Counts the fingers down on the window; never recognizes, delays or cancels anything (it fails as the last finger
    /// lifts).
    private final class Fingers: UIGestureRecognizer, UIGestureRecognizerDelegate {
        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }
        override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent) {
            FrameProbe.touches += t.count
            seen(t)
        }
        override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent) { seen(t) }
        override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent) { lifted(t.count) }
        private func seen(_ t: Set<UITouch>) {
            if let u = t.first, let w = view as? UIWindow { FrameProbe.touch = (u.location(in: w), w) }
        }
        override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent) {
            FrameProbe.cancelled = CACurrentMediaTime()
            FrameProbe.worst = 0
            lifted(t.count)
        }
        private func lifted(_ n: Int) {
            FrameProbe.touches = max(0, FrameProbe.touches - n)
            if FrameProbe.touches == 0 {
                FrameProbe.touch = nil
                state = .failed
            }
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
    }
}

/// The probes' log files, in tmp/ of the app's container (appended to; devicectl copies them from the phone).
enum Trace {
    static func open(_ name: String) -> FileHandle? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        _ = try? h?.seekToEnd()
        return h
    }

    /// A file handle written to from the probes' disk queue only.
    struct Handle: @unchecked Sendable {
        let h: FileHandle
        init(_ h: FileHandle) { self.h = h }
        func write(_ d: Data) { h.write(d) }
    }
}
#endif
