import AppKit
import SwiftUI
import TasksCore

// The detail pane's notes (§7 Notes, css:276–281, dc:1635–1655): read as inline Markdown, edited as the raw text in the
// same font and place. One NSTextView does both, so switching never moves a line.

// MARK: - Inline Markdown (dc:481–497): bold, italic, `code` and links, line by line

enum InlineMarkdown {
    enum Kind: Equatable { case plain, bold, italic, code, link(String) }

    struct Segment: Equatable {
        var kind: Kind
        var text: String
    }

    private static let token = try! NSRegularExpression(
        pattern: #"(\*\*[^*\n]+\*\*|`[^`\n]+`|\[[^\]\n]+\]\([^)\s]+\)|\*[^*\n]+\*|_[^_\n]+_)"#)
    private static let link = try! NSRegularExpression(pattern: #"^\[([^\]]+)\]\(([^)]+)\)$"#)

    static func segments(_ src: String) -> [Segment] {
        let ns = src as NSString
        var out: [Segment] = []
        var last = 0
        for m in token.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last {
                out.append(.init(kind: .plain, text: ns.substring(with: NSRange(location: last, length: m.range.location - last))))
            }
            let tok = ns.substring(with: m.range) as NSString
            func inner(_ n: Int) -> String { tok.substring(with: NSRange(location: n, length: tok.length - 2 * n)) }
            if tok.hasPrefix("**") {
                out.append(.init(kind: .bold, text: inner(2)))
            } else if tok.hasPrefix("`") {
                out.append(.init(kind: .code, text: inner(1)))
            } else if tok.hasPrefix("["), let l = link.firstMatch(in: tok as String, range: NSRange(location: 0, length: tok.length)) {
                out.append(.init(kind: .link(tok.substring(with: l.range(at: 2))), text: tok.substring(with: l.range(at: 1))))
            } else {
                out.append(.init(kind: .italic, text: inner(1)))
            }
            last = NSMaxRange(m.range)
        }
        if last < ns.length { out.append(.init(kind: .plain, text: ns.substring(from: last))) }
        return out
    }
}

// MARK: - Type

extension NSAttributedString.Key {
    /// A `code` span: drawn on `fill-control`, padding 1 / 4, radius 4 (css:281).
    static let notesCode = NSAttributedString.Key("tasks.notes.code")
    /// A link's href; drawn `accent-text`, underlined 1pt at offset 2 (css:280).
    static let notesLink = NSAttributedString.Key("tasks.notes.link")
}

/// CSS line boxes in TextKit. The browser rounds the font's ascent and descent and splits the leading evenly (13/19
/// puts the baseline 14.5 down, measured in Chromium); TextKit puts a forced line height's extra space above the
/// glyphs. `baselineOffset` moves the glyphs up to where the browser has them.
@MainActor
enum LineBox {
    /// The baseline's distance from the top of a CSS line box `lineHeight` tall.
    static func cssBaseline(_ font: NSFont, lineHeight: CGFloat) -> CGFloat {
        let a = font.ascender.rounded(), d = (-font.descender).rounded()
        return a + (lineHeight - a - d) / 2
    }

    /// Where TextKit puts the baseline in a line forced to `lineHeight` (measured once per font and height).
    static func textKitBaseline(_ font: NSFont, lineHeight: CGFloat) -> CGFloat {
        let key = "\(font.fontName)|\(font.pointSize)|\(lineHeight)"
        if let b = cache[key] { return b }
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = lineHeight
        ps.maximumLineHeight = lineHeight
        let storage = NSTextStorage(string: "Xg", attributes: [.font: font, .paragraphStyle: ps])
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: 1000, height: 1000))
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        lm.ensureLayout(for: tc)
        let b = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY + lm.location(forGlyphAt: 0).y
        cache[key] = b
        return b
    }

    static func baselineOffset(_ font: NSFont, lineHeight: CGFloat) -> CGFloat {
        textKitBaseline(font, lineHeight: lineHeight) - cssBaseline(font, lineHeight: lineHeight)
    }

    static func paragraph(lineHeight: CGFloat) -> NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = lineHeight
        ps.maximumLineHeight = lineHeight
        return ps
    }

    private static var cache: [String: CGFloat] = [:]
}

