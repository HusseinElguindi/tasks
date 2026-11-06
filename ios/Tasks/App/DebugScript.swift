#if DEBUG || PERF_PROBE
import SwiftUI
import TasksCore
import UIKit

/// A debug aid for repros without XCUITest, as the Mac's `-debugScript` (app/Tasks/Support/DebugScript.swift), in Debug
/// builds and the phone's measuring build (`PERF_PROBE`) only: a shipped Release build has none of it. Launched with
/// `-debugScript "<steps>"` (or `-debugScriptFile <path>`, from the app's container home, for a long script), the steps
/// run one after another 1.5 s after launch. Steps are separated by `;` or a new line (`\;` is a semicolon in a step's
/// text); in a file, a line starting with `#` is a comment. The host's side, and examples: ios/Tools/script/README.md.
///
/// **What it can't do.** iOS has no public way for an app to make touches. So the drag steps drive our own press's
/// phases (`PressDrag`: lift, moved, release) at a scripted finger, through the same calls its action makes, on the
/// task lists' `CollectionDrag` and Home's controller: the copy, the gap, the slots, the fold, the landing and the write
/// are the app's own. But UIKit never sees a touch: the row's long-press menu, its SwiftUI buttons, swipes, scrolling
/// by pan and gesture arbitration are out of reach (XCUITest covers those). Editing starts through the app's own calls
/// (a heading's Rename and Edit Notes, a list's Edit Notes, a task's details), and the typing goes to the first
/// responder as `insertText` and `deleteBackward`, as the keyboard's do, without the keyboard's own machinery.
///
/// ROW: a task's, heading's or list's title, its id, or a list item's id ("h:<id>", "header"). A row is looked up on
/// the screen shown (a list, or Home); `edit` also finds it in the model.
///
///     drag:ROW,DY[,STEPS,MS]   press ROW's middle, hold 0.35 s (the lift), move DY pt in STEPS (10) moves MS (16) ms
///                              apart, let go
///     down:ROW   move:DY[,STEPS,MS]   up   cancel      (the same a phase at a time; cancel: the touch is taken away)
///     edit:ROW[:notes|:title]  starts typing a heading's name (Rename) or its notes (Edit Notes), a list's notes
///                              (`edit:header:notes`, or its name) or a task's title or notes (its details open)
///     type:TEXT                each character as `insertText` on the first responder (\n is Return, \t a tab, \\ a \)
///     ret   del[:N]            Return; N (1) deleteBackward
///     caret:N                  the caret to character N of the field (-N: N before its end)
///     done                     the list's Done (the draft ends and writes), or the details' Done
///     open:LIST   home   collapse:HEADING   undo   redo   wait:MS
///     snap:NAME                the window as a PNG (drawHierarchy, afterScreenUpdates false): NAME.png
///     log:NAME                 appends to NAME.txt: the drag probe's fields and the drag's state, the field being typed
///                              into (its text, selection and caret rect), and the shown rows' frames
///     frames:MS[:NAME]         for MS ms, each display frame's rows (as drawn: presentation layers), caret, and the field
///                              and its views up to its cell (as drawn, after "||"), to NAME.txt
///                              (frames)
///     film:MS[:NAME]           the same, in the background: the next steps run while it records (wait it out before
///                              quit) (film)
///     quit                     the app exits (after the done marker is written)
///
/// Output, in the app container's tmp/script/ (emptied at launch): run.txt (each step, ms from the first, and any
/// error), the snaps and logs, and `done` once the script has run: "<token> ok" or "<token> errors=N", the token from
/// `-debugScriptToken` (the host's, so it never reads a marker from an earlier run); also an element "debugScript" with
/// the marker as its value and the folder's path as its label, for a UI test. Window points throughout.
@MainActor
enum DebugScript {
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("script", isDirectory: true) }

    static func runIfRequested(_ app: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        var text: String?
        if let i = args.firstIndex(of: "-debugScript"), i + 1 < args.count {
            text = args[i + 1]
        } else if let i = args.firstIndex(of: "-debugScriptFile"), i + 1 < args.count {
            let path = args[i + 1]
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(path)
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        guard let text else { return }
        let token = args.firstIndex(of: "-debugScriptToken").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "-"
        let fm = FileManager.default
        try? fm.removeItem(at: directory)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let runner = ScriptRunner(app: app, token: token)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            await runner.run(steps(text))
        }
    }

    /// The steps: split at `;` and new lines (not at `\;`), trimmed; blank ones and `#` comments dropped.
    static func steps(_ text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var escaped = false
        for c in text {
            if escaped {
                cur += c == ";" ? ";" : "\\" + String(c)
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == ";" || c.isNewline {
                out.append(cur)
                cur = ""
            } else {
                cur.append(c)
            }
        }
        if escaped { cur += "\\" }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// A step's text: \n, \t and \\ (a typed `\;` is already a semicolon).
    static func unescape(_ s: String) -> String {
        var out = ""
        var escaped = false
        for c in s {
            if escaped {
                switch c {
                case "n": out += "\n"
                case "t": out += "\t"
                default: out.append(c)
                }
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else {
                out.append(c)
            }
        }
        return out
    }
}

/// A screen a script can see: a task list's controller or Home's (their files' `ScriptScreen` extensions).
@MainActor
protocol ScriptScreen: AnyObject {
    var scriptList: UICollectionView { get }
    var scriptItems: [String] { get }
    func scriptIndexPath(_ id: String) -> IndexPath?
    /// The item a script's ROW names on this screen.
    func scriptItem(_ row: String) -> String?
    /// A phase of our press at the scripted finger (in the window); `.possible` is the touch-down.
    func scriptPress(_ phase: UIGestureRecognizer.State, at p: CGPoint?)
    var scriptState: String { get }
}

enum ScriptFormat {
    static func n(_ v: CGFloat) -> String { String(format: "%.1f", v) }
    static func rect(_ r: CGRect) -> String { "\(n(r.minX)),\(n(r.minY)),\(n(r.width)),\(n(r.height))" }
    /// Text on one line: new lines as \n.
    static func line(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
    }
}

@MainActor
private final class ScriptLines {
    var v: [String]
    init(_ v: [String]) { self.v = v }
}

@MainActor
final class ScriptRunner {
    let app: AppModel
    let token: String
    private var errors = 0
    private var t0 = CACurrentMediaTime()
    /// The scripted finger, in the window, and the screen it's pressing on.
    private var finger: CGPoint?
    private weak var pressing: (any ScriptScreen)?

    init(app: AppModel, token: String) {
        self.app = app
        self.token = token
    }

    private var dir: URL { DebugScript.directory }

    func run(_ steps: [String]) async {
        t0 = CACurrentMediaTime()
        note("start \(steps.count) steps token=\(token)")
        var quit = false
        for step in steps {
            note("> " + step)
            let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
            let arg = parts.count > 1 ? parts[1] : ""
            switch parts[0] {
            case "drag": await drag(arg)
            case "down": await down(arg)
            case "move": await move(arg)
            case "up": up(.ended)
            case "cancel": up(.cancelled)
            case "edit": await edit(arg)
            case "type": type(DebugScript.unescape(arg))
            case "ret": type("\n")
            case "del":
                guard let r = responder() as? UIKeyInput else { fail("del: nothing is being typed into"); break }
                for _ in 0..<max(1, Int(arg) ?? 1) { r.deleteBackward() }
            case "caret": caret(Int(arg) ?? 0)
            case "done": done()
            case "open": await open(arg)
            case "home":
                app.path = []
                try? await Task.sleep(for: .milliseconds(600))
            case "collapse":
                guard let id = task(arg), app.isHeading(id) else { fail("collapse: no heading \(arg)"); break }
                app.toggleCollapse(id)
            case "undo": app.performUndo()
            case "redo": app.performRedo()
            case "wait": try? await Task.sleep(for: .milliseconds(Int(arg) ?? 100))
            case "snap": snap(arg.isEmpty ? "snap" : arg)
            case "log": write(state(), to: arg.isEmpty ? "log" : arg)
            case "frames":
                let a = arg.split(separator: ":", maxSplits: 1).map(String.init)
                await frames(Int(a.first ?? "") ?? 500, to: a.count > 1 ? a[1] : "frames")
            case "film":
                let a = arg.split(separator: ":", maxSplits: 1).map(String.init)
                Task { await frames(Int(a.first ?? "") ?? 500, to: a.count > 1 ? a[1] : "film") }
            case "quit": quit = true
            default: fail("unknown step")
            }
            if quit { break }
            // A turn of the run loop: SwiftUI's updates from this step land before the next.
            await Task.yield()
        }
        if finger != nil { up(.cancelled) }
        note("end errors=\(errors)")
        let marker = "\(token) \(errors == 0 ? "ok" : "errors=\(errors)")"
        try? Data((marker + "\n").utf8).write(to: dir.appendingPathComponent("done"))
        // For a UI test (DebugScriptTests): the marker as an element's value, and the output's folder as its label.
        if let w = window {
            let v = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            v.isUserInteractionEnabled = false
            v.isAccessibilityElement = true
            v.accessibilityIdentifier = "debugScript"
            v.accessibilityLabel = dir.path
            v.accessibilityValue = marker
            w.addSubview(v)
        }
        if quit {
            // The probes write their logs as the app leaves the foreground.
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            try? await Task.sleep(for: .milliseconds(300))
            exit(0)
        }
    }

    // MARK: Output

    private func ms() -> String { String(format: "%.0f", (CACurrentMediaTime() - t0) * 1000) }

    private func note(_ s: String) { write(ms() + " " + s, to: "run") }

    private func fail(_ s: String) {
        errors += 1
        note("ERR " + s)
    }

    private func write(_ s: String, to name: String) {
        let url = dir.appendingPathComponent(name + ".txt")
        let data = Data((s.hasSuffix("\n") ? s : s + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    private var window: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    private func snap(_ name: String) {
        guard let w = window else { fail("snap: no window"); return }
        let image = UIGraphicsImageRenderer(bounds: w.bounds).image { _ in _ = w.drawHierarchy(in: w.bounds, afterScreenUpdates: false) }
        guard let png = image.pngData() else { fail("snap: no image"); return }
        try? png.write(to: dir.appendingPathComponent(name + ".png"))
    }

    // MARK: Screens and rows

    /// The screen shown: the top list's controller, or Home's.
    private func screen() -> (any ScriptScreen)? {
        guard let root = window?.rootViewController else { return nil }
        var found: [any ScriptScreen] = []
        func walk(_ vc: UIViewController) {
            if let s = vc as? any ScriptScreen, vc.viewIfLoaded?.window != nil { found.append(s) }
            vc.children.forEach(walk)
            if let p = vc.presentedViewController { walk(p) }
        }
        walk(root)
        let shown = app.shown
        if let t = found.first(where: { ($0 as? TaskCollectionController)?.source == shown && shown != nil }) { return t }
        if shown == nil, let h = found.first(where: { $0 is HomeCollectionController }) { return h }
        return found.last
    }

    /// ROW's middle in the window, on the screen shown, scrolled into view if it isn't.
    private func point(_ row: String) -> (any ScriptScreen, CGPoint)? {
        guard let s = screen() else { fail("no list on screen"); return nil }
        guard let id = s.scriptItem(row), let ip = s.scriptIndexPath(id) else { fail("no row \(row)"); return nil }
        let cv = s.scriptList
        if cv.cellForItem(at: ip) == nil || !cv.bounds.contains(cv.cellForItem(at: ip)!.frame) {
            cv.scrollToItem(at: ip, at: .centeredVertically, animated: false)
            cv.layoutIfNeeded()
        }
        guard let a = cv.layoutAttributesForItem(at: ip) else { fail("no frame for \(row)"); return nil }
        let f = cv.convert(a.frame, to: nil)
        return (s, CGPoint(x: f.midX, y: f.midY))
    }

    /// A task or heading by its id or title (the shown list's first, live before deleted).
    private func task(_ row: String) -> EntityID? {
        var r = row
        for p in ["t:", "h:", "n:"] where r.hasPrefix(p) { r = String(r.dropFirst(2)) }
        if app.task(r) != nil { return r }
        let shownList: EntityID? = if case let .list(l)? = app.shown { l } else { nil }
        let all = app.projection.allTaskIDs.sorted().compactMap(app.task).filter { $0.title == r }
        let best = all.sorted { a, b in
            let ka = (a.list == shownList ? 0 : 1, app.isTrashed(a) ? 1 : 0), kb = (b.list == shownList ? 0 : 1, app.isTrashed(b) ? 1 : 0)
            return ka < kb
        }
        return best.first?.id
    }

    /// A list by its id, sample short name or name ("header": the one shown).
    private func list(_ row: String) -> EntityID? {
        if row == "header", case let .list(l)? = app.shown { return l }
        let id = SampleData.listID(row, in: app.projection)
        if app.list(id) != nil { return id }
        return app.activeLists.first { $0.name == row }?.id
    }

    // MARK: The press

    private func drag(_ arg: String) async {
        // ROW,DY[,STEPS,MS]: the numbers from the right, so a title may hold commas.
        var parts = arg.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        var nums: [String] = []
        while parts.count > 1, nums.count < 3, Double(parts.last!) != nil { nums.insert(parts.removeLast(), at: 0) }
        guard !nums.isEmpty else { fail("drag: no DY"); return }
        await down(parts.joined(separator: ","))
        guard finger != nil else { return }
        await move(nums.joined(separator: ","))
        up(.ended)
    }

    private func down(_ row: String) async {
        if finger != nil { up(.cancelled) }
        guard let (s, p) = point(row) else { return }
        finger = p
        pressing = s
        s.scriptPress(.possible, at: p)
        try? await Task.sleep(for: .milliseconds(Int(PressDrag.hold * 1000)))
        s.scriptPress(.began, at: p)
    }

    private func move(_ arg: String) async {
        let v = arg.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard let dy = v.first, let start = finger, let s = pressing else { fail("move: no finger down"); return }
        let n = v.count > 1 ? max(1, Int(v[1])) : 10
        let gap = v.count > 2 ? max(1, Int(v[2])) : 16
        for i in 1...n {
            try? await Task.sleep(for: .milliseconds(gap))
            let p = CGPoint(x: start.x, y: start.y + dy * Double(i) / Double(n))
            finger = p
            s.scriptPress(.changed, at: p)
        }
    }

    private func up(_ phase: UIGestureRecognizer.State) {
        guard let p = finger, let s = pressing else { fail("up: no finger down"); return }
        s.scriptPress(phase, at: p)
        finger = nil
        pressing = nil
    }

    // MARK: Editing

    private func edit(_ arg: String) async {
        var row = arg, notes = false
        if let r = arg.range(of: ":", options: .backwards) {
            let what = arg[r.upperBound...]
            if what == "notes" || what == "title" {
                notes = what == "notes"
                row = String(arg[..<r.lowerBound])
            }
        }
        if let id = task(row), let t = app.task(id) {
            if t.isHeading {
                if app.shown != .list(t.list) { await open(t.list) }
                if notes { app.editHeadingNotes(id) } else { app.renameHeading(id) }
            } else {
                app.detailTask = id
                guard let field = await detailField(notes: notes) else { fail("edit: no field in the details"); return }
                _ = field.becomeFirstResponder()
            }
        } else if let l = list(row) {
            if app.shown != .list(l) { await open(l) }
            if notes { app.editListNotes(l) } else { app.listEditor = AppModel.ListEditor(listID: l, name: app.list(l)?.name ?? "") }
        } else {
            fail("edit: no task, heading or list \(row)")
            return
        }
        // Until the field has the caret (the app focuses it once its row or sheet is up).
        for _ in 0..<60 {
            if responder() != nil { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        fail("edit: no field took the caret")
    }

    /// The details' title (the upper text view) or notes (the lower), once the sheet is up.
    private func detailField(notes: Bool) async -> UIView? {
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(50))
            guard let w = window, let sheet = w.rootViewController?.presentedViewController?.viewIfLoaded else { continue }
            let fields = views(in: sheet).filter { ($0 is UITextView || $0 is UITextField) && !$0.isHidden }
                .sorted { $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY }
            if fields.count >= 2 { return notes ? fields[1] : fields[0] }
        }
        return nil
    }

    private func views(in v: UIView) -> [UIView] { [v] + v.subviews.flatMap(views(in:)) }

    /// The view the keys go to.
    private func responder() -> UIView? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for w in scenes.flatMap(\.windows) {
            if let r = views(in: w).first(where: \.isFirstResponder) { return r }
        }
        return nil
    }

    private func type(_ text: String) {
        guard let r = responder() as? UIKeyInput else { fail("type: nothing is being typed into"); return }
        for c in text { r.insertText(String(c)) }
    }

    private func caret(_ n: Int) {
        guard let t = responder() as? UITextInput else { fail("caret: nothing is being typed into"); return }
        let length = t.offset(from: t.beginningOfDocument, to: t.endOfDocument)
        let at = max(0, min(length, n < 0 ? length + n : n))
        guard let p = t.position(from: t.beginningOfDocument, offset: at) else { fail("caret: no place \(n)"); return }
        t.selectedTextRange = t.textRange(from: p, to: p)
    }

    private func done() {
        if app.draft != nil {
            app.endDraft()
        } else {
            responder()?.resignFirstResponder()
            app.detailTask = nil
            app.listEditor = nil
        }
    }

    private func open(_ row: String) async {
        let id = list(row) ?? row
        if let s = Source(id: row), app.list(id) == nil { app.open(s) } else { app.open(.list(id)) }
        // The push.
        try? await Task.sleep(for: .milliseconds(600))
    }

    // MARK: State

    /// The caret's rect in the window, the text and the selection of the field being typed into.
    private func field() -> String {
        guard let r = responder() else { return "field=-" }
        var s = "field=\(Swift.type(of: r))"
        if let t = r as? UITextInput, let range = t.selectedTextRange {
            let start = t.offset(from: t.beginningOfDocument, to: range.start)
            let len = t.offset(from: range.start, to: range.end)
            s += " sel=\(start),\(len) caret=\(ScriptFormat.rect(r.convert(t.caretRect(for: range.end), to: nil)))"
        }
        let text = (r as? UITextView)?.text ?? (r as? UITextField)?.text ?? ""
        s += " frame=\(ScriptFormat.rect(r.convert(r.bounds, to: nil))) text=\"\(ScriptFormat.line(text))\""
        if let sv = r as? UIScrollView { s += " off=\(ScriptFormat.n(sv.contentOffset.y)) size=\(ScriptFormat.n(sv.contentSize.height))" }
        return s
    }

    /// The shown rows, in order: item, frame in the window (as laid out: `drawn`, its presentation layer's).
    private func rows(drawn: Bool) -> String {
        guard let s = screen() else { return "rows=-" }
        let cv = s.scriptList
        let pb = (drawn ? cv.layer.presentation() ?? cv.layer : cv.layer).bounds.origin
        let shift = CGPoint(x: cv.bounds.minX - pb.x, y: cv.bounds.minY - pb.y)
        let items = s.scriptItems
        let cells = cv.indexPathsForVisibleItems.sorted().compactMap { ip -> String? in
            guard ip.item < items.count, let c = cv.cellForItem(at: ip) else { return nil }
            let f = drawn ? (c.layer.presentation()?.frame ?? c.frame) : c.frame
            let hidden = c.isHidden || c.contentView.alpha < 0.01 ? " hidden" : ""
            return "  \(items[ip.item]) \(ScriptFormat.rect(cv.convert(f.offsetBy(dx: shift.x, dy: shift.y), to: nil)))\(hidden)"
        }
        return "off=\(ScriptFormat.n(cv.contentOffset.y)) rows=\(cells.count)\n" + cells.joined(separator: "\n")
    }

    private func state() -> String {
        let draft = app.draft.map { "\($0.kind) title=\"\(ScriptFormat.line($0.title))\"" } ?? "-"
        return """
        == \(ms()) ms screen=\(app.shown?.id ?? "home") draft=\(draft)
        probe \(DragProbe.shared.summary)
        \(screen()?.scriptState ?? "drag=-")
        \(field())
        \(rows(drawn: false))
        """
    }

    /// The field being typed into and its views up to its cell, each as drawn (presentation layers) in the window, with
    /// the field's own offset: which of them moves when its text does.
    private func fieldChain() -> String {
        guard let r = responder(), let w = r.window else { return "" }
        let wl = w.layer.presentation() ?? w.layer
        var parts: [String] = []
        var v: UIView? = r
        while let cur = v, !(cur is UICollectionView), parts.count < 8 {
            let l = cur.layer.presentation() ?? cur.layer
            parts.append("\(Swift.type(of: cur)) \(ScriptFormat.rect(l.convert(l.bounds, to: wl)))")
            if cur is UICollectionViewCell { break }
            v = cur.superview
        }
        var s = " || " + parts.joined(separator: " < ")
        if let sv = r as? UIScrollView {
            let l = sv.layer.presentation() ?? sv.layer
            s += " tvoff=\(ScriptFormat.n(l.bounds.minY))/\(ScriptFormat.n(sv.contentOffset.y))"
        }
        return s
    }

    /// Each display frame for `ms`: the caret and the rows as drawn.
    private func frames(_ ms: Int, to name: String) async {
        let end = CACurrentMediaTime() + Double(ms) / 1000
        let lines = ScriptLines(["== frames \(ms) ms from \(self.ms())"])
        let tick = Tick { [weak self] in
            guard let self else { return }
            var caret = "-"
            if let r = self.responder(), let t = r as? UITextInput, let range = t.selectedTextRange {
                caret = ScriptFormat.rect(r.convert(t.caretRect(for: range.end), to: nil))
            }
            lines.v.append("F \(self.ms()) caret=\(caret) " + self.rows(drawn: true).replacingOccurrences(of: "\n  ", with: " | ")
                + self.fieldChain())
        }
        let link = CADisplayLink(target: tick, selector: #selector(Tick.fire))
        link.add(to: .main, forMode: .common)
        while CACurrentMediaTime() < end { try? await Task.sleep(for: .milliseconds(16)) }
        link.invalidate()
        write(lines.v.joined(separator: "\n"), to: name)
    }
}
#endif
