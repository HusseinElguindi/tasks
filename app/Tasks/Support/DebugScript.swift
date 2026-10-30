#if DEBUG
import AppKit
import Foundation

/// Debug aid for checking interactions without the screen (it can be locked): `-debugScript "<steps>"` runs
/// semicolon-separated steps 1.5 s after launch, posting events straight to the window (no HID), then quits.
///
///     click:X,Y   dbl:X,Y   cmdclick:X,Y   shiftclick:X,Y     (window points from the top left)
///     key:CODE[:cmd|shift]   wait:MS   snap:/path.png   log:/path.txt  (appends the selection and first responder)
///     hit:X,Y     (prints the view AppKit hit-tests there)   size:W,H   (resizes the window, keeping its top left)
@MainActor
enum DebugScript {
    static func runIfRequested(_ window: WindowState, _ describe: @escaping @MainActor () -> String) {
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
                case "size":
                    let wh = arg.split(separator: ",").compactMap { Double($0) }
                    guard wh.count == 2 else { continue }
                    w.setFrame(NSRect(x: w.frame.minX, y: w.frame.maxY - wh[1], width: wh[0], height: wh[1]), display: true)
                case "wait":
                    try? await Task.sleep(for: .milliseconds(Int(arg) ?? 100))
                case "snap":
                    snapshot(w, to: arg)
                case "hit":
                    // hit:X,Y — logs the view AppKit hit-tests at that window point (top-left origin).
                    let xy = arg.split(separator: ",").compactMap { Double($0) }
                    guard xy.count == 2, let frame = w.contentView?.superview else { continue }
                    let v = frame.hitTest(NSPoint(x: xy[0], y: frame.bounds.height - xy[1]))
                    print("hit \(xy[0]),\(xy[1]) -> \(v.map { "\(type(of: $0))" } ?? "nil")")
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

    private static func click(_ w: NSWindow, x: Double, y: Double, count: Int, flags: NSEvent.ModifierFlags) {
        let p = NSPoint(x: x, y: w.contentLayoutRect.height - y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1) {
                NSApp.sendEvent(e)
            }
        }
    }

    private static func key(_ w: NSWindow, code: UInt16, flags: NSEvent.ModifierFlags) {
        let chars: String = switch code {
        case 125: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case 126: String(UnicodeScalar(NSUpArrowFunctionKey)!)
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
                NSApp.sendEvent(e)
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