/// The notes' text: 13/19 `ink` (css:276–277), tabs every 8 spaces like the browser's `tab-size: 8`.
@MainActor
enum NotesStyle {
    static let lineHeight: CGFloat = 19
    static var font: NSFont { TK.Font.body }

    static var paragraph: NSParagraphStyle {
        let ps = LineBox.paragraph(lineHeight: lineHeight)
        ps.tabStops = []
        ps.defaultTabInterval = 8 * (" " as NSString).size(withAttributes: [.font: font]).width
        return ps
    }

    static func base(_ tk: TK.Palette) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: tk.ink, .paragraphStyle: paragraph,
         .baselineOffset: LineBox.baselineOffset(font, lineHeight: lineHeight)]
    }

    static func placeholder(_ tk: TK.Palette) -> NSAttributedString {
        var a = base(tk)
        a[.foregroundColor] = tk.ink3
        return NSAttributedString(string: "Notes", attributes: a)
    }

    /// The reading view: inline Markdown, or "Notes" in `ink-tertiary` when there are none (css:278).
    static func reading(_ notes: String, _ tk: TK.Palette) -> NSAttributedString {
        guard !notes.isEmpty else { return placeholder(tk) }
        let base = base(tk)
        let out = NSMutableAttributedString()
        var codeRanges: [NSRange] = []
        for seg in InlineMarkdown.segments(notes) {
            var a = base
            switch seg.kind {
            case .plain: break
            case .bold: a[.font] = NSFont.systemFont(ofSize: font.pointSize, weight: .bold)
            case .italic: a[.font] = italic
            case .code:
                a[.font] = TK.Font.code
                a[.notesCode] = true
                // The mono font sits on the same baseline as the text around it.
                a[.baselineOffset] = LineBox.baselineOffset(font, lineHeight: lineHeight)
            case .link(let href):
                a[.foregroundColor] = tk.accentText
                a[.notesLink] = href
            }
            let start = out.length
            out.append(NSAttributedString(string: seg.text, attributes: a))
            if seg.kind == .code { codeRanges.append(NSRange(location: start, length: out.length - start)) }
        }
        // `padding: 0 4px` on an inline box: 4pt before and after the code's text, as kerning on the characters
        // either side of its start and on its last character.
        let s = out.string as NSString
        for r in codeRanges where r.length > 0 {
            if r.location > 0, s.character(at: r.location - 1) != 10 {
                out.addAttribute(.kern, value: codePad, range: NSRange(location: r.location - 1, length: 1))
            }
            out.addAttribute(.kern, value: codePad, range: NSRange(location: NSMaxRange(r) - 1, length: 1))
        }
        return out
    }

    nonisolated static let codePad: CGFloat = 4

    private static var italic: NSFont {
        let d = font.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: d, size: font.pointSize) ?? font
    }

    /// An href as typed; one without a scheme opens as https.
    static func url(_ href: String) -> URL? {
        guard let u = URL(string: href) else { return nil }
        if u.scheme != nil { return u }
        return URL(string: "https://" + href)
    }
}

// MARK: - Layout manager: code backgrounds and link underlines

