#if DEBUG
import AppKit
import Foundation

/// Debug aid for checking interactions without the screen (it can be locked): `-debugScript "<steps>"` runs
/// semicolon-separated steps 1.5 s after launch, posting events straight to the window (no HID), then quits.
///
///     click:X,Y   dbl:X,Y   cmdclick:X,Y   shiftclick:X,Y     (window points from the top left)
///     key:CODE[:cmd|shift]   wait:MS   snap:/path.png   log:/path.txt  (appends the selection and first responder)
///     glasssnap:/path.png   (what covers the window's glass, as alpha, plus /path.txt: `GlassDebug`)
///     hit:X,Y     (prints the view AppKit hit-tests there)   size:W,H   (resizes the window, keeping its top left)
///     drag:X1,Y1,X2,Y2[,STEPS]   (press, move in steps 16 ms apart, release)
///     down:X,Y   move:X1,Y1,X2,Y2[,STEPS]   up:X,Y   (the same, a step at a time, to hold a drag)
///     theme:system|dark|light   (Settings ▸ Theme)   sys:dark|light|none   (stands in for the system appearance: the
///     app's own, which windows on System follow; none puts the real one back)   chrome:/path.txt   (appends the
///     window's appearance and the traffic lights' frames and states)   sidebar   (Show/Hide Sidebar)
///     picker:when|deadline   (opens the date popover for the selection)
///     watch:MS:/path.txt   (for MS ms, checks the traffic lights on every turn of the run loop, before each commit,
///     and appends how many turns they were out of place)
@MainActor
enum DebugScript {
    static func runIfRequested(_ window: WindowState, model: AppModel, _ describe: @escaping @MainActor () -> String) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-debugScript"), i + 1 < args.count else { return }
        let steps = args[i + 1].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            for step in steps {
                guard let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { break }
                let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
                let arg = parts.count > 1 ? parts[1] : ""
                switch parts[0] {
                case "click", "dbl", "cmdclick", "shiftclick":
                    let xy = arg.split(separator: ",").compactMap { Double($0) }
                    guard xy.count == 2 else { continue }
                    let flags: NSEvent.ModifierFlags = parts[0] == "cmdclick" ? .command : parts[0] == "shiftclick" ? .shift : []
                    click(w, x: xy[0], y: xy[1], count: 1, flags: flags)
                    if parts[0] == "dbl" { click(w, x: xy[0], y: xy[1], count: 2, flags: flags) }
                case "key":
                    let k = arg.split(separator: ":").map(String.init)
                    guard let code = UInt16(k[0]) else { continue }
                    let flags: NSEvent.ModifierFlags = k.count > 1 ? (k[1] == "cmd" ? .command : k[1] == "shift" ? .shift : []) : []
                    key(w, code: code, flags: flags)
                case "drag":
                    let v = arg.split(separator: ",").compactMap { Double($0) }
                    guard v.count >= 4 else { continue }
                    let n = v.count > 4 ? max(1, Int(v[4])) : 8
                    mouse(w, .leftMouseDown, x: v[0], y: v[1])
                    for i in 1...n {
                        try? await Task.sleep(for: .milliseconds(16))
                        let f = Double(i) / Double(n)
                        mouse(w, .leftMouseDragged, x: v[0] + (v[2] - v[0]) * f, y: v[1] + (v[3] - v[1]) * f)
                    }
                    mouse(w, .leftMouseUp, x: v[2], y: v[3])
                case "down", "up":
                    let xy = arg.split(separator: ",").compactMap { Double($0) }
                    guard xy.count == 2 else { continue }
                    mouse(w, parts[0] == "down" ? .leftMouseDown : .leftMouseUp, x: xy[0], y: xy[1])
                case "move":
                    // move:X1,Y1,X2,Y2[,STEPS]: the button stays down (between down: and up:).
                    let v = arg.split(separator: ",").compactMap { Double($0) }
                    guard v.count >= 4 else { continue }
                    let n = v.count > 4 ? max(1, Int(v[4])) : 8
                    for i in 1...n {
                        try? await Task.sleep(for: .milliseconds(16))
                        let f = Double(i) / Double(n)
                        mouse(w, .leftMouseDragged, x: v[0] + (v[2] - v[0]) * f, y: v[1] + (v[3] - v[1]) * f)
                    }
                case "size":
                    let wh = arg.split(separator: ",").compactMap { Double($0) }
                    guard wh.count == 2 else { continue }
                    w.setFrame(NSRect(x: w.frame.minX, y: w.frame.maxY - wh[1], width: wh[0], height: wh[1]), display: true)
                case "wait":
                    try? await Task.sleep(for: .milliseconds(Int(arg) ?? 100))
                case "snap":
                    snapshot(w, to: arg)
                case "glasssnap":
                    GlassDebug.snapshot(w, to: arg)
                case "hit":
                    // hit:X,Y — logs the view AppKit hit-tests at that window point (top-left origin).
                    let xy = arg.split(separator: ",").compactMap { Double($0) }
                    guard xy.count == 2, let frame = w.contentView?.superview else { continue }
                    let v = frame.hitTest(NSPoint(x: xy[0], y: frame.bounds.height - xy[1]))
                    print("hit \(xy[0]),\(xy[1]) -> \(v.map { "\(type(of: $0))" } ?? "nil")")
                case "theme":
                    if let t = AppModel.ThemeChoice(rawValue: arg) { model.theme = t }
                case "sys":
                    NSApp.appearance = arg == "dark" ? NSAppearance(named: .darkAqua) : arg == "light" ? NSAppearance(named: .aqua) : nil
                case "picker":
                    if let store = model.store { WindowActions(store: store, window: window).openPicker(arg == "deadline" ? .deadline : .when) }
                case "sidebar":
                    if let store = model.store { WindowActions(store: store, window: window).toggleSidebar() }
                case "watch":
                    let a = arg.split(separator: ":", maxSplits: 1).map(String.init)
                    guard a.count == 2, let ms = Int(a[0]) else { continue }
                    watchLights(w, ms: ms, path: a[1])
                case "chrome":
                    let line = chrome(w) + "\n"
                    if let h = FileHandle(forWritingAtPath: arg) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
                    else { try? line.write(toFile: arg, atomically: true, encoding: .utf8) }
                case "log":
                    let line = describe() + " firstResponder=" + (w.firstResponder.map { "\(type(of: $0))" } ?? "none") + "\n"
                    if let h = FileHandle(forWritingAtPath: arg) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
                    else { try? line.write(toFile: arg, atomically: true, encoding: .utf8) }
                default:
                    break
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
            NSApp.terminate(nil)
        }
    }

