import AppKit
import SwiftUI
import TasksCore

// The detail pane's notes (design/MARKDOWN.md): one always-editable NSTextView whose storage is the Markdown source.
// It's rendered in place, and the marks show, faintly, only near the caret. Clicking puts the caret there and starts
// the editing session; the session commits once ("Edit Notes"), as before. Styling is in NotesMarkdown.swift.

// MARK: - The text view

final class NotesTextView: NSTextView {
    weak var notes: NotesField.Coordinator?
    /// Under an untitled new task (which the pane dims) and in the Trash (§22): deaf to the pointer, with no hover, no
    /// I-beam and no session.
    var inert = false {
        didSet { if inert != oldValue { window?.invalidateCursorRects(for: self); if inert { notes?.hover(at: nil) } } }
    }
    var placeholder: NSAttributedString?
    /// The notes' own undo while typing (§6), never the window's.
    private let notesUndo = UndoManager()
    private var lastTyping: TimeInterval = 0
    private var tracking: NSTrackingArea?
    /// In the detail pane: the pane's width on an animation (a zoom, the sidebar's slide, the divider springing back).
    /// The notes wrap once, at the width they're going to, as the slide starts (`WrapSettle`, as the list pane's text
    /// does). In the list pane the list lays its editors out itself.
    private(set) var settle: WrapSettle?
    /// The notes' height as they were wrapped when the slide began.
    private var settleFromHeight: CGFloat = 0