/// Draws a `code` span's rounded fill (its content area, the mono font's rounded ascent and descent, plus 1 / 4
/// padding) and a link's 1pt underline 2pt under the baseline (`text-underline-offset: 2px`, measured in Chromium),
/// both under the glyphs, as the browser paints them.
final class NotesLayoutManager: NSLayoutManager {
    var codeFill: NSColor = TK.Palette.dark.fillControl
    var linkColor: NSColor = TK.Palette.dark.accentText

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, storage.length > 0 else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let mono = TK.Font.code
        let monoAscent = mono.ascender.rounded(), monoDescent = (-mono.descender).rounded()
        storage.enumerateAttribute(.notesCode, in: chars) { value, range, _ in
            guard value != nil else { return }
            codeFill.setFill()
            spans(of: range) { line, x0, x1, baseline, first, _ in
                let left = first ? max(line.minX, x0 - NotesStyle.codePad) : x0
                let r = CGRect(x: origin.x + left, y: origin.y + baseline - monoAscent - 1,
                               width: x1 - left, height: monoAscent + monoDescent + 2)
                NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            }
        }
        storage.enumerateAttribute(.notesLink, in: chars) { value, range, _ in
            guard value != nil else { return }
            linkColor.setFill()
            spans(of: range) { _, x0, x1, baseline, _, last in
                // The last glyph's kerning (a code span's padding) isn't underlined.
                let end = last ? x1 - trailingKern(range) : x1
                CGRect(x: origin.x + x0, y: origin.y + baseline + 2, width: end - x0, height: 1).fill()
            }
        }
    }

    private func trailingKern(_ range: NSRange) -> CGFloat {
        guard let storage = textStorage, range.length > 0 else { return 0 }
        return storage.attribute(.kern, at: NSMaxRange(range) - 1, effectiveRange: nil) as? CGFloat ?? 0
    }

    /// Each line's piece of `range`: its line fragment, the x span (container coordinates), the baseline, and whether
    /// it's the first / last piece.
    private func spans(of range: NSRange, _ body: (CGRect, CGFloat, CGFloat, CGFloat, Bool, Bool) -> Void) {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        withoutActuallyEscaping(body) { body in spans(glyphs, body) }
    }

    private func spans(_ glyphs: NSRange, _ body: @escaping (CGRect, CGFloat, CGFloat, CGFloat, Bool, Bool) -> Void) {
        enumerateLineFragments(forGlyphRange: glyphs) { rect, used, _, lineGlyphs, _ in
            let piece = NSIntersectionRange(glyphs, lineGlyphs)
            guard piece.length > 0 else { return }
            let x0 = rect.minX + self.location(forGlyphAt: piece.location).x
            let after = NSMaxRange(piece)
            var x1: CGFloat
            if after < NSMaxRange(lineGlyphs) {
                x1 = rect.minX + self.location(forGlyphAt: after).x
            } else {
                x1 = used.maxX
            }
            // A line ending in a newline: don't run past the last visible glyph.
            x1 = max(x0, x1)
            let baseline = rect.minY + self.location(forGlyphAt: piece.location).y
            body(rect, x0, x1, baseline, piece.location == glyphs.location, after == NSMaxRange(glyphs))
        }
    }
}

// MARK: - The text view

final class NotesTextView: NSTextView {
    enum Command { case escape, commandReturn, backtab }

    /// Reading (Markdown, presses start editing or open a link) or editing (the raw text).
    var reading = true
    /// Under an untitled new task: dimmed and deaf to the pointer (css:285–286).
    var inert = false { didSet { if inert != oldValue { window?.invalidateCursorRects(for: self) } } }
    var onReadingPress: (() -> Void)?
    var onCommand: ((Command) -> Void)?
    var onResign: (() -> Void)?
    var onLeaveWindow: (() -> Void)?
    var placeholder: NSAttributedString?
    /// The field's own undo while typing (§9), never the window's.
    private let notesUndo = UndoManager()

    override var undoManager: UndoManager? { notesUndo }
    override var acceptsFirstResponder: Bool { !reading && super.acceptsFirstResponder }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { inert ? nil : super.hitTest(point) }

    func clearUndo() { notesUndo.removeAllActions() }

    override func mouseDown(with event: NSEvent) {
        guard reading else { super.mouseDown(with: event); return }
        if let url = link(at: convert(event.locationInWindow, from: nil)) {
            NSWorkspace.shared.open(url)
            return
        }
        onReadingPress?()
    }