    /// Samples the traffic lights from a run loop observer (before waiting, i.e. just before Core Animation commits what
    /// this turn changed) for `ms` while the script goes on.
    private static func watchLights(_ w: NSWindow, ms: Int, path: String) {
        var turns = 0, off = 0, first = ""
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, _ in
            MainActor.assumeIsolated {
                guard let b = w.standardWindowButton(.closeButton), let c = b.superview?.superview else { return }
                turns += 1
                let r = b.convert(b.bounds, to: nil)
                let top = w.frame.height - r.maxY
                if c.frame.height != 50 || abs(top - 18) > 0.5 || abs(r.minX - 18) > 0.5 {
                    off += 1
                    if first.isEmpty { first = "container=\(Int(c.frame.height)) close=\(Int(r.minX)),\(Int(top))" }
                }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            let line = "watch turns=\(turns) off=\(off)\(first.isEmpty ? "" : " first: " + first)\n"
            if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
            else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
        }
    }

    /// The window's appearance and each traffic light: its frame in the window (top-left origin), whether it's hidden,
    /// and how many standard buttons of that kind are in the title bar (a second one would be drawn twice).
    private static func chrome(_ w: NSWindow) -> String {
        func name(_ a: NSAppearance?) -> String { a.map { $0.name.rawValue.replacingOccurrences(of: "NSAppearanceName", with: "") } ?? "nil" }
        var out = "window=\(name(w.appearance)) effective=\(name(w.effectiveAppearance)) app=\(name(NSApp.appearance))"
        out += " full=\(w.styleMask.contains(.fullScreen)) key=\(w.isKeyWindow) active=\(NSApp.isActive)"
        if let b = w.standardWindowButton(.closeButton) {
            out += " ids=\(UInt(bitPattern: ObjectIdentifier(b).hashValue) % 100000)/\(b.superview.map { UInt(bitPattern: ObjectIdentifier($0).hashValue) % 100000 } ?? 0)"
        }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let b = w.standardWindowButton(kind) else { out += " \(kind.rawValue)=none"; continue }
            let r = b.convert(b.bounds, to: nil)
            let top = w.frame.height - r.maxY
            let twins = b.superview?.subviews.filter { type(of: $0) == type(of: b) && ($0 as? NSButton)?.action == b.action }.count ?? 0
            out += " \(kind.rawValue)=\(Int(r.minX)),\(Int(top)) \(Int(r.width))x\(Int(r.height))\(b.isHidden ? " hidden" : "")\(twins > 1 ? " x\(twins)" : "") \(name(b.effectiveAppearance))"
        }
        if let c = w.standardWindowButton(.closeButton)?.superview?.superview { out += " container=\(Int(c.frame.height))" }
        return out
    }

    private static func click(_ w: NSWindow, x: Double, y: Double, count: Int, flags: NSEvent.ModifierFlags) {
        let p = NSPoint(x: x, y: w.contentLayoutRect.height - y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1) {
                post(e, in: w)
            }
        }
    }

    private static func mouse(_ w: NSWindow, _ type: NSEvent.EventType, x: Double, y: Double) {
        let p = NSPoint(x: x, y: w.contentLayoutRect.height - y)
        if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            post(e, in: w)
        }
    }

    /// While the app is active, through `NSApp.sendEvent` as a real event goes. In the background (someone else is using
    /// the Mac) the window would swallow the first press on a view that doesn't take the first mouse, so the press goes
    /// straight to the view under it and the drag and release to that same view, as NSWindow routes them (local event
    /// monitors don't see these).
    private static var pressed: NSView?
    private static func post(_ e: NSEvent, in w: NSWindow) {
        if NSApp.isActive { NSApp.sendEvent(e); return }
        switch e.type {
        case .leftMouseDown:
            pressed = w.contentView?.superview?.hitTest(e.locationInWindow)
            pressed?.mouseDown(with: e)
        case .leftMouseDragged: pressed?.mouseDragged(with: e)
        case .leftMouseUp:
            pressed?.mouseUp(with: e)
            pressed = nil
        default: NSApp.sendEvent(e)
        }
    }

    private static func key(_ w: NSWindow, code: UInt16, flags: NSEvent.ModifierFlags) {
        let chars: String = switch code {
        case 125: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case 126: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case 123: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case 124: String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case 36: "\r"
        case 49: " "
        case 53: "\u{1b}"
        case 45: "n"
        case 6: "z"
        case 0: "a"
        case 11: "b"
        case 2: "d"
        default: ""
        }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                // In the background there's no key window to route to: straight to the first responder (menu key
                // equivalents don't work this way).
                if NSApp.isActive { NSApp.sendEvent(e) } else if type == .keyDown { w.firstResponder?.keyDown(with: e) }
            }
        }
    }

    private static func snapshot(_ w: NSWindow, to path: String) {
        guard let view = w.contentView?.superview ?? w.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
