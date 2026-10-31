#if DEBUG
import AppKit
import QuartzCore

/// Debug aid for v2 feedback 20: `act:frames:N:/f.txt[:snap]` records the next N display frames. Each frame writes the
/// layers with an animation running (owner view, layer class, keys), and every visible row's drawn state whenever it
/// differs from the frame before; with `snap`, also the window as /f.txt-<frame>.png. A list switch is instant when the
/// first frame after it already shows the new rows and nothing animates.
@MainActor
final class DebugFrames: NSObject {
    private static var current: DebugFrames?
    private let path: String
    private let window: NSWindow
    private let state: WindowState
    private let snaps: Bool
    private var left: Int
    private var frame = 0
    private var lastRows = ""
    private var link: CADisplayLink?
    private let t0 = CACurrentMediaTime()

    private init(path: String, frames: Int, window: NSWindow, state: WindowState, snaps: Bool) {
        self.path = path
        self.window = window
        self.state = state
        self.snaps = snaps
        left = frames
    }

    static func start(_ arg: String, window w: WindowState) {
        let a = arg.split(separator: ":").map(String.init)
        guard a.count >= 2, let n = Int(a[0]), let win = w.nsWindow, let view = win.contentView else { return }
        try? "".write(toFile: a[1], atomically: true, encoding: .utf8)
        let r = DebugFrames(path: a[1], frames: n, window: win, state: w, snaps: a.count > 2 && a[2] == "snap")
        current = r
        r.record()
        let l = view.displayLink(target: r, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        r.link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        frame += 1
        record()
        left -= 1
        if left <= 0 {
            l.invalidate()
            link = nil
            DebugFrames.current = nil
        }
    }

    private func record() {
        var anims: [String] = []
        if let root = window.contentView?.superview?.layer { walk(root, &anims) }
        let rows = state.taskList?.debugFrameRows() ?? ""
        var line = String(format: "f%d %.1fms anims=%d", frame, (CACurrentMediaTime() - t0) * 1000, anims.count)
        if !anims.isEmpty { line += " " + anims.prefix(30).joined(separator: " ") }
        if rows != lastRows {
            line += "\n" + rows
            lastRows = rows
        }
        let l = line + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(l.utf8)); h.closeFile() }
        if snaps, let v = window.contentView?.superview ?? window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + "-\(frame).png"))
        }
    }

    private func walk(_ l: CALayer, _ out: inout [String]) {
        if let keys = l.animationKeys(), !keys.isEmpty {
            out.append("\(owner(l))>\(type(of: l)):\(keys.joined(separator: ","))")
        }
        l.sublayers?.forEach { walk($0, &out) }
    }

    /// The nearest view that owns this layer or one above it.
    private func owner(_ l: CALayer) -> String {
        var x: CALayer? = l
        while let c = x {
            if let v = c.delegate as? NSView { return "\(type(of: v))" }
            x = c.superlayer
        }
        return "-"
    }
}
#endif