    override func rightMouseDown(with event: NSEvent) {
        if reading { return }
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !reading {
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == 53, mods.isEmpty { onCommand?(.escape); return }
            if event.keyCode == 36 || event.keyCode == 76, mods == .command { onCommand?(.commandReturn); return }
        }
        super.keyDown(with: event)
    }

    override func insertBacktab(_ sender: Any?) {
        if reading { super.insertBacktab(sender) } else { onCommand?(.backtab) }
    }

    override func cancelOperation(_ sender: Any?) {
        if reading { super.cancelOperation(sender) } else { onCommand?(.escape) }
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onResign?() }
        return ok
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { onLeaveWindow?() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // The textarea's placeholder while editing empty notes.
        if !reading, string.isEmpty, let placeholder {
            placeholder.draw(with: NSRect(x: textContainerOrigin.x, y: textContainerOrigin.y, width: bounds.width, height: NotesStyle.lineHeight),
                             options: [.usesLineFragmentOrigin])
        }
    }

    override func resetCursorRects() {
        if inert { return }
        guard reading else { super.resetCursorRects(); return }
        // `cursor: text` on the notes, `pointer` on links (css:278, 280).
        addCursorRect(visibleRect, cursor: .iBeam)
        for r in linkRects() { addCursorRect(r, cursor: .pointingHand) }
    }

    /// The link under `p` (view coordinates), if the press is on its text.
    func link(at p: NSPoint) -> URL? {
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage, ts.length > 0 else { return nil }
        let pt = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        var frac: CGFloat = 0
        let g = lm.glyphIndex(for: pt, in: tc, fractionOfDistanceThroughGlyph: &frac)
        guard lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc).contains(pt) else { return nil }
        let ci = lm.characterIndexForGlyph(at: g)
        guard ci < ts.length, let href = ts.attribute(.notesLink, at: ci, effectiveRange: nil) as? String else { return nil }
        return NotesStyle.url(href)
    }

    private func linkRects() -> [CGRect] {
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage, ts.length > 0 else { return [] }
        var rects: [CGRect] = []
        ts.enumerateAttribute(.notesLink, in: NSRange(location: 0, length: ts.length)) { v, r, _ in
            guard v != nil else { return }
            let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            lm.enumerateEnclosingRects(forGlyphRange: g, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { rect, _ in
                rects.append(rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y))
            }
        }
        return rects
    }

    /// The text's height at `width`: whole 19pt lines, at least one.
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
}

// MARK: - SwiftUI

