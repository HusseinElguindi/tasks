#if DEBUG
import AppKit
import Foundation
import TasksCore

/// Debug aid for checking interactions without the screen (it can be locked): `-debugScript "<steps>"` runs
/// semicolon-separated steps 1.5 s after launch, posting events straight to the window (no HID), then quits.
///
///     click:X,Y   dbl:X,Y   cmdclick:X,Y   shiftclick:X,Y     (window points from the top left)
///     key:CODE[:cmd|shift|cmdshift]   wait:MS   snap:/path.png   log:/path.txt  (appends the selection and first responder)
///     psnap:/path.png   (the layers as on screen this frame, mid-animation)
///     hold:CODE:N[:cmd]   (the key held: its press, N auto-repeats from 525 ms, its release)
///     checkclick:TITLE   checkdbl:TITLE   (a click or a double-click on that task's checkbox)
///     chiphover:TITLE:when|deadline   (the pointer over that row's date)
///     glasssnap:/path.png   (what covers the window's glass, as alpha, plus /path.txt: `GlassDebug`)
///     hit:X,Y     (prints the view AppKit hit-tests there)   size:W,H   (resizes the window, keeping its top left)
///     drag:X1,Y1,X2,Y2[,STEPS]   (press, move in steps 16 ms apart, release)
///     down:X,Y   move:X1,Y1,X2,Y2[,STEPS]   up:X,Y   (the same, a step at a time, to hold a drag)
///     theme:system|dark|light   (Settings ▸ Theme)   palette:derived|rex   (Rex's palette from its base colours alone,
///     a change within one appearance, as another theme would be)   sys:dark|light|none   (stands in for the system appearance: the
///     app's own, which windows on System follow; none puts the real one back)   chrome:/path.txt   (appends the
///     window's appearance and the traffic lights' frames and states)   sidebar   (Show/Hide Sidebar)
///     picker:when|deadline   (opens the date popover for the selection)
///     type:TEXT   (types each character as a key press; \n and \t as Return and Tab)
///     mktask:TITLE|NOTES   (a new task with notes, in the open list or Inbox)
///     menukey:z|Z|ret|RET:/path.txt   (the main menu's ⌘z, or ⇧⌘z for Z, ⇧⌘↩ for RET, sent as with the window key; appends the item and
///     who took it)   event   (a pass of NSApp's event loop, as real input makes: it closes undo groups)
///     ncaret:A[,B]   (the notes take the keys with A..B selected; dcaret:A[,B] the detail pane's notes)   nbox:OFFSET   (toggles the checklist box there)
///     nboxclick:OFFSET   ntextclick:OFFSET   (a real click on that box, or that character, through the window)   nscroll:Y | nscroll:box:OFFSET   (scrolls the notes)
///     nlog:/path.txt   (appends the notes' text, selection, hidden marks, session and the task's stored notes)
///     settings   (opens Settings)   hidemain   (orders the main windows out)   windows:/path.txt   (appends each window,
///     whether it can become main, and `AppModel.hasVisibleWindow`)
///     newesc:MS   (+, then Esc MS ms later)   close   (the detail pane's ×: `closeDetail`)   focusdetail   (a press in the
///     detail pane before its button acts)
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
                    let flags: NSEvent.ModifierFlags = k.count > 1 ? (k[1] == "cmd" ? .command : k[1] == "shift" ? .shift
                                                                       : k[1] == "cmdshift" ? [.command, .shift] : []) : []
                    key(w, code: code, flags: flags)
                case "hold":
                    // hold:CODE:N[:cmd] — the key held down past the repeat delay: its press, N repeats (the first
                    // 525 ms later, one of System Settings' "Delay until repeat" steps, then 83 ms apart), its release.
                    let k = arg.split(separator: ":").map(String.init)
                    guard k.count >= 2, let code = UInt16(k[0]), let n = Int(k[1]) else { continue }
                    let flags: NSEvent.ModifierFlags = k.count > 2 && k[2] == "cmd" ? .command : []
                    key(w, code: code, flags: flags, phase: .down)
                    for i in 0..<n {
                        try? await Task.sleep(for: .milliseconds(i == 0 ? 525 : 83))
                        key(w, code: code, flags: flags, phase: .repeated)
                    }
                    key(w, code: code, flags: flags, phase: .up)
                case "chiphover":
                    // chiphover:<title>:when|deadline — the pointer over that date (its hover look and tooltip, §24).
                    let t = arg.split(separator: ":").map(String.init)
                    guard t.count == 2, let store = model.store,
                          let id = store.projection.allTaskIDs.sorted().first(where: { store.projection.task($0)?.title == t[0] }),
                          let c = window.taskList?.debugChipPoint(id, t[1] == "when" ? .when : .deadline) else { continue }
                    window.taskList?.debugHover(c)
                case "checkclick", "checkdbl":
                    // checkclick:<title> — a click on that task's checkbox through the list's own mouse path;
                    // checkdbl:<title> a double-click there.
                    guard let store = model.store,
                          let id = store.projection.allTaskIDs.sorted().first(where: { store.projection.task($0)?.title == arg }),
                          let c = window.taskList?.debugCheckPoint(id) else { print("checkclick: \(arg) not on screen"); continue }
                    click(w, x: c.x, y: c.y, count: 1, flags: [])
                    if parts[0] == "checkdbl" { click(w, x: c.x, y: c.y, count: 2, flags: []) }
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
                case "psnap":
                    presentationSnapshot(w, to: arg)
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
                case "palette":
                    model.debugDerivedTheme = arg == "derived"
                case "sys":
                    NSApp.appearance = arg == "dark" ? NSAppearance(named: .darkAqua) : arg == "light" ? NSAppearance(named: .aqua) : nil
                case "sync":
                    // The sync indicator (Support/DebugSync.swift).
                    guard let store = model.store else { continue }
                    if arg == "click" || arg.hasPrefix("footclick:") {
                        // SwiftUI's button sees the press and the release in separate turns.
                        // Through the window (not straight to the view, as `mouse` does while the app is inactive): the cloud
                        // takes the first click there, as a person's would.
                        let target = arg == "click" ? DebugSync.cloudPoint(window: window, store: store)
                            : window.sidebarView?.debugFootPoint(arg.hasSuffix("settings") ? .settings : .newList)
                        if let c = target {
                            // From the window's top (as `hit:` reads it), not the content layout rect's.
                            let p = NSPoint(x: c.x, y: (w.contentView?.superview?.bounds.height ?? w.frame.height) - c.y)
                            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                                if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                                    NSApp.sendEvent(e)
                                }
                                try? await Task.sleep(for: .milliseconds(80))
                            }
                        }
                    } else {
                        await DebugSync.step(arg, window: window, store: store)
                    }
                case "close":
                    // close — what the detail pane's × and its Esc do (`closeDetail`), for when a click can't reach a
                    // SwiftUI button (the window isn't key).
                    if let store = model.store { WindowActions(store: store, window: window).closeDetail() }
                case "focusdetail":
                    // focusdetail — what a press in the detail pane does before its button acts (DetailPane.press).
                    if window.focus != .detail { window.focus = .detail }
                    window.detailKeySink?.takeKeys()
                case "newesc":
                    // newesc:MS — + (a new task), then Esc MS ms later, without the 150 ms between steps
                    // (the detail pane left on screen after it closed: Scripts/repro-stuck-detail.sh).
                    if let store = model.store, let d = Int(arg) {
                        WindowActions(store: store, window: window).newTask()
                        try? await Task.sleep(for: .milliseconds(d))
                        key(w, code: 53, flags: [])
                    }
                case "act":
                    // The four views' actions and traces (Support/DebugViews.swift).
                    if let store = model.store { DebugViews.act(arg, window: window, store: store) }
                case "picker":
                    if let store = model.store { WindowActions(store: store, window: window).openPicker(arg == "deadline" ? .deadline : .when) }
                case "type":
                    for ch in arg.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t") {
                        if ch == "\n" { key(w, code: 36, flags: []) } else if ch == "\t" { key(w, code: 48, flags: []) } else { typeKey(w, String(ch)) }
                        try? await Task.sleep(for: .milliseconds(20))
                    }
                case "ncaret":
                    let v = arg.split(separator: ",").compactMap { Int($0) }
                    guard let n = notesView(w), let a = v.first else { continue }
                    w.makeFirstResponder(n)
                    n.setSelectedRange(NSRange(location: a, length: (v.count > 1 ? v[1] : a) - a))
                case "dcaret":
                    // dcaret:A[,B] — the same in the detail pane's notes, whatever notes the list pane shows.
                    let v = arg.split(separator: ",").compactMap { Int($0) }
                    guard let n = detailNotesView(w), let a = v.first else { continue }
                    w.makeFirstResponder(n)
                    n.setSelectedRange(NSRange(location: a, length: (v.count > 1 ? v[1] : a) - a))
                case "mktask":
                    // mktask:TITLE|NOTES (\\n for a newline): a task in the open list, or Inbox.
                    let parts = arg.split(separator: "|", maxSplits: 1).map(String.init)
                    let notes = parts.count > 1 ? parts[1].replacingOccurrences(of: "\\n", with: "\n") : ""
                    model.store?.createTask(title: parts[0], notes: notes, in: window.route.listID, when: nil, deadline: nil)
                case "nbox":
                    if let n = notesView(w), let at = Int(arg) { n.notes?.toggleBox(at) }
                case "nboxclick":
                    // nboxclick:OFFSET — a real press and release on the box there, queued for the run loop as a click
                    // comes (it's NSApp's current event, and NSWindow picks the first responder before the view's
                    // mouseDown), wherever the app is.
                    guard let n = notesView(w), let at = Int(arg), let c = boxCenter(n, at) else { continue }
                    clickQueued(w, n.convert(c, to: nil))
                case "ntextclick":
                    // ntextclick:OFFSET — the same real click, on the middle of the character there.
                    guard let n = notesView(w), let at = Int(arg), let lm = n.layoutManager, let tc = n.textContainer else { continue }
                    lm.ensureLayout(for: tc)
                    let g = lm.glyphRange(forCharacterRange: NSRange(location: at, length: 1), actualCharacterRange: nil)
                    let r = lm.boundingRect(forGlyphRange: g, in: tc)
                    clickQueued(w, n.convert(NSPoint(x: n.textContainerOrigin.x + r.midX, y: n.textContainerOrigin.y + r.midY), to: nil))
                case "nscroll":
                    // nscroll:Y — the notes' scroll view to Y (its clip view's top), or nscroll:box:OFFSET to put that box
                    // 40pt above the bottom of the view.
                    guard let n = notesView(w), let sv = n.enclosingScrollView else { continue }
                    var y = Double(arg) ?? 0
                    if arg.hasPrefix("box:"), let at = Int(arg.dropFirst(4)), let c = boxCenter(n, at) {
                        let inDoc = n.convert(c, to: sv.documentView)
                        y = (sv.documentView?.isFlipped ?? true) ? inDoc.y - sv.contentView.bounds.height + 40 : inDoc.y - 40
                    }
                    sv.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
                    sv.reflectScrolledClipView(sv.contentView)
                case "nbench":
                    if let n = notesView(w), let c = n.notes {
                        let line = c.benchmark() + "\n"
                        try? line.write(toFile: arg, atomically: true, encoding: .utf8)
                    }
                case "npaste":
                    // npaste:url:ADDRESS | npaste:text:TEXT | npaste:plain:TEXT | npaste:rtf — a private pasteboard,
                    // never the user's clipboard.
                    guard let n = notesView(w) else { continue }
                    let kv = arg.split(separator: ":", maxSplits: 1).map(String.init)
                    let pb = NSPasteboard(name: NSPasteboard.Name("tasks.debug.\(UUID().uuidString)"))
                    pb.clearContents()
                    let text = kv.count > 1 ? kv[1].replacingOccurrences(of: "\\n", with: "\n") : ""
                    if kv[0] == "rtf" {
                        let a = NSMutableAttributedString()
                        let body = NSFont.systemFont(ofSize: 12)
                        a.append(NSAttributedString(string: "Big title\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)]))
                        a.append(NSAttributedString(string: "Some ", attributes: [.font: body]))
                        a.append(NSAttributedString(string: "bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]))
                        a.append(NSAttributedString(string: " and a ", attributes: [.font: body]))
                        a.append(NSAttributedString(string: "link", attributes: [.font: body, .link: URL(string: "https://example.com/x")!]))
                        a.append(NSAttributedString(string: " and ", attributes: [.font: body]))
                        a.append(NSAttributedString(string: "mono", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]))
                        a.append(NSAttributedString(string: ".\n", attributes: [.font: body]))
                        let list = NSTextList(markerFormat: .disc, options: 0)
                        let ps = NSMutableParagraphStyle()
                        ps.textLists = [list]
                        for item in ["first", "second"] {
                            a.append(NSAttributedString(string: "\t•\t" + item + "\n", attributes: [.font: body, .paragraphStyle: ps]))
                        }
                        a.append(NSAttributedString(string: "After the list.", attributes: [.font: body]))
                        if let d = a.rtf(from: NSRange(location: 0, length: a.length), documentAttributes: [:]) { pb.setData(d, forType: .rtf) }
                        pb.setString(a.string, forType: .string)
                    } else {
                        pb.setString(text, forType: .string)
                    }
                    n.paste(plain: kv[0] == "plain", from: pb)
                    pb.releaseGlobally()
                case "nhover":
                    // nhover:X,Y in window points from the top left (y as the other steps take it), or none.
                    guard let n = notesView(w) else { continue }
                    let xy = arg.split(separator: ",").compactMap { Double($0) }
                    if xy.count == 2 {
                        let p = n.convert(NSPoint(x: xy[0], y: w.contentLayoutRect.height - xy[1]), from: nil)
                        n.notes?.hover(at: p)
                    } else {
                        n.notes?.hover(at: nil)
                    }
                case "nax":
                    guard let n = notesView(w) else { continue }
                    let boxes = (n.accessibilityChildren() ?? []).compactMap { $0 as? NotesBoxElement }
                        .map { "\($0.accessibilityLabel() ?? "")=\($0.accessibilityValue() as? Int ?? -1)" }
                    let line = "value=\((n.accessibilityValue() ?? "").debugDescription) boxes=\(boxes)\n"
                    try? line.write(toFile: arg, atomically: true, encoding: .utf8)
                case "undo", "redo":
                    // The first responder's undo (the notes' own while they have the keys, else the window's): a
                    // background app has no key window for the menu's action to find.
                    let um = w.firstResponder?.undoManager ?? w.undoManager
                    if parts[0] == "undo" { um?.undo() } else { um?.redo() }
                case "event":
                    // An application-defined event through NSApp's queue: a pass of the event loop, as real input makes.
                    if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                                  windowNumber: w.windowNumber, context: nil, subtype: 0, data1: 0, data2: 0) {
                        NSApp.postEvent(e, atStart: false)
                    }
                case "menukey":
                    // menukey:z|Z:/path.txt: the main menu's ⌘z (⇧⌘ for Z) run as AppKit would for a key window.
                    let a = arg.split(separator: ":", maxSplits: 1).map(String.init)
                    guard a.count == 2 else { continue }
                    append(menuKey(w, a[0]), to: a[1])
                case "nfrag":
                    // Each notes line's kind, characters and line fragment rects (container coordinates).
                    guard let n = notesView(w), let lm = n.layoutManager, let tc = n.textContainer else { continue }
                    lm.ensureLayout(for: tc)
                    var out = ""
                    let ns = n.string as NSString
                    for l in Markdown.parse(n.string).lines {
                        let r = NSRange(location: l.start, length: max(0, min(ns.length, l.end + 1) - l.start))
                        let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
                        var rects: [String] = []
                        if g.length > 0 {
                            lm.enumerateLineFragments(forGlyphRange: g) { rect, used, _, _, _ in rects.append("\(Int(rect.minY))+\(rect.height) used \(Int(used.minY))+\(used.height)") }
                        }
                        out += "\(l.index) \(l.kind) \(ns.substring(with: l.range).prefix(20).debugDescription) \(rects)\n"
                    }
                    try? out.write(toFile: arg, atomically: true, encoding: .utf8)
                case "nlog":
                    guard let n = notesView(w) else { continue }
                    let ts = n.textStorage!
                    var hidden: [String] = []
                    ts.enumerateAttribute(.mdHidden, in: NSRange(location: 0, length: ts.length)) { v, r, _ in
                        if v != nil { hidden.append((ts.string as NSString).substring(with: r).replacingOccurrences(of: "\n", with: "⏎")) }
                    }
                    let stored = window.selection.first.flatMap { model.store?.projection.task($0)?.notes } ?? "-"
                    let sel = n.selectedRange()
                    let scroll = n.enclosingScrollView.map { "\(Int($0.contentView.bounds.origin.y))" } ?? "-"
                    let line = "notes=\(n.string.debugDescription) sel=\(sel.location),\(sel.length) hidden=\(hidden) editing=\(window.detailEditing.map { "\($0)" } ?? "-") stored=\(stored.debugDescription) responder=\(w.firstResponder === n) inert=\(n.inert) group=\(n.undoManager?.groupingLevel ?? -1) scroll=\(scroll)\n"
                    if let h = FileHandle(forWritingAtPath: arg) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
                    else { try? line.write(toFile: arg, atomically: true, encoding: .utf8) }
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
                case "settings":
                    // Settings (⌘,), through the scene's `openSettings`.
                    window.openSettings?()
                case "hidemain":
                    // The main windows out of sight (ordered out, not closed), leaving Settings.
                    for m in NSApp.windows where m.contentView != nil && m.identifier?.rawValue.hasPrefix("main") == true { m.orderOut(nil) }
                case "windows":
                    // Each window and whether it counts as one for the periodic sync and the socket (AppModel.hasVisibleWindow).
                    let line = NSApp.windows.map { "\($0.identifier?.rawValue ?? "-") \(type(of: $0)) visible=\($0.isVisible) canBecomeMain=\($0.canBecomeMain)" }
                        .joined(separator: "; ") + " | hasVisibleWindow=\(AppModel.hasVisibleWindow)\n"
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

    /// A press and release at `p` (window coordinates) queued for the run loop, as real input comes: the press is NSApp's
    /// current event while it's sent, and the release waits for a tracking loop's `nextEvent` to take it.
    private static func clickQueued(_ w: NSWindow, _ p: NSPoint) {
        for t in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.postEvent(e, atStart: false)
            }
        }
    }

    /// The middle of the checklist box at character `at`, in the notes view's coordinates (§5: 12pt, 3.5 down).
    private static func boxCenter(_ n: NotesTextView, _ at: Int) -> NSPoint? {
        guard let lm = n.layoutManager as? NotesLayoutManager, let tc = n.textContainer,
              let l = Markdown.parse(n.string).lines.first(where: { $0.kind == .task && $0.box == at }) else { return nil }
        lm.ensureLayout(for: tc)
        guard let f = lm.fragment(l, first: true) else { return nil }
        return NSPoint(x: n.textContainerOrigin.x + CGFloat(l.level) * NotesStyle.column + 2 + 6,
                       y: n.textContainerOrigin.y + f.minY + 3.5 + 6)
    }

    /// The detail pane's notes: the one editor that isn't in a list.
    private static func detailNotesView(_ w: NSWindow) -> NotesTextView? {
        func find(_ v: NSView) -> NotesTextView? {
            if v is TaskListView { return nil }
            if let n = v as? NotesTextView { return n }
            for s in v.subviews { if let n = find(s) { return n } }
            return nil
        }
        return w.contentView.flatMap(find)
    }

    private static func notesView(_ w: NSWindow) -> NotesTextView? {
        func find(_ v: NSView) -> NotesTextView? {
            if let n = v as? NotesTextView { return n }
            for s in v.subviews { if let n = find(s) { return n } }
            return nil
        }
        return w.contentView.flatMap(find)
    }

    /// One character as a key press, to the first responder as `key` sends them.
    private static func typeKey(_ w: NSWindow, _ s: String) {
        for t in [NSEvent.EventType.keyDown, .keyUp] {
            guard let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: w.windowNumber, context: nil, characters: s, charactersIgnoringModifiers: s,
                                           isARepeat: false, keyCode: 0) else { continue }
            if NSApp.isActive { NSApp.sendEvent(e) } else if t == .keyDown { w.firstResponder?.keyDown(with: e) }
        }
    }

    enum KeyPhase { case press, down, repeated, up }

    /// A key press (down and up), or one phase of a held key.
    private static func key(_ w: NSWindow, code: UInt16, flags: NSEvent.ModifierFlags, phase: KeyPhase = .press) {
        let chars: String = switch code {
        case 125: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case 126: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case 123: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case 124: String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case 36: "\r"
        case 49: " "
        case 40: "k"
        case 53: "\u{1b}"
        case 48: flags.contains(.shift) ? "\u{19}" : "\t"
        case 51: "\u{7f}"
        case 45: "n"
        case 6: "z"
        case 0: "a"
        case 11: "b"
        case 34: "i"
        case 2: "d"
        default: ""
        }
        let types: [NSEvent.EventType] = switch phase {
        case .press: [.keyDown, .keyUp]
        case .down, .repeated: [.keyDown]
        case .up: [.keyUp]
        }
        for type in types {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: phase == .repeated, keyCode: code) {
                // In the background there's no key window to route to: straight to the first responder (menu key
                // equivalents don't work this way).
                // With ⌘, the window's views get it as a key equivalent first, as AppKit does.
                if NSApp.isActive { NSApp.sendEvent(e) } else if type == .keyDown, !(flags.contains(.command) && w.performKeyEquivalent(with: e)) {
                    w.firstResponder?.keyDown(with: e)
                }
            }
        }
    }

    private static func append(_ s: String, to path: String) {
        let line = s + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
        else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
    }

    /// The menu item a ⌘ key equivalent picks, sent as AppKit sends it with the window key: its own target, or the
    /// first in the first responder's chain (then the window's delegate, the app and its delegate) that takes the
    /// action. A background app has no key window, so the real menu can't find one. Returns what happened.
    private static func menuKey(_ w: NSWindow, _ name: String) -> String {
        // `ret` is ⌘↩ and `RET` ⇧⌘↩ (Zoom Pane, §29); a letter is itself, ⇧ when it's a capital.
        let key = name.lowercased() == "ret" ? "\r" : name
        let shift = name == "RET" || key != key.lowercased()
        func find(_ m: NSMenu) -> NSMenuItem? {
            for i in m.items {
                if let s = i.submenu, let f = find(s) { return f }
                let mask = i.keyEquivalentModifierMask
                let eqShift = mask.contains(.shift) || i.keyEquivalent != i.keyEquivalent.lowercased()
                if i.keyEquivalent.lowercased() == key.lowercased(), mask.contains(.command), eqShift == shift,
                   !mask.contains(.option), !mask.contains(.control) { return i }
            }
            return nil
        }
        guard let menu = NSApp.mainMenu, let item = find(menu) else { return "menukey \(key): no item" }
        guard let action = item.action else { return "menukey \(key): '\(item.title)' has no action" }
        menu.update()
        var handler: AnyObject? = item.target
        if handler == nil {
            var r: NSResponder? = w.firstResponder
            while let x = r, !x.responds(to: action) { r = x.nextResponder }
            handler = r
            for o in [w.delegate as AnyObject?, NSApp, NSApp.delegate as AnyObject?] where handler == nil {
                if let o, o.responds(to: action) { handler = o }
            }
        }
        var enabled = item.isEnabled
        let itemEnabled = item.isEnabled
        if let v = handler as? NSMenuItemValidation { enabled = enabled && v.validateMenuItem(item) }
        else if let v = handler as? NSUserInterfaceValidations { enabled = enabled && v.validateUserInterfaceItem(item) }
        var out = "menukey \(key): '\(item.title)' \(action) target=\(item.target.map { "\(type(of: $0))" } ?? "nil")"
        out += " handler=\(handler.map { "\(type(of: $0))" } ?? "none") enabled=\(enabled) (item \(itemEnabled))"
        out += " responder=\(w.firstResponder.map { "\(type(of: $0))" } ?? "none") um=\(w.firstResponder?.undoManager.map { "\($0.undoActionName)|\($0.canUndo)" } ?? "-")"
        func id(_ o: AnyObject?) -> String { o.map { String(UInt(bitPattern: ObjectIdentifier($0).hashValue) % 100000) } ?? "nil" }
        out += " ums: responder=\(id(w.firstResponder?.undoManager)) handler=\(id((handler as? NSResponder)?.undoManager)) window=\(id(w.undoManager))"
        let before = (w.firstResponder as? NSTextView)?.string
        if enabled, let handler { NSApp.sendAction(action, to: handler, from: item) }
        if let before { out += " text=\(before.debugDescription)→\(((w.firstResponder as? NSTextView)?.string ?? "-").debugDescription)" }
        return out
    }

    /// `psnap:/path.png`: the window's layers as they are on screen this frame, mid-animation (`snap` draws the model
    /// values, so a running animation doesn't show). Core Animation's own render: materials draw as their fallbacks.
    private static func presentationSnapshot(_ w: NSWindow, to path: String) {
        guard let view = w.contentView?.superview ?? w.contentView, let layer = view.layer else { return }
        let scale = w.backingScaleFactor, size = view.bounds.size
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        if layer.isGeometryFlipped || view.isFlipped {
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        (layer.presentation() ?? layer).render(in: ctx)
        guard let img = ctx.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func snapshot(_ w: NSWindow, to path: String) {
        guard let view = w.contentView?.superview ?? w.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