    override var undoManager: UndoManager? { notesUndo }
    /// ⌘Z and ⇧⌘Z are the notes' own (`FieldUndo`), never the window's.
    @objc func undo(_ sender: Any?) { FieldUndo.undo(notesUndo) }
    @objc func redo(_ sender: Any?) { FieldUndo.redo(notesUndo) }
    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        FieldUndo.validate(item, notesUndo) ?? super.validateMenuItem(item)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// A press on a box, a link, a dot or a number takes neither the caret nor the keys (§5, §6 Pointer). NSWindow makes
    /// the view under a press first responder before it calls `mouseDown`, which started the session with the caret
    /// where it was left (the end of the notes) and scrolled there (the user, 2026-11-08), so that press is refused here.
    override var acceptsFirstResponder: Bool {
        guard super.acceptsFirstResponder else { return false }
        guard window?.firstResponder !== self, let e = NSApp.currentEvent, e.type == .leftMouseDown, e.window === window,
              let n = notes else { return true }
        return !n.pressTakesNoCaret(at: convert(e.locationInWindow, from: nil))
    }
    override func hitTest(_ point: NSPoint) -> NSView? { inert ? nil : super.hitTest(point) }
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [] }
    override func dragSelection(with event: NSEvent, offset mouseOffset: NSSize, slideBack: Bool) -> Bool { false }

    func clearUndo() { notesUndo.removeAllActions() }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { notes?.sessionBegan() }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { notes?.endEditing() }
        return ok
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { notes?.endEditing() }
        super.viewWillMove(toWindow: newWindow)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // "Notes" in ink-tertiary while the text is empty, focused or not (md:8).
        if string.isEmpty, let placeholder {
            placeholder.draw(with: NSRect(x: textContainerOrigin.x, y: textContainerOrigin.y, width: bounds.width, height: NotesStyle.lineHeight),
                             options: [.usesLineFragmentOrigin])
        }
    }

    // MARK: The pane's width animating (the detail pane)

    func followPaneSettle() {
        guard settle == nil else { return }
        let s = WrapSettle()
        // Over: the container tracks the view again.
        s.onEnd = { [weak self] in
            guard let self, let tc = self.textContainer else { return }
            tc.widthTracksTextView = true
            tc.containerSize = NSSize(width: max(1, self.bounds.width), height: .greatestFiniteMagnitude)
            self.clipsToBounds = false
            self.needsDisplay = true
        }
        settle = s
    }

    /// The width the notes wrap at: the view's, or while the pane's width animates the width it's going to.
    var wrapWidth: CGFloat { settle?.to ?? bounds.width }

    /// The pane's settle from this update (`PaneSettle`): on an animated change of the pane's width the notes re-wrap
    /// now, once. The text container stops tracking the view, which SwiftUI gives every width on the way, and takes
    /// the width it's going to: widening, the longer lines show as the view's edge moves out; narrowing, the lines the
    /// wrap adds have the view's own room, or show as it grows.
    func paneSettle(_ p: PaneSettle?, animated: Bool) {
        guard let settle, let tc = textContainer else { return }
        let wrap = wrapWidth
        let from = fittingHeight(width: wrap)
        let began = settle.pane(p, animated: animated, wrap: wrap, inWindow: window != nil)
        // Began, or the pane is leaving and the notes keep the wrap they have.
        guard let to = settle.to, began || tc.widthTracksTextView else { return }
        settleFromHeight = from
        tc.widthTracksTextView = false
        _ = fittingHeight(width: to)
        // Narrowing, lines the wrap adds past the view's end wait for it to grow, as what's under it moves down.
        clipsToBounds = to < wrap
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        settle?.arrived(newSize.width)
    }

    /// The height SwiftUI gives the notes at `width`: their lines there. While the pane's width animates the lines are
    /// already those of the width it's going to, and the height goes from the old to the new as the width does, so
    /// what's under the notes glides on the pane's own motion instead of jumping a line.
    func fittedHeight(width: CGFloat) -> CGFloat {
        guard let settle, let s = settle.span else { return fittingHeight(width: width) }
        let h1 = fittingHeight(width: s.to)
        return settleFromHeight + (h1 - settleFromHeight) * settle.progress(at: width)
    }

    /// The text's height at `width`: whole lines, at least one.
    func fittingHeight(width: CGFloat) -> CGFloat {
        guard let lm = layoutManager, let tc = textContainer else { return NotesStyle.lineHeight }
        if abs(tc.containerSize.width - width) > 0.25 {
            tc.containerSize = NSSize(width: max(1, width), height: .greatestFiniteMagnitude)
        }
        lm.ensureLayout(for: tc)
        var h = lm.usedRect(for: tc).maxY
        if !lm.extraLineFragmentRect.isEmpty { h = max(h, lm.extraLineFragmentRect.maxY) }
        return max(NotesStyle.lineHeight, ceil(h))
    }

    // MARK: Pointer (§6 Pointer)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func resetCursorRects() {
        if !inert { super.resetCursorRects() }
    }

    override func mouseMoved(with event: NSEvent) {
        guard !inert else { return }
        super.mouseMoved(with: event)
        guard let n = notes else { return }
        let p = convert(event.locationInWindow, from: nil)
        n.hover(at: p)
        if n.link(at: p) != nil { NSCursor.pointingHand.set() } else if n.box(at: p) != nil || n.inGutter(p) { NSCursor.arrow.set() }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        notes?.hover(at: nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard !inert, let n = notes else { return }
        let p = convert(event.locationInWindow, from: nil)
        // A box toggles on release, inside; it never takes the caret or the keys (§5).
        if let box = n.box(at: p) {
            n.pressBox(box, down: true)
            var inside = true
            while let e = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
                inside = n.box(at: convert(e.locationInWindow, from: nil)) == box
                n.pressBox(box, down: inside)
                if e.type == .leftMouseUp { break }
            }
            n.pressBox(box, down: false)
            if inside { n.toggleBox(box) }
            return
        }
        // A link opens on a plain click, with no caret (§6). Dots and numbers take nothing.
        if let url = n.link(at: p) {
            n.hover(at: nil)
            NSWorkspace.shared.open(url)
            return
        }
        if n.inGutter(p) { return }
        // The marks wait for the button to come up, so the text never moves under the pointer (§4).
        n.dragging = true
        super.mouseDown(with: event)
        n.dragging = false
        n.updateReveal()
    }

    // MARK: Keys (§6 Keys while editing)

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let returnKey = event.keyCode == 36 || event.keyCode == 76
        if event.keyCode == 53, mods.isEmpty { notes?.done(); return }
        if returnKey, mods == .command { notes?.done(); return }
        if returnKey, mods == .shift { replace(selectedRange(), "\n", kind: .typing); return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { notes?.done() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if mods == .command, let c = event.charactersIgnoringModifiers?.lowercased() {
            if c == "b" { wrap(bold: true); return true }
            if c == "i" { wrap(bold: false); return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func notesBold(_ sender: Any?) { wrap(bold: true) }
    @objc func notesItalic(_ sender: Any?) { wrap(bold: false) }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // Typing coalesces into one undo step per 1.5 s pause (§6).
        let now = Date.timeIntervalSinceReferenceDate
        if now - lastTyping > 1.5 { breakUndoCoalescing() }
        lastTyping = now
        guard var s = (string as? String) ?? (string as? NSAttributedString)?.string else { return super.insertText(string, replacementRange: replacementRange) }
        let r = replacementRange.location == NSNotFound ? (hasMarkedText() ? markedRange() : selectedRange()) : replacementRange
        // A `]` closing a box brings the space after it, in the same typing step; a space typed after that one isn't
        // doubled (§5, the user, 2026-11-01).
        var typed: Any = string
        if let b = notes?.boxTyping(s, at: r) {
            if b.isEmpty { return }
            s = b
            typed = b
        }
        let room = NotesStyle.maxLength - ((self.string as NSString).length - r.length)
        if (s as NSString).length > room {
            notes?.overLimit()
            guard room > 0 else { return }
            super.insertText(Self.prefix(s, room), replacementRange: replacementRange)
            return
        }
        super.insertText(typed, replacementRange: replacementRange)
    }

    override func insertNewline(_ sender: Any?) {
        if !newline() { super.insertNewline(sender) }
    }

    override func deleteBackward(_ sender: Any?) {
        if !backspace() { super.deleteBackward(sender) }
    }

    override func insertTab(_ sender: Any?) {
        if !indent(out: false) { replace(selectedRange(), "\t", kind: .typing) }
    }

    override func insertBacktab(_ sender: Any?) {
        if !indent(out: true) { notes?.backToTitle() }
    }

    // MARK: Pasting (§6 Pasting)

    override func paste(_ sender: Any?) { paste(plain: false) }
    override func pasteAsPlainText(_ sender: Any?) { paste(plain: true) }
    override func pasteAsRichText(_ sender: Any?) { paste(plain: false) }

    func paste(plain: Bool, from pb: NSPasteboard = .general) {
        guard let n = notes else { return }
        let txt = (pb.string(forType: .string) ?? "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let sel = selectedRange()
        let t = string as NSString
        let line = n.document.line(at: sel.location)
        let plainOnly = plain || line?.kind == .code || line?.kind == .fence
        let one = txt.trimmingCharacters(in: .whitespacesAndNewlines)
        let isURL = one.range(of: #"^(https?://|mailto:)\S+$"#, options: [.regularExpression, .caseInsensitive]) != nil
        // A URL over selected text links it: the way to make a named link.
        if sel.length > 0, isURL, !t.substring(with: sel).contains("\n") {
            let label = t.substring(with: sel).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            let addr = one.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
            replace(sel, "[" + label + "](" + addr + ")", kind: .paste)
            return
        }
        var ins = txt
        if !plainOnly, !isURL, let rich = Self.richText(pb) {
            let m = NotesPaste.markdown(from: rich)
            if !m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { ins = m }
        }
        // Blocks start on a line of their own and leave the rest of the line below them.
        if !plainOnly, !ins.isEmpty,
           ins.contains("\n") || ins.range(of: #"^(#{1,6} |[-*+] |\d+[.)] |> |```)"#, options: .regularExpression) != nil {
            if sel.location > 0, t.character(at: sel.location - 1) != 10 { ins = "\n" + ins }
            if NSMaxRange(sel) < t.length, t.character(at: NSMaxRange(sel)) != 10 { ins += "\n" }
        }
        guard !ins.isEmpty else { return }
        replace(sel, ins, kind: .paste)
    }

    /// RTF first (fast); HTML only without it, as it loads WebKit, and only for a clipboard the notes could hold.
    private static func richText(_ pb: NSPasteboard) -> NSAttributedString? {
        if let d = pb.data(forType: .rtf), let a = NSAttributedString(rtf: d, documentAttributes: nil) { return a }
        if let d = pb.data(forType: .html), d.count < 400_000,
           let a = NSAttributedString(html: d, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) {
            return a
        }
        return nil
    }

    // MARK: Edits

    enum EditKind { case typing, paste, structure }

    /// One undoable change: the notes' undo groups it, past 20,000 characters it's trimmed with a notice.
    func replace(_ r: NSRange, _ s: String, kind: EditKind, select: NSRange? = nil, scroll: Bool = true) {
        var s = s
        let room = NotesStyle.maxLength - ((string as NSString).length - r.length)
        if (s as NSString).length > room {
            notes?.overLimit()
            s = Self.prefix(s, max(0, room))
        }
        if kind != .typing { breakUndoCoalescing() }
        guard shouldChangeText(in: r, replacementString: s) else { return }
        textStorage?.replaceCharacters(in: r, with: s)
        didChangeText()
        let caret = select ?? NSRange(location: r.location + (s as NSString).length, length: 0)
        setSelectedRange(caret)
        if kind != .typing { breakUndoCoalescing() }
        if scroll { scrollRangeToVisible(caret) }
    }

    /// The first `n` UTF-16 units, not splitting a surrogate pair.
    static func prefix(_ s: String, _ n: Int) -> String {
        let ns = s as NSString
        guard ns.length > n else { return s }
        var end = n
        if end > 0, end < ns.length, CFStringIsSurrogateLowCharacter(ns.character(at: end)) { end -= 1 }
        return ns.substring(to: end)
    }

    private var doc: NotesDocument? { notes?.document }

    /// Return continues a list, checklist or quote; on an empty item it outdents, then ends the list. In a code block
    /// the new line keeps the indent (`nReturn`, dc:2041–2060).
    private func newline() -> Bool {
        guard !hasMarkedText(), let d = doc else { return false }
        let sel = selectedRange()
        let t = string as NSString
        guard let l = d.line(at: sel.location) else { return false }
        if sel.length > 0, let b = d.line(at: NSMaxRange(sel)), b.index != l.index { return false }
        let a = sel.location
        if l.kind == .code {
            let line = t.substring(with: NSRange(location: l.start, length: a - l.start))
            replace(sel, "\n" + line.prefix { $0 == " " || $0 == "\t" }, kind: .structure)
            return true
        }
        guard (l.isListItem || l.kind == .quote) && a >= l.textStart else { return false }
        let rest = t.substring(with: NSRange(location: l.textStart, length: l.end - l.textStart))
        if sel.length == 0 && rest.trimmingCharacters(in: .whitespaces).isEmpty {
            if l.isListItem && l.level > 0 {
                replace(NSRange(location: l.start, length: 2), "", kind: .structure, select: NSRange(location: a - 2, length: 0))
            } else {
                replace(l.range, "", kind: .structure)
            }
            return true
        }
        let lead = String(repeating: " ", count: l.lead)
        let pre: String
        switch l.kind {
        case .quote: pre = "> "
        case .ordered: pre = lead + "\(l.number + 1)" + String(UnicodeScalar(UInt8(l.delimiter))) + " "
        case .task: pre = lead + String(UnicodeScalar(UInt8(l.bullet))) + " [ ] "
        default: pre = lead + String(UnicodeScalar(UInt8(l.bullet))) + " "
        }
        replace(sel, "\n" + pre, kind: .structure)
        return true
    }

    /// Backspace at the start of an item's text outdents it, then makes it a plain line; at the start of a heading or
    /// quote, the `#`s or `>` go (`nBackspace`, dc:2063–2075).
    private func backspace() -> Bool {
        guard !hasMarkedText(), let d = doc else { return false }
        let sel = selectedRange()
        guard sel.length == 0, sel.location > 0, let l = d.line(at: sel.location), l.prefix > 0, sel.location == l.textStart,
              l.isListItem || l.kind == .quote || l.kind == .heading1 || l.kind == .heading2 else { return false }
        if l.isListItem && l.level > 0 {
            replace(NSRange(location: l.start, length: 2), "", kind: .structure, select: NSRange(location: sel.location - 2, length: 0))
        } else {
            replace(NSRange(location: l.start, length: l.prefix), "", kind: .structure, select: NSRange(location: l.start, length: 0))
        }
        return true
    }

    /// Tab and ⇧Tab move the list items in the selection a level (two spaces, two levels at most) (`nIndent`,
    /// dc:2078–2090). False when there's none to move.
    private func indent(out: Bool) -> Bool {
        guard let d = doc else { return false }
        let sel = selectedRange()
        let a = sel.location, b = NSMaxRange(sel)
        let items = d.lines.filter { $0.isListItem && $0.end >= a && $0.start <= b }
        guard !items.isEmpty else { return false }
        if out && items.allSatisfy({ $0.level == 0 }) { return false }
        let t = string as NSString
        let span = NSRange(location: items[0].start, length: items[items.count - 1].end - items[0].start)
        var s = t.substring(with: span) as NSString
        var da = 0, db = 0
        for l in items.reversed() {
            let at = l.start - span.location
            if out {
                guard l.level > 0 else { continue }
                s = s.replacingCharacters(in: NSRange(location: at, length: 2), with: "") as NSString
                if l.start < a { da -= 2 }
                db -= 2
            } else {
                guard l.level < 2 else { continue }
                s = s.replacingCharacters(in: NSRange(location: at, length: 0), with: "  ") as NSString
                if l.start <= a { da += 2 }
                db += 2
            }
        }
        guard s as String != t.substring(with: span) else { return true }
        let na = max(0, a + da), nb = max(na, b + db)
        replace(span, s as String, kind: .structure, select: NSRange(location: na, length: nb - na))
        return true
    }

    /// ⌘B / ⌘I: wrap the selection or the word at the caret; inside that style already, take it off (`nWrap`,
    /// dc:2092–2113).
    private func wrap(bold: Bool) {
        guard let d = doc, !hasMarkedText() else { return }
        let mk = bold ? "**" : "_", ml = (mk as NSString).length
        let sel = selectedRange()
        let a = sel.location, b = NSMaxRange(sel)
        let t = string as NSString
        if let l = d.line(at: a), let tok = d.tokens(l).filter({ $0.kind == (bold ? .bold : .italic) && $0.range.lowerBound <= a && b <= $0.range.upperBound }).last {
            func map(_ x: Int) -> Int {
                if x <= tok.range.lowerBound { return x }
                if x >= tok.range.upperBound { return x - 2 * ml }
                return min(max(x - ml, tok.range.lowerBound), tok.range.upperBound - 2 * ml)
            }
            let inner = t.substring(with: NSRange(location: tok.inner.lowerBound, length: tok.inner.count))
            let na = map(a), nb = map(b)
            replace(NSRange(location: tok.range.lowerBound, length: tok.range.count), inner, kind: .structure,
                    select: NSRange(location: na, length: nb - na))
            return
        }
        if sel.length == 0 {
            if let w = word(at: a) {
                replace(w, mk + t.substring(with: w) + mk, kind: .structure, select: NSRange(location: a + ml, length: 0))
            } else {
                replace(sel, mk + mk, kind: .structure, select: NSRange(location: a + ml, length: 0))
            }
            return
        }
        // Spaces at either end stay outside; over several lines, each line's text is wrapped.
        let seg = t.substring(with: sel).components(separatedBy: "\n").map { x -> String in
            let lead = x.prefix { $0.isWhitespace }, trail = String(x.reversed().prefix { $0.isWhitespace }.reversed())
            let core = x.trimmingCharacters(in: .whitespaces)
            return core.isEmpty ? x : String(lead) + mk + core + mk + trail
        }.joined(separator: "\n")
        replace(sel, seg, kind: .structure, select: NSRange(location: a, length: (seg as NSString).length))
    }

    /// The word around `a`: letters, digits, apostrophes and hyphens (`mdWordAt`, dc:625).
    private func word(at a: Int) -> NSRange? {
        let t = string as NSString
        func isWord(_ i: Int) -> Bool {
            guard i >= 0, i < t.length, let u = UnicodeScalar(t.character(at: i)) else { return false }
            return CharacterSet.letters.contains(u) || CharacterSet.decimalDigits.contains(u) || "'’-".unicodeScalars.contains(u)
        }
        var s = a, e = a
        while s > 0 && isWord(s - 1) { s -= 1 }
        while e < t.length && isWord(e) { e += 1 }
        return e > s ? NSRange(location: s, length: e - s) : nil
    }

    // MARK: Accessibility (§9): the text as it reads, and each box as a checkbox

    override func accessibilityValue() -> String? { notes?.readingText() ?? super.accessibilityValue() }

    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + (notes?.boxElements(in: self) ?? [])
    }
}

/// A checklist box for VoiceOver: a checkbox with its item's text; pressing it toggles the item.
final class NotesBoxElement: NSAccessibilityElement {
    var toggle: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { toggle?(); return true }
}

// MARK: - SwiftUI

/// Where a notes editor lives and what it edits: a task's notes in the detail pane, or a list's or a heading's in the
/// list pane (design/INTERACTIONS-v2.md §23), where they're a step quieter (`ink-secondary`).
struct NotesHost {
    enum Target: Hashable { case task(EntityID), list(EntityID) }
    var store: Store
    var window: WindowState
    var target: Target
    var notes: String
    var inert = false
    var palette: TK.Palette
    /// In the detail pane: a session sets `detailEditing` and the pane's focus. In the list pane it sets `paneNotes`.
    var inDetail = true
    var onLayoutChange: () -> Void = {}
    /// The text's length while it's being edited (the footer's count), nil at rest.
    var onLength: (Int?) -> Void = { _ in }
    /// ⇧Tab outside a list item: back to the title the notes belong to.
    var backToTitle: () -> Void = {}
}

/// The notes area: fills the space it's given (it's the pane's flexible part), shows and edits one task's notes, and
/// writes one `task.update` per editing session.
struct NotesField: NSViewRepresentable {
    let store: Store
    let window: WindowState
    let refs: DetailRefs
    let id: EntityID
    let notes: String
    let inert: Bool
    let palette: TK.Palette
    /// Bumped by the view while editing, so SwiftUI measures the text again.
    let layoutTick: Int
    let onLayoutChange: () -> Void
    /// The text's length while it's being edited (the footer's count), nil at rest.
    let onLength: (Int?) -> Void
    @Environment(\.paneSettle) private var paneSettle

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var host: NotesHost {
        NotesHost(store: store, window: window, target: .task(id), notes: notes, inert: inert, palette: palette,
                  inDetail: true, onLayoutChange: onLayoutChange, onLength: onLength,
                  backToTitle: { [refs] in refs.focusTitle(.all) })
    }

    func makeNSView(context: Context) -> NotesTextView {
        let c = context.coordinator
        let v = Self.makeEditor(c, host: host)
        v.followPaneSettle()
        refs.notes = c
        return v
    }

    /// The text view and its TextKit 1 stack, wired to `c`, showing `host`'s notes.
    static func makeEditor(_ c: Coordinator, host: NotesHost) -> NotesTextView {
        let storage = NSTextStorage()
        let lm = NotesLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: 340, height: CGFloat.greatestFiniteMagnitude))
        tc.lineFragmentPadding = 0
        tc.widthTracksTextView = true
        lm.addTextContainer(tc)
        let v = NotesTextView(frame: NSRect(x: 0, y: 0, width: 340, height: 120), textContainer: tc)
        v.drawsBackground = false
        v.isRichText = false
        v.importsGraphics = false
        v.allowsUndo = true
        v.isEditable = true
        v.isSelectable = true
        v.isVerticallyResizable = false
        v.isHorizontallyResizable = false
        v.textContainerInset = .zero
        v.isAutomaticQuoteSubstitutionEnabled = false
        v.isAutomaticDashSubstitutionEnabled = false
        v.isAutomaticTextReplacementEnabled = false
        v.isAutomaticSpellingCorrectionEnabled = false
        v.isAutomaticLinkDetectionEnabled = false
        v.isContinuousSpellCheckingEnabled = false
        v.isGrammarCheckingEnabled = false
        v.smartInsertDeleteEnabled = false
        v.usesFontPanel = false
        v.usesFindBar = false
        v.displaysLinkToolTips = false
        v.linkTextAttributes = [:]
        v.focusRingType = .none
        v.setAccessibilityLabel("Notes")
        c.host = host
        c.view = v
        v.notes = c
        v.delegate = c
        storage.delegate = c
        lm.decorations = c
        v.inert = host.inert
        c.apply(force: true)
        return v
    }

    func updateNSView(_ v: NotesTextView, context: Context) {
        let c = context.coordinator
        c.host = host
        refs.notes = c
        v.inert = inert
        c.apply(force: false)
        let t = context.transaction
        v.paneSettle(paneSettle, animated: t.animation != nil && !t.disablesAnimations)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: NotesTextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 340
        let h = v.fittedHeight(width: w)
        return CGSize(width: w, height: max(h, proposal.height ?? 0))
    }

    static func dismantleNSView(_ v: NotesTextView, coordinator: Coordinator) {
        coordinator.endEditing()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate, NotesDecorations {
        var host: NotesHost!
        weak var view: NotesTextView?
        let document = NotesDocument()
        /// In the list pane the notes are a step quieter: `ink-secondary` where the detail pane has `ink` (§23).
        var palette: TK.Palette { host.inDetail ? host.palette : host.palette.quieter }
        /// The editing session: whose notes, and what they were.
        private(set) var session: (target: NotesHost.Target, original: String)?
        /// What the view shows at rest: whose notes, the notes and the theme.
        private var shown: (target: NotesHost.Target, notes: String, palette: TK.Palette)?
        /// The button is down in the text: the marks wait for it (§4).
        var dragging = false
        private(set) var hoveredLink: NSRange?
        private var hoveredBox: Int?
        private var boxes: [Int: BoxAnimation] = [:]
        private var ticker: Timer?
        private var fades: [(NSRange, TimeInterval)] = []
        private var actions: WindowActions { WindowActions(store: host.store, window: host.window) }

        private struct BoxAnimation {
            var hoverFrom: CGFloat = 0, hoverTo: CGFloat = 0, hoverAt: TimeInterval = 0
            var pressed = false, pressAt: TimeInterval = 0, releaseAt: TimeInterval?
            var checkAt: TimeInterval?, popAt: TimeInterval?
        }

        // MARK: Model → view

        /// Shows the task's notes (unless they're being edited), restyled for the theme.
        func apply(force: Bool) {
            guard let v = view else { return }
            let tk = palette
            v.insertionPointColor = tk.ink
            v.selectedTextAttributes = [.backgroundColor: tk.textSelection]
            refreshPlaceholder()
            v.typingAttributes = NotesStyle.base(tk)
            let themeChanged = shown?.palette != tk
            if session != nil {
                if themeChanged { shown?.palette = tk; restyleAll() }
                return
            }
            guard force || shown?.target != host.target || shown?.notes != host.notes || themeChanged else { return }
            shown = (host.target, host.notes, tk)
            if v.string != host.notes {
                v.textStorage?.replaceCharacters(in: NSRange(location: 0, length: (v.string as NSString).length), with: host.notes)
            }
            pending = nil
            restyleAll()
            v.clearUndo()
            v.needsDisplay = true
            host.onLayoutChange()
        }

        /// In the list pane an empty editor shows nothing at rest (§23): the title block fades its own "Notes" in on
        /// hover, and a heading's shows it, in `ink-quaternary`, only with the caret in it (css:448–450).
        private func refreshPlaceholder() {
            guard let v = view else { return }
            let tk = palette
            let ph: NSAttributedString?
            if host.inDetail {
                ph = NotesStyle.placeholder(tk)
            } else if case .task = host.target, session != nil {
                let a = NSMutableAttributedString(attributedString: NotesStyle.placeholder(tk))
                a.addAttribute(.foregroundColor, value: tk.inkQuiet, range: NSRange(location: 0, length: a.length))
                ph = a
            } else {
                ph = nil
            }
            if v.placeholder != ph {
                v.placeholder = ph
                v.needsDisplay = true
            }
        }

        // MARK: The session

        /// A press in the notes, or Return / Tab in the title: the caret, and the session begins.
        func startEditing() {
            guard let v = view, let w = v.window, !host.inert else { return }
            w.makeFirstResponder(v)
            let end = (v.string as NSString).length
            v.setSelectedRange(NSRange(location: end, length: 0))
            v.scrollRangeToVisible(NSRange(location: end, length: 0))
        }

        func sessionBegan() {
            guard session == nil, let v = view else { return }
            session = (host.target, v.string)
            refreshPlaceholder()
            v.clearUndo()
            let w = host.window
            if host.inDetail {
                if w.detailEditing != .notes { w.detailEditing = .notes }
                if w.focus != .detail { w.focus = .detail }
            } else {
                if w.paneNotes != host.target { w.paneNotes = host.target }
                if w.focus != .list { w.focus = .list }
            }
            reportLength(v)
            if !dragging { updateReveal() }
        }

        /// Esc, ⌘Return, ⇧Tab or a press elsewhere: one `task.update` if the user changed the text from where the session
        /// began (`EditSession`). Notes left as they were never go back over ones that synced in during the session;
        /// the view shows those instead.
        func endEditing() {
            guard let s = session, let v = view else { return }
            session = nil
            let text = v.string
            refreshPlaceholder()
            let w = host.window
            if host.inDetail {
                if w.detailEditing == .notes { w.detailEditing = nil }
            } else if w.paneNotes == s.target {
                w.paneNotes = nil
            }
            let store = host.store
            let a = actions
            var wrote = false
            switch s.target {
            case .task(let id):
                if let t = store.projection.task(id), !t.deleted, EditSession.write(text, original: s.original, current: t.notes) != nil {
                    a.undoable("Edit Notes") { store.setNotes(id, text, name: "Edit Notes", undoManager: a.undo) }
                    wrote = true
                }
            case .list(let id):
                if let l = store.projection.list(id), EditSession.write(text, original: s.original, current: l.notes) != nil {
                    a.undoable("Edit List Notes") { store.setNotes(list: id, text, name: "Edit List Notes", undoManager: a.undo) }
                    wrote = true
                }
            }
            // Read what was written, not the model (it may update a moment later).
            shown = (s.target, text, palette)
            v.clearUndo()
            setReveal(nil)
            hover(at: nil)
            host.onLength(nil)
            host.onLayoutChange()
            // Nothing written and the model moved on (notes synced in): show the model's.
            if !wrote, text != host.notes { apply(force: true) }
        }

        /// Esc and ⌘Return: done, the text kept, the keys to the list.
        func done() {
            view?.window?.makeFirstResponder(nil)
            endEditing()
            actions.focus(.list)
        }

        /// ⇧Tab outside a list: back to the title.
        func backToTitle() {
            view?.window?.makeFirstResponder(nil)
            endEditing()
            host.backToTitle()
        }

        func overLimit() { host.window.overlays.showNotice("Notes hold up to 20,000 characters", undo: false) }

        // MARK: Restyling (§9: one line at a time)

        /// The characters edited since the last restyle (in the current string), and whether a fence count may have
        /// changed. Restyling waits until the edit is done: attributes changed while the storage processes an edit
        /// widen its edited range, and NSTextView then put the caret at the end of the restyled line.
        private var pending: NSRange?

        func textStorage(_ ts: NSTextStorage, willProcessEditing mask: NSTextStorageEditActions, range: NSRange, changeInLength delta: Int) {
            guard mask.contains(.editedCharacters) else { return }
            if let p = pending {
                // The old pending range moves with the edit if it's after it.
                let shifted = p.location >= range.location ? NSRange(location: max(range.location, p.location + delta), length: p.length) : p
                let lo = min(shifted.location, range.location), hi = min(ts.length, max(NSMaxRange(shifted), NSMaxRange(range)))
                pending = NSRange(location: lo, length: max(0, hi - lo))
            } else {
                pending = range
            }
        }

        /// Restyles what the last edits touched (one line per keystroke), then shows the marks near the caret.
        func restylePending() {
            guard let range = pending, let v = view, let ts = v.textStorage, !v.hasMarkedText() else { return }
            pending = nil
            let old = document.doc
            document.update(ts.string)
            let new = document.doc
            guard let touched = document.lines(touching: NSRange(location: min(range.location, ts.length), length: 0).union(
                NSRange(location: min(NSMaxRange(range), ts.length), length: 0))) else { return }
            var from = touched.lowerBound, to = touched.upperBound
            // Fences are the one rule that isn't local: an edit on or around one restyles to the end.
            let fences = { (d: Markdown.Document) in d.lines.lazy.filter { $0.kind == .fence }.count }
            if fences(old) != fences(new) || new.lines[from...to].contains(where: { $0.block >= 0 }) {
                to = new.lines.count - 1
            }
            // Heading space ("none above the first line") and list numbering follow the line before.
            from = max(0, from - 1)
            ts.beginEditing()
            for i in from...to { NotesStyler.style(new.lines[i], document, ts, palette) }
            ts.endEditing()
            // Numbers and quote bars further down may change without their lines moving.
            v.needsDisplay = true
            // An edit that leaves the caret in a list's prefix (undoing an indent puts it at the line's start) puts it
            // at the item's text, as a move there would; the snap waits for this parse.
            let sel = v.selectedRange()
            if sel.length == 0, let l = document.line(at: sel.location), l.isListItem, sel.location >= l.start,
               sel.location < l.textStart {
                v.setSelectedRange(NSRange(location: l.textStart, length: 0))
            }
            if wantReveal != document.reveal { setReveal(wantReveal) }
        }

        /// The reveal asked for while an edit was pending.
        private var wantReveal: NSRange?

        /// What typing `s` at `r` puts in instead, for a checklist box being typed (`Markdown.typing`); nil to type it
        /// as it is. Only a plain keystroke at a caret, on a current parse.
        func boxTyping(_ s: String, at r: NSRange) -> String? {
            guard r.length == 0, pending == nil, let v = view, !v.hasMarkedText(),
                  document.units.count == (v.string as NSString).length, let l = document.line(at: r.location) else { return nil }
            return document.units.withUnsafeBufferPointer { Markdown.typing(s, at: r.location, on: l, $0) }
        }

        private func restyleAll() {
            guard let ts = view?.textStorage else { return }
            document.update(ts.string)
            ts.beginEditing()
            let t0 = DispatchTime.now().uptimeNanoseconds
            for l in document.lines { NotesStyler.style(l, document, ts, palette) }
            let t1 = DispatchTime.now().uptimeNanoseconds
            ts.endEditing()
            lastRestyle = (Double(t1 - t0) / 1e6, Double(DispatchTime.now().uptimeNanoseconds - t1) / 1e6)
            view?.needsDisplay = true
        }

        /// The last full restyle: the styling loop and the storage's own processing, in ms (for `nbench:`).
        private(set) var lastRestyle: (loop: Double, process: Double) = (0, 0)

        /// The marks near the selection show; the ones it left are hidden again. Only the lines (and code blocks) the
        /// old and new selection touch are restyled: O(token), not O(document) (§9).
        func updateReveal() {
            guard let v = view, session != nil, !dragging, v.window?.firstResponder === v else { return }
            setReveal(v.selectedRange())
        }

        private func setReveal(_ sel: NSRange?) {
            wantReveal = sel
            // Mid-edit the lines are stale: the restyle after it applies this.
            guard pending == nil else { return }
            guard let ts = view?.textStorage, sel != document.reveal else { return }
            let old = document.reveal
            var lines = Set<Int>()
            var blocks = Set<Int>()
            func add(_ r: NSRange?) {
                guard let r, let span = document.lines(touching: r) else { return }
                for i in span { lines.insert(i) }
                for (i, b) in document.doc.blocks.enumerated() where r.location <= b.end && NSMaxRange(r) >= b.start { blocks.insert(i) }
            }
            add(old)
            add(sel)
            for b in blocks {
                let blk = document.doc.blocks[b]
                for i in blk.first...blk.last { lines.insert(i) }
            }
            guard !lines.isEmpty else { document.reveal = sel; return }
            // Marks that were hidden in these lines, to fade in the ones that appear.
            var hiddenBefore: [NSRange] = []
            for i in lines {
                let l = document.lines[i]
                ts.enumerateAttribute(.mdHidden, in: l.range) { v, r, _ in if v != nil { hiddenBefore.append(r) } }
            }
            document.reveal = sel
            ts.beginEditing()
            for i in lines.sorted() { NotesStyler.style(document.lines[i], document, ts, palette) }
            ts.endEditing()
            if !TK.CA.reduce {
                let now = Date.timeIntervalSinceReferenceDate
                for r in hiddenBefore {
                    ts.enumerateAttribute(.mdHidden, in: r) { v, rr, _ in if v == nil { fades.append((rr, now)) } }
                }
                if !fades.isEmpty { tick() }
            }
        }

        // MARK: Selection: never inside a list's prefix

        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange,
                      toCharacterRange new: NSRange) -> NSRange {
            // Mid-edit the parse is a keystroke behind: typing at the end of a line put the caret one line on, at
            // what the stale parse took for the next item's prefix, and snapped it past that (v2 feedback 13). An
            // edit's caret is snapped in `restylePending`, against the new parse.
            guard pending == nil, new.length == 0, let l = document.line(at: new.location), l.isListItem,
                  new.location < l.textStart, new.location >= l.start else { return new }
            // Moving left from the item's text goes on to the line before; anything else lands at the text.
            let keyLeft = NSApp.currentEvent?.type == .keyDown && old.location >= l.textStart && old.length == 0
            if keyLeft && l.start > 0 { return NSRange(location: l.start - 1, length: 0) }
            return NSRange(location: l.textStart, length: 0)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if !dragging { updateReveal() }
        }

        func textDidChange(_ notification: Notification) {
            restylePending()
            guard let v = view else { return }
            reportLength(v)
            // SwiftUI measures the notes again only when their height changed, not on every keystroke.
            let h = v.fittingHeight(width: v.wrapWidth)
            if h != lastHeight {
                lastHeight = h
                host.onLayoutChange()
            }
        }

        private var lastHeight: CGFloat = 0

        /// The footer's count shows from 18,000 characters; below that the length isn't reported, so typing doesn't
        /// redraw the pane.
        private func reportLength(_ v: NSTextView) {
            let n = v.string.utf16.count
            host.onLength(n >= NotesStyle.nearLength ? n : 0)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL { NSWorkspace.shared.open(url) }
            return true
        }

        // MARK: Pointer

        private func containerPoint(_ p: CGPoint) -> CGPoint {
            guard let v = view else { return p }
            return CGPoint(x: p.x - v.textContainerOrigin.x, y: p.y - v.textContainerOrigin.y)
        }

        private var layout: NotesLayoutManager? { view?.layoutManager as? NotesLayoutManager }

        /// The list item whose first line holds `p`.
        private func listItem(at p: CGPoint) -> (Markdown.Line, CGRect)? {
            guard let lm = layout, let tc = view?.textContainer, (view?.string as NSString?)?.length ?? 0 > 0 else { return nil }
            let q = containerPoint(p)
            let g = lm.glyphIndex(for: q, in: tc)
            guard let l = document.line(at: lm.characterIndexForGlyph(at: g)), l.isListItem, let f = lm.fragment(l, first: true),
                  q.y >= f.minY - 2, q.y < f.maxY + 2 else { return nil }
            return (l, f)
        }

        /// A checklist box under `p` (its 20×20 hit area): the offset of its character.
        func box(at p: CGPoint) -> Int? {
            guard let (l, f) = listItem(at: p), l.kind == .task else { return nil }
            let q = containerPoint(p)
            let r = CGRect(x: CGFloat(l.level) * NotesStyle.column + 2 - 4, y: f.minY + 3.5 - 4, width: 20, height: 20)
            return r.contains(q) ? l.box : nil
        }

        /// A press here toggles a box, opens a link or takes nothing (a dot or a number): never the caret (§6 Pointer).
        func pressTakesNoCaret(at p: CGPoint) -> Bool { box(at: p) != nil || link(at: p) != nil || inGutter(p) }

        /// The gutter of a list item (a dot or a number): presses there take nothing.
        func inGutter(_ p: CGPoint) -> Bool {
            guard let (l, _) = listItem(at: p) else { return false }
            return containerPoint(p).x < CGFloat(l.level + 1) * NotesStyle.column - 4
        }

        /// The link whose text is under `p`.
        func link(at p: CGPoint) -> URL? { linkRange(at: p)?.1 }

        private func linkRange(at p: CGPoint) -> (NSRange, URL, String)? {
            guard let lm = layout, let tc = view?.textContainer, let ts = view?.textStorage, ts.length > 0 else { return nil }
            let q = containerPoint(p)
            var frac: CGFloat = 0
            let g = lm.glyphIndex(for: q, in: tc, fractionOfDistanceThroughGlyph: &frac)
            guard lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc).insetBy(dx: 0, dy: -2).contains(q) else { return nil }
            let ci = lm.characterIndexForGlyph(at: g)
            var r = NSRange()
            guard ci < ts.length, let href = ts.attribute(.mdLink, at: ci, effectiveRange: &r) as? String,
                  ts.attribute(.mdHidden, at: ci, effectiveRange: nil) == nil, let url = NotesStyle.url(href) else { return nil }
            return (r, url, href)
        }

        /// Hover: a link's underline comes up to full and its address shows in the tooltip after 600 ms; a box's ring
        /// goes ink-secondary (md:16–18, md:45).
        func hover(at p: CGPoint?) {
            let link = p.flatMap(linkRange(at:))
            if link?.0 != hoveredLink {
                let old = hoveredLink
                hoveredLink = link?.0
                for r in [old, hoveredLink].compactMap({ $0 }) { redraw(r) }
                if let (r, _, href) = link, let v = view, let lm = layout, let tc = v.textContainer, let w = v.window {
                    let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
                    let rect = lm.boundingRect(forGlyphRange: g, in: tc).offsetBy(dx: v.textContainerOrigin.x, dy: v.textContainerOrigin.y)
                    let inWindow = v.convert(rect, to: nil)
                    let h = w.contentView?.bounds.height ?? 0
                    let top = CGRect(x: inWindow.minX, y: h - inWindow.maxY, width: inWindow.width, height: inWindow.height)
                    host.window.overlays.hoverTip(NotesStyle.tip(href), for: top, windowWidth: w.contentView?.bounds.width ?? 0)
                } else {
                    host.window.overlays.hideTip()
                }
            }
            let box = p.flatMap(box(at:))
            if box != hoveredBox {
                let now = Date.timeIntervalSinceReferenceDate
                if let b = hoveredBox { setHover(b, 0, now) }
                hoveredBox = box
                if let b = box { setHover(b, 1, now) }
            }
        }

        private func setHover(_ b: Int, _ to: CGFloat, _ now: TimeInterval) {
            var a = boxes[b] ?? BoxAnimation()
            a.hoverFrom = boxState(b).hover
            a.hoverTo = to
            a.hoverAt = now
            boxes[b] = a
            tick()
        }

        func pressBox(_ b: Int, down: Bool) {
            var a = boxes[b] ?? BoxAnimation()
            let now = Date.timeIntervalSinceReferenceDate
            if down != a.pressed {
                a.pressed = down
                if down { a.pressAt = now; a.releaseAt = nil } else { a.releaseAt = now }
            }
            boxes[b] = a
            tick()
        }

        /// Clicking a box flips the character between its brackets (§5). In a session it's a step of the notes' undo;
        /// otherwise it's written to the task as its own step, "Check Item" or "Uncheck Item".
        func toggleBox(_ at: Int) {
            guard let v = view, let l = document.line(at: at), l.kind == .task, l.box == at else { return }
            let t = v.string as NSString
            guard at < t.length else { return }
            let checking = t.character(at: at) == 32
            if checking {
                var a = boxes[at] ?? BoxAnimation()
                let now = Date.timeIntervalSinceReferenceDate
                a.checkAt = now
                a.popAt = now
                boxes[at] = a
            }
            if session != nil, v.window?.firstResponder === v {
                // The caret and the view stay where they are: the box may be far from the caret (§5).
                let sel = v.selectedRange()
                v.replace(NSRange(location: at, length: 1), checking ? "x" : " ", kind: .structure, select: sel, scroll: false)
            } else {
                let store = host.store
                let notes = t.replacingCharacters(in: NSRange(location: at, length: 1), with: checking ? "x" : " ")
                let a = actions
                let name = checking ? "Check Item" : "Uncheck Item"
                switch host.target {
                case .task(let id): a.undoable(name) { store.setNotes(id, notes, name: name, undoManager: a.undo) }
                case .list(let id): a.undoable(name) { store.setNotes(list: id, notes, name: name, undoManager: a.undo) }
                }
            }
            tick()
        }

        func boxState(_ b: Int) -> NotesBoxState {
            guard let a = boxes[b] else { return NotesBoxState() }
            let now = Date.timeIntervalSinceReferenceDate
            var s = NotesBoxState()
            let reduce = TK.CA.reduce
            // Hover: in on hoverIn (60 ms), out on hoverOut (85 ms).
            let hd = a.hoverTo > a.hoverFrom ? 0.06 : 0.085
            let ht = reduce ? 1 : min(1, (now - a.hoverAt) / hd)
            s.hover = a.hoverFrom + (a.hoverTo - a.hoverFrom) * CGFloat(ease(ht))
            // Press: down to 0.86 in 80 ms, back on snappy.
            if !reduce {
                if a.pressed {
                    s.scale = 1 - 0.14 * CGFloat(min(1, (now - a.pressAt) / 0.08))
                } else if let r = a.releaseAt, now - r < 0.3 {
                    s.scale = 0.86 + 0.14 * CGFloat(snappy((now - r) / 0.3))
                }
                if let p = a.popAt, now - p < 0.3 { s.scale *= 0.8 + 0.2 * CGFloat(snappy((now - p) / 0.3)) }
                // The check draws on over 160 ms after 40 (md:46).
                if let c = a.checkAt { s.check = CGFloat(min(1, max(0, (now - c - 0.04) / 0.16))) }
            }
            return s
        }

        private func ease(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

        /// `--ease-snappy` (tasks-v2.css:12), sampled.
        private func snappy(_ t: Double) -> Double {
            let k: [Double] = [0, 0.0617, 0.1976, 0.3564, 0.5094, 0.6423, 0.7503, 0.8334, 0.8945, 0.9376, 0.9666, 0.9852, 0.9964,
                               1.0025, 1.0054, 1.0063, 1.006, 1.0052, 1.0042, 1.0033, 1.0024, 1.0017, 1.0011, 1.0007, 1]
            let x = min(1, max(0, t)) * Double(k.count - 1)
            let i = min(k.count - 2, Int(x))
            return k[i] + (k[i + 1] - k[i]) * (x - Double(i))
        }

        /// Runs while boxes animate or marks fade in, redrawing what moves.
        private func tick() {
            let now = Date.timeIntervalSinceReferenceDate
            for b in boxes.keys { redrawBox(b) }
            if let ts = view?.textStorage, let lm = layout {
                // Marks appearing fade in over `icon` (100 ms) (md:21).
                fades.removeAll { now - $0.1 > 0.1 }
                lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: ts.length))
                for (r, t0) in fades where NSMaxRange(r) <= ts.length {
                    let k = CGFloat(ease(min(1, (now - t0) / 0.1)))
                    lm.addTemporaryAttribute(.foregroundColor, value: palette.inkQuiet.withAlphaComponent(k), forCharacterRange: r)
                }
            }
            // Finished box animations go.
            boxes = boxes.filter { b, a in
                a.pressed || hoveredBox == b || a.hoverTo > 0 && now - a.hoverAt < 0.2 || a.hoverTo == 0 && now - a.hoverAt < 0.2
                    || (a.releaseAt.map { now - $0 < 0.35 } ?? false) || (a.popAt.map { now - $0 < 0.35 } ?? false)
                    || (a.checkAt.map { now - $0 < 0.25 } ?? false)
            }
            let busy = !boxes.isEmpty && boxes.contains { b, a in a.pressed || now - a.hoverAt < 0.1 || (a.releaseAt.map { now - $0 < 0.35 } ?? false)
                || (a.popAt.map { now - $0 < 0.35 } ?? false) || (a.checkAt.map { now - $0 < 0.25 } ?? false) } || !fades.isEmpty
            if busy, ticker == nil {
                ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
            } else if !busy {
                ticker?.invalidate()
                ticker = nil
            }
        }

        private func redraw(_ r: NSRange) {
            guard let v = view, let lm = layout, let tc = v.textContainer, NSMaxRange(r) <= (v.string as NSString).length else { return }
            let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            let rect = lm.boundingRect(forGlyphRange: g, in: tc).offsetBy(dx: v.textContainerOrigin.x, dy: v.textContainerOrigin.y)
            v.setNeedsDisplay(rect.insetBy(dx: -2, dy: -4))
        }

        private func redrawBox(_ b: Int) {
            guard let v = view, let l = document.line(at: b), l.kind == .task, let f = layout?.fragment(l, first: true) else { return }
            let x = CGFloat(l.level) * NotesStyle.column
            v.setNeedsDisplay(CGRect(x: v.textContainerOrigin.x + x - 2, y: v.textContainerOrigin.y + f.minY - 2, width: 20, height: 20))
        }

        #if DEBUG
        /// `nbench:` (DebugScript): opening a 20,000-character note and typing 100 characters into it, in ms of app
        /// work (design/MARKDOWN.md §9). The task's notes are put back after; nothing is written.
        func benchmark() -> String {
            guard let v = view, let ts = v.textStorage, let lm = layout, let tc = v.textContainer else { return "no view" }
            let block = "## Heading\nSome **bold** and _italic_ text with a [link](https://example.com) and `code`.\n- [ ] item one\n- [x] item two\n> a quote\n```\nlet x = 1\n```\n"
            var note = ""
            while note.utf16.count < 20_000 { note += block }
            note = NotesTextView.prefix(note, 19_800)   // room for the 100 typed characters
            func ms(_ t0: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000 }
            var opens: [Double] = [], scans: [Double] = [], styles: [Double] = [], layouts: [Double] = [], loops: [Double] = []
            for _ in 0..<5 {
                ts.replaceCharacters(in: NSRange(location: 0, length: ts.length), with: "")
                pending = nil
                let t0 = DispatchTime.now().uptimeNanoseconds
                ts.replaceCharacters(in: NSRange(location: 0, length: 0), with: note)
                pending = nil
                let s0 = DispatchTime.now().uptimeNanoseconds
                document.update(ts.string)
                scans.append(ms(s0))
                let r0 = DispatchTime.now().uptimeNanoseconds
                restyleAll()
                styles.append(ms(r0))
                loops.append(lastRestyle.loop)
                let l0 = DispatchTime.now().uptimeNanoseconds
                _ = v.fittingHeight(width: v.wrapWidth)
                layouts.append(ms(l0))
                opens.append(ms(t0))
            }
            v.window?.makeFirstResponder(v)
            let mid = (note as NSString).length / 2
            v.setSelectedRange(NSRange(location: mid, length: 0))
            var keys: [Double] = []
            let before = ts.length
            for i in 0..<100 {
                let t0 = DispatchTime.now().uptimeNanoseconds
                v.insertText(i % 10 == 9 ? " " : "a", replacementRange: NSRange(location: NSNotFound, length: 0))
                lm.ensureLayout(forCharacterRange: NSRange(location: v.selectedRange().location, length: 0))
                keys.append(ms(t0))
            }
            _ = tc
            let typed = ts.length - before
            let responder = v.window?.firstResponder === v
            // Put the task's notes back without committing anything.
            session = nil
            v.window?.makeFirstResponder(nil)
            shown = nil
            apply(force: true)
            func med(_ a: [Double]) -> Double { a.sorted()[a.count / 2] }
            let slow = keys.enumerated().sorted { $0.element > $1.element }.prefix(4).map { String(format: "#%d %.2f", $0.offset, $0.element) }.joined(separator: ", ")
            return "slowest keys: \(slow); " + String(format: "open 20k: median %.2f ms (scan %.3f, style %.2f of which loop %.2f, layout %.2f ms); keystroke: median %.3f ms, max %.3f ms, typed %d, responder %@",
                          med(opens), med(scans), med(styles), med(loops), med(layouts), med(keys), keys.max() ?? 0, typed,
                          responder ? "yes" : "no")
        }
        #endif

        // MARK: Accessibility

        /// The notes as they read: no marks; dots and numbers as text; code as typed, without its fences.
        func readingText() -> String {
            document.lines.compactMap { l -> String? in
                switch l.kind {
                case .fence: return nil
                case .code: return String(utf16CodeUnits: Array(document.units[l.start..<l.end]), count: l.end - l.start)
                case .blank: return ""
                case .bullet: return "• " + document.plain(l)
                case .ordered: return "\(document.numbers[l.index] ?? l.number). " + document.plain(l)
                default: return document.plain(l)
                }
            }.joined(separator: "\n")
        }

        func boxElements(in v: NotesTextView) -> [Any] {
            guard let lm = layout else { return [] }
            return document.lines.filter { $0.kind == .task }.compactMap { l in
                guard let f = lm.fragment(l, first: true) else { return nil }
                let e = NotesBoxElement()
                e.setAccessibilityRole(.checkBox)
                let text = document.plain(l).trimmingCharacters(in: .whitespaces)
                e.setAccessibilityLabel(text.isEmpty ? "item" : text)
                e.setAccessibilityValue(l.checked ? 1 : 0)
                e.setAccessibilityParent(v)
                let r = CGRect(x: v.textContainerOrigin.x + CGFloat(l.level) * NotesStyle.column, y: v.textContainerOrigin.y + f.minY, width: 16, height: 19)
                e.setAccessibilityFrameInParentSpace(r)
                let box = l.box
                e.toggle = { [weak self] in self?.toggleBox(box) }
                return e
            }
        }
    }
}