/// The notes area: fills the space it's given (it's the pane's flexible part), reads or edits one task's notes, and
/// writes one `task.update` per editing session (§7).
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NotesTextView {
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
        v.isEditable = false
        v.isSelectable = false
        v.isVerticallyResizable = false
        v.isHorizontallyResizable = false
        v.textContainerInset = .zero
        v.isAutomaticQuoteSubstitutionEnabled = false
        v.isAutomaticDashSubstitutionEnabled = false
        v.isAutomaticTextReplacementEnabled = false
        v.isAutomaticSpellingCorrectionEnabled = false
        v.isContinuousSpellCheckingEnabled = false
        v.isGrammarCheckingEnabled = false
        v.smartInsertDeleteEnabled = false
        v.usesFindBar = false
        v.focusRingType = .none
        v.setAccessibilityLabel("Notes")
        v.delegate = context.coordinator
        let c = context.coordinator
        c.parent = self
        c.view = v
        v.onReadingPress = { [weak c] in c?.startEditing() }
        v.onCommand = { [weak c] in c?.command($0) }
        v.onResign = { [weak c] in c?.endEditing() }
        v.onLeaveWindow = { [weak c] in c?.endEditing() }
        refs.notes = c
        c.apply(force: true)
        return v
    }

    func updateNSView(_ v: NotesTextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        refs.notes = c
        v.inert = inert
        c.apply(force: false)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: NotesTextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 340
        let h = v.fittingHeight(width: w)
        return CGSize(width: w, height: max(h, proposal.height ?? 0))
    }

    static func dismantleNSView(_ v: NotesTextView, coordinator: Coordinator) {
        coordinator.endEditing()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesField!
        weak var view: NotesTextView?
        /// The editing session: whose notes, and what they were.
        private(set) var session: (id: EntityID, original: String)?
        private var shown: (source: String, dark: Bool)?
        private var actions: WindowActions { WindowActions(store: parent.store, window: parent.window) }

        /// Shows the reading view for the current notes (unless they're being edited).
        func apply(force: Bool) {
            guard let v = view, session == nil else { return }
            let tk = parent.palette
            if let lm = v.layoutManager as? NotesLayoutManager {
                lm.codeFill = tk.fillControl
                lm.linkColor = tk.accentText
            }
            v.insertionPointColor = tk.ink
            v.selectedTextAttributes = [.backgroundColor: tk.textSel]
            v.placeholder = NotesStyle.placeholder(tk)
            guard force || shown?.source != parent.notes || shown?.dark != tk.isDark else { return }
            shown = (parent.notes, tk.isDark)
            v.textStorage?.setAttributedString(NotesStyle.reading(parent.notes, tk))
            v.needsDisplay = true
            v.window?.invalidateCursorRects(for: v)
        }

        /// A press on the notes (not a link), or Return / Tab in the title: the raw text, caret at the end.
        func startEditing() {
            guard let v = view, let w = v.window, session == nil, !parent.inert else { return }
            let id = parent.id
            let raw = parent.store.projection.task(id)?.notes ?? ""
            let tk = parent.palette
            session = (id, raw)
            shown = nil
            v.reading = false
            v.isEditable = true
            v.isSelectable = true
            v.typingAttributes = NotesStyle.base(tk)
            v.textStorage?.setAttributedString(NSAttributedString(string: raw, attributes: NotesStyle.base(tk)))
            v.clearUndo()
            if parent.window.detailEditing != .notes { parent.window.detailEditing = .notes }
            if parent.window.focus != .detail { parent.window.focus = .detail }
            w.makeFirstResponder(v)
            v.setSelectedRange(NSRange(location: (raw as NSString).length, length: 0))
            v.window?.invalidateCursorRects(for: v)
            v.needsDisplay = true
            parent.onLayoutChange()
        }

        /// Esc, ⌘Return, ⇧Tab or a press elsewhere: one `task.update` if the text changed (§7).
        func endEditing() {
            guard let s = session, let v = view else { return }
            session = nil
            let text = v.string
            v.reading = true
            v.isEditable = false
            v.isSelectable = false
            v.setSelectedRange(NSRange(location: 0, length: 0))
            if parent.window.detailEditing == .notes { parent.window.detailEditing = nil }
            let store = parent.store
            if let t = store.projection.task(s.id), !t.deleted, t.notes != text {
                let a = actions
                a.undoable("Edit Notes") { store.setNotes(s.id, text, name: "Edit Notes", undoManager: a.undo) }
            }
            // Read what was written, not the model (it may update a moment later).
            shown = (text, parent.palette.isDark)
            v.textStorage?.setAttributedString(NotesStyle.reading(text, parent.palette))
            v.window?.invalidateCursorRects(for: v)
            v.needsDisplay = true
            parent.onLayoutChange()
        }

        func command(_ c: NotesTextView.Command) {
            switch c {
            case .escape, .commandReturn:
                // Done: keeps the text; the keys go to the list (§7).
                endEditing()
                actions.focus(.list)
            case .backtab:
                endEditing()
                parent.refs.focusTitle(.all)
            }
        }

        func textDidChange(_ notification: Notification) { parent.onLayoutChange() }
    }
}
