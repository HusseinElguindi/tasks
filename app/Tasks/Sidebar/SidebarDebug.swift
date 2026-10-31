#if DEBUG
import AppKit
import Foundation

/// Debug aids for checking the sidebar without the screen or the real pointer (never compiled into release builds):
///
///     -debugArchiveOpen YES       the Archive group starts open
///     -debugCmdHints YES          ⌘1–⌘9 shown in place of the counts
///     -debugHover X,Y             hovers the sidebar at that window point (top-left origin), as the tracker would
///     -debugSidebarScript "<steps>"   runs semicolon-separated steps 1.5 s after launch, then quits:
///         size:W,H  down:X,Y  drag:X,Y  up:X,Y  click:X,Y  dbl:X,Y  move:X,Y (hover; "move:none" leaves)
///         key:CODE[:cmd|shift|alt|ctrl|cmdalt][:CHARS]  flags:cmd|none  type:TEXT  newlist  menu:X,Y
///         wait:MS  snap:/path.png  state:/path.txt (appends what's on screen, by presentation values)
///
/// Mouse and key events go straight to the window (`NSApp.sendEvent`), never through HID; `flags` goes through the
/// event queue so the held-⌘ monitor sees it.
extension SidebarView {
    func runDebugIfRequested() {
        let d = UserDefaults.standard
        if d.bool(forKey: "debugArchiveOpen") { ui.archiveOpen = true }
        if d.bool(forKey: "debugCmdHints") { ui.cmdHints = true }
        if let h = d.string(forKey: "debugHover") {
            let xy = h.split(separator: ",").compactMap { Double($0) }
            if xy.count == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    MainActor.assumeIsolated { self?.debugHover(at: CGPoint(x: xy[0], y: xy[1])) }
                }
            }
        }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-debugSidebarScript"), i + 1 < args.count else { return }
        let steps = args[i + 1].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            for step in steps {
                guard let self, let w = self.window else { break }
                let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
                let arg = parts.count > 1 ? parts[1] : ""
                let xy = arg.split(separator: ",").compactMap { Double($0) }
                let pt = xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
                switch parts[0] {
                case "size":
                    if let pt { w.setFrame(NSRect(origin: w.frame.origin, size: NSSize(width: pt.x, height: pt.y)), display: true) }
                case "down": if let pt { Self.mouse(w, .leftMouseDown, pt, count: 1) }
                case "drag": if let pt { Self.mouse(w, .leftMouseDragged, pt, count: 1) }
                case "up": if let pt { Self.mouse(w, .leftMouseUp, pt, count: 1) }
                case "click":
                    if let pt { Self.mouse(w, .leftMouseDown, pt, count: 1); Self.mouse(w, .leftMouseUp, pt, count: 1) }
                case "dbl":
                    if let pt {
                        Self.mouse(w, .leftMouseDown, pt, count: 1); Self.mouse(w, .leftMouseUp, pt, count: 1)
                        Self.mouse(w, .leftMouseDown, pt, count: 2); Self.mouse(w, .leftMouseUp, pt, count: 2)
                    }
                case "move": self.debugHover(at: pt)
                case "key": Self.key(w, arg)
                case "flags":
                    let flags: NSEvent.ModifierFlags = arg == "cmd" ? .command : []
                    if let e = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: w.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                                                isARepeat: false, keyCode: 55) {
                        NSApp.postEvent(e, atStart: false)
                    }
                case "type":
                    (w.firstResponder as? NSTextView)?.insertText(arg, replacementRange: NSRange(location: NSNotFound, length: 0))
                case "newlist":
                    WindowActions(store: self.store, window: self.ui).newList()
                case "menu":
                    if let pt {
                        let p = self.debugContentPoint(pt)
                        let m = self.contextMenu(at: p)
                        print("menu \(pt): \(m.map { $0.items.map { $0.isSeparatorItem ? "--" : $0.title + ($0.isEnabled ? "" : "(off)") } } ?? [])")
                    }
                case "dropover":
                    // A task drag from the list, as the task list would drive it: the target under the point, its look,
                    // and the frame the dropped copy would fly to.
                    if let pt {
                        let over = self.dropTarget(at: pt, dragged: self.ui.route.listID.map { Array(self.store.projection.openTasks(in: $0).ids.prefix(1)) } ?? [])
                        print("dropover \(pt): \(String(describing: over)) frame=\(String(describing: over.flatMap(self.rowFrame(for:))))")
                        self.ui.drag = .init(kind: .tasks(ids: [], group: self.ui.route.listID ?? ""), target: 0, over: over)
                    }
                case "dropclear":
                    self.ui.drag = nil
                case "scroll":
                    let doc = (self.subviews.first as? NSScrollView)?.documentView
                    doc?.scroll(NSPoint(x: 0, y: Double(arg) ?? 0))
                case "sidebar":
                    WindowActions(store: self.store, window: self.ui).toggleSidebar()
                case "ax":
                    let doc = (self.subviews.first as? NSScrollView)?.documentView
                    let kids = (doc?.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement }
                    print("ax \(doc?.accessibilityRole()?.rawValue ?? "-") '\(doc?.accessibilityLabel() ?? "")': " + kids.map {
                        "\($0.accessibilityRole()?.rawValue ?? "?"):\($0.accessibilityLabel() ?? "")\($0.accessibilityValue().map { "=\($0)" } ?? "")\($0.isAccessibilitySelected() ? "*" : "")"
                    }.joined(separator: ", "))
                case "archive", "unarchive":
                    let p = self.store.projection
                    if let id = p.allListIDs.first(where: { p.list($0)?.name == arg }) {
                        let a = WindowActions(store: self.store, window: self.ui)
                        if parts[0] == "archive" { a.archive(list: id) } else { a.unarchive(list: id) }
                    }
                case "wait":
                    try? await Task.sleep(for: .milliseconds(Int(arg) ?? 100))
                    continue
                case "snap":
                    Self.snapshot(w, to: arg)
                case "state":
                    let line = "--- \(String(format: "%.3f", CACurrentMediaTime()))\n" + self.debugState + "\n"
                    if let h = FileHandle(forWritingAtPath: arg) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
                    else { try? line.write(toFile: arg, atomically: true, encoding: .utf8) }
                default:
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            NSApp.terminate(nil)
        }
    }

    private func debugContentPoint(_ windowTopLeft: CGPoint) -> CGPoint {
        guard let w = window, let h = w.contentView?.bounds.height else { return .zero }
        return subviews.first.flatMap { ($0 as? NSScrollView)?.documentView }?.convert(NSPoint(x: windowTopLeft.x, y: h - windowTopLeft.y), from: nil) ?? .zero
    }

    private static func mouse(_ w: NSWindow, _ type: NSEvent.EventType, _ p: CGPoint, count: Int) {
        let h = w.contentView?.bounds.height ?? w.contentLayoutRect.height
        if let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: p.x, y: h - p.y), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil,
                                      eventNumber: 0, clickCount: count, pressure: type == .leftMouseUp ? 0 : 1) {
            NSApp.sendEvent(e)
        }
    }

    private static func key(_ w: NSWindow, _ arg: String) {
        let k = arg.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let code = UInt16(k[0]) else { return }
        var flags: NSEvent.ModifierFlags = []
        if k.count > 1 {
            if k[1].contains("cmd") { flags.insert(.command) }
            if k[1].contains("shift") { flags.insert(.shift) }
            if k[1].contains("alt") { flags.insert(.option) }
            if k[1].contains("ctrl") { flags.insert(.control) }
        }
        var chars: String = switch code {
        case 125: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case 126: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case 124: String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case 36: "\r"
        case 48: "\t"
        case 49: " "
        case 53: "\u{1b}"
        case 51: "\u{7f}"
        default: ""
        }
        if k.count > 2 { chars = k[2] }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                NSApp.sendEvent(e)
            }
        }
    }

    static func snapshot(_ w: NSWindow, to path: String) {
        guard let view = w.contentView?.superview ?? w.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
