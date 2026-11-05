#if DEBUG
import QuartzCore
import UIKit

/// Debug only. `-frameProbe YES` (measuring by hand): every display frame from launch, to tmp/frame-trace.log in the
/// app's container, one line each: "F <epoch> <dt ms> <busy ms> <touches> <ticks>": the time since the last frame, the
/// main thread's longest stretch of work since then (a run loop pass, from waking to waiting again), the fingers down,
/// and the drag's haptic ticks so far (DragProbe's: one per new slot). And for FlowTests: the longest frame in the
/// 1.2 s after the last touch UIKit cancelled (a drag's begin), as the accessibility value of an element "frameProbe"
/// ("dragWorst=287.6").
@MainActor
enum FrameProbe {
    private static var link: CADisplayLink?
    private static var last: CFTimeInterval = 0
    private static var woke: CFTimeInterval = 0
    private static var busy: CFTimeInterval = 0
    private static var lines: [String] = []
    private static let epoch = Date().timeIntervalSince1970 - CACurrentMediaTime()
    private static var file: FileHandle?
    fileprivate static var touches = 0
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
        guard UserDefaults.standard.bool(forKey: "frameProbe"), link == nil else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("frame-trace.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        file = try? FileHandle(forWritingTo: url)
        _ = try? file?.seekToEnd()
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue
            | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, activity in
            let now = CACurrentMediaTime()
            MainActor.assumeIsolated {
                if activity == .afterWaiting { woke = now } else if woke > 0 { busy = max(busy, now - woke); woke = 0 }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        let l = CADisplayLink(target: Fire.shared, selector: #selector(Fire.fire(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    fileprivate static func frame(_ l: CADisplayLink) {
        if watched == nil, let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            watched = w
            w.addGestureRecognizer(Fingers())
            w.addSubview(marker)
        }
        let t = l.timestamp
        // A pass still under way (this one) counts up to now.
        let now = CACurrentMediaTime()
        let b = max(busy, woke > 0 ? now - woke : 0)
        if last > 0 {
            lines.append(String(format: "F %.4f %.2f %.2f %d %d", t + epoch, (t - last) * 1000, b * 1000, touches, DragProbe.shared.ticks))
        }
        if cancelled > 0, last > 0 {
            if t - cancelled < 1.2 { worst = max(worst, t - last) } else {
                marker.accessibilityValue = String(format: "dragWorst=%.1f", worst * 1000)
                cancelled = 0
            }
        }
        last = t
        busy = 0
        if woke > 0 { woke = now }
        if lines.count >= 60 {
            file?.write(Data((lines.joined(separator: "\n") + "\n").utf8))
            lines.removeAll()
        }
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
        override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent) { FrameProbe.touches += t.count }
        override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent) { lifted(t.count) }
        override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent) {
            FrameProbe.cancelled = CACurrentMediaTime()
            FrameProbe.worst = 0
            lifted(t.count)
        }
        private func lifted(_ n: Int) {
            FrameProbe.touches = max(0, FrameProbe.touches - n)
            if FrameProbe.touches == 0 { state = .failed }
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
    }
}
#endif
