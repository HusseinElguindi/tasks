import AppKit
import TasksCore

// The notes' Markdown, drawn (design/MARKDOWN.md): the text storage is the source, character for character; styling
// is attributes laid on one line at a time; marks the caret isn't near are hidden glyphs; dots, numbers, boxes, the
// quote bar and code blocks' backgrounds are drawn by the layout manager.

extension NSAttributedString.Key {
    /// A mark that isn't showing: its glyphs are null, so it takes no space (§4).
    static let mdHidden = NSAttributedString.Key("tasks.md.hidden")
    /// Inline code: drawn on `fill-control`, padding 1 / 4, radius 4 (md:14).
    static let mdCode = NSAttributedString.Key("tasks.md.code")
    /// A link's text: its address, underlined by the layout manager (md:16–18).
    static let mdLink = NSAttributedString.Key("tasks.md.link")
    /// A mark (`**`, `_`, `` ` ``, `[`, `](…)`, `# `, `> `, a fence): it fades in when it appears (md:21).
    static let mdMark = NSAttributedString.Key("tasks.md.mark")
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
        let key = OffsetKey(font: ObjectIdentifier(font), lineHeight: lineHeight)
        if let o = offsets[key] { return o }
        let o = textKitBaseline(font, lineHeight: lineHeight) - cssBaseline(font, lineHeight: lineHeight)
        offsets[key] = o
        return o
    }

    private struct OffsetKey: Hashable { var font: ObjectIdentifier; var lineHeight: CGFloat }
    /// Keyed by the font object: the notes' fonts are shared statics, so this is a pointer compare per lookup.
    private static var offsets: [OffsetKey: CGFloat] = [:]

    static func paragraph(lineHeight: CGFloat) -> NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = lineHeight
        ps.maximumLineHeight = lineHeight
        return ps
    }

    private static var cache: [String: CGFloat] = [:]
}

/// Type and metrics (§8, md:6–65).
@MainActor
enum NotesStyle {
    static let lineHeight: CGFloat = 19
    static let headingLineHeight: CGFloat = 20
    static let codeLineHeight: CGFloat = 17
    /// A list level and the quote's indent: the checkbox's 16pt column and its 10pt gap (`MD_COL`, dc:508).
    static let column: CGFloat = 26
    static let codePad: CGFloat = 4
    static let blockPadX: CGFloat = 10
    static let blockPadY: CGFloat = 6
    static let blockMargin: CGFloat = 2
    static let maxLength = 20_000
    static let nearLength = 18_000

    static var body: NSFont { bodyFont }
    static let semibold = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let heading = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static var mono: NSFont { monoFont }
    static let number = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    /// A hidden fence line's font: its line is as good as gone.
    static let collapsed = NSFont.systemFont(ofSize: 0.1)

    /// The line's font with bold and italic laid on, one shared instance per combination.
    static func font(_ base: NSFont, bold: Bool, italic: Bool) -> NSFont {
        guard bold || italic else { return base }
        let key = FontKey(base: ObjectIdentifier(base), bold: bold, italic: italic)
        if let f = variants[key] { return f }
        var f = bold ? NSFont.systemFont(ofSize: base.pointSize, weight: .semibold) : base
        if italic {
            f = NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(.italic)), size: f.pointSize) ?? f
        }
        variants[key] = f
        return f
    }

    private struct FontKey: Hashable { var base: ObjectIdentifier; var bold: Bool; var italic: Bool }
    private static var variants: [FontKey: NSFont] = [:]
    private static let bodyFont = TK.Font.body
    private static let monoFont = TK.Font.code

    /// One paragraph style per combination, shared.
    static func paragraph(lineHeight: CGFloat, indent: CGFloat = 0, before: CGFloat = 0, after: CGFloat = 0,
                          tail: CGFloat = 0) -> NSParagraphStyle {
        let key = ParagraphKey(lineHeight: lineHeight, indent: indent, before: before, after: after, tail: tail)
        if let p = paragraphs[key] { return p }
        let ps = LineBox.paragraph(lineHeight: lineHeight)
        ps.firstLineHeadIndent = indent
        ps.headIndent = indent
        ps.tailIndent = tail
        ps.paragraphSpacingBefore = before
        ps.paragraphSpacing = after
        ps.tabStops = []
        ps.defaultTabInterval = 4 * (" " as NSString).size(withAttributes: [.font: body]).width   // tab-size: 4
        ps.lineBreakMode = .byWordWrapping
        paragraphs[key] = ps
        return ps
    }

    private struct ParagraphKey: Hashable {
        var lineHeight, indent, before, after, tail: CGFloat
    }
    private static var paragraphs: [ParagraphKey: NSParagraphStyle] = [:]

    static func base(_ tk: TK.Palette) -> [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: tk.ink, .paragraphStyle: paragraph(lineHeight: lineHeight),
         .baselineOffset: LineBox.baselineOffset(body, lineHeight: lineHeight)]
    }

    static func placeholder(_ tk: TK.Palette) -> NSAttributedString {
        var a = base(tk)
        a[.foregroundColor] = tk.inkTertiary
        return NSAttributedString(string: "Notes", attributes: a)
    }

    /// An address as typed; one without a scheme opens as https, a bare email as mailto (`mdNormalizeUrl`, dc:632).
    static func url(_ href: String) -> URL? {
        let h = href.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return nil }
        if h.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*:"#, options: .regularExpression) != nil { return URL(string: h) }
        if h.range(of: #"^[^\s@/]+@[^\s@/]+\.[a-zA-Z]{2,}$"#, options: .regularExpression) != nil { return URL(string: "mailto:" + h) }
        return URL(string: "https://" + h)
    }

    /// The tooltip's text: the address without its scheme (dc:2306).
    static func tip(_ href: String) -> String {
        var s = href
        for p in ["https://www.", "http://www.", "https://", "http://", "mailto:"] where s.hasPrefix(p) {
            s.removeFirst(p.count)
            break
        }
        return s
    }
}

// MARK: - The document: lines, numbering, what's revealed

/// The notes' parsed lines and everything drawing needs from them, rebuilt (one linear pass) on every text change.
@MainActor
final class NotesDocument {
    private(set) var doc = Markdown.Document()
    private(set) var units: [UInt16] = []
    /// An ordered item's shown number: lists number themselves from their first item (dc:2293); TasksCore's
    /// `Markdown.Document.shownNumbers`.
    private(set) var numbers: [Int: Int] = [:]
    /// The selection that shows marks; nil at rest or while the button is down (§4).
    var reveal: NSRange?

    func update(_ string: String) {
        units = Array(string.utf16)
        doc = units.withUnsafeBufferPointer { Markdown.parse($0) }
        numbers = doc.shownNumbers
    }

    var lines: [Markdown.Line] { doc.lines }

    func line(at offset: Int) -> Markdown.Line? { doc.line(at: offset) }

    /// The lines a range touches, its ends included.
    func lines(touching r: NSRange) -> ClosedRange<Int>? {
        guard let a = line(at: r.location), let b = line(at: NSMaxRange(r)) else { return nil }
        return a.index...b.index
    }

    func touches(_ a: Int, _ b: Int) -> Bool {
        guard let s = reveal else { return false }
        return s.location <= b && NSMaxRange(s) >= a
    }

    func blockShown(_ i: Int) -> Bool {
        let b = doc.blocks[i]
        return touches(b.start, b.end)
    }

    /// The first and last lines of a block that show (the fences only while it's revealed).
    func visibleLines(ofBlock i: Int) -> ClosedRange<Int>? {
        let b = doc.blocks[i]
        if blockShown(i) { return b.first...b.last }
        let first = b.first + 1, last = b.closed ? b.last - 1 : b.last
        return first <= last ? first...last : nil
    }

    func tokens(_ l: Markdown.Line) -> [Markdown.Token] {
        units.withUnsafeBufferPointer { Markdown.inline($0, l.textStart, l.end) }
    }

    func plain(_ l: Markdown.Line) -> String {
        units.withUnsafeBufferPointer { Markdown.plain($0, l.textStart, l.end) }
    }
}

// MARK: - Styling one line

@MainActor
enum NotesStyler {
    /// Lays a line's attributes over its characters (and its newline): font, color, paragraph, the inline styles, and
    /// which marks are hidden, from the line's kind and whether the selection is near.
    static func style(_ l: Markdown.Line, _ d: NotesDocument, _ ts: NSTextStorage, _ tk: TK.Palette) {
        let length = ts.length
        let paraEnd = min(length, l.end + 1)
        guard paraEnd > l.start || l.start == length else { return }
        let first = l.index == 0
        var font = NotesStyle.body
        var color = tk.ink
        var lh = NotesStyle.lineHeight
        var para: NSParagraphStyle
        switch l.kind {
        case .heading1:
            font = NotesStyle.heading
            lh = NotesStyle.headingLineHeight
            para = NotesStyle.paragraph(lineHeight: lh, before: first ? 0 : 6)
        case .heading2:
            font = NotesStyle.semibold
            para = NotesStyle.paragraph(lineHeight: lh, before: first ? 0 : 4)
        case .bullet, .ordered, .task:
            para = NotesStyle.paragraph(lineHeight: lh, indent: CGFloat(l.level + 1) * NotesStyle.column)
            if l.kind == .task && l.checked { color = tk.inkTertiary }
        case .quote:
            color = tk.inkSecondary
            para = NotesStyle.paragraph(lineHeight: lh, indent: NotesStyle.column)
        case .fence, .code:
            font = NotesStyle.mono
            lh = NotesStyle.codeLineHeight
            let vis = d.visibleLines(ofBlock: l.block)
            let before: CGFloat = vis?.lowerBound == l.index ? NotesStyle.blockMargin + NotesStyle.blockPadY : 0
            let after: CGFloat = vis?.upperBound == l.index ? NotesStyle.blockMargin + NotesStyle.blockPadY : 0
            para = NotesStyle.paragraph(lineHeight: lh, indent: NotesStyle.blockPadX, before: before, after: after,
                                        tail: -NotesStyle.blockPadX)
            if l.kind == .fence { color = tk.inkQuiet }
        case .paragraph, .blank:
            para = NotesStyle.paragraph(lineHeight: lh)
        }
        let offset = LineBox.baselineOffset(font, lineHeight: lh)
        let whole = NSRange(location: l.start, length: paraEnd - l.start)
        ts.setAttributes([.font: font, .foregroundColor: color, .paragraphStyle: para, .baselineOffset: offset], range: whole)

        if l.kind == .fence {
            if !d.blockShown(l.block) {
                // Its line takes (next to) no room: a 0.1pt line of zero-advance glyphs.
                ts.addAttributes([.font: NotesStyle.collapsed, .paragraphStyle: NotesStyle.paragraph(lineHeight: 0.1),
                                  .baselineOffset: 0], range: whole)
                // Never the newline: hidden, it would stop breaking the paragraph and join the next line to this one.
                ts.addAttribute(.mdHidden, value: true, range: l.range)
            } else {
                ts.addAttribute(.mdMark, value: true, range: l.range)
            }
            return
        }
        guard l.kind != .code, l.kind != .blank, l.end > l.start else { return }

        // The prefix: never shown for list items (the dot, number or box is the mark); `# ` and `> ` while the
        // selection is on the line.
        if l.prefix > 0 {
            let pr = NSRange(location: l.start, length: l.prefix)
            var a: [NSAttributedString.Key: Any] = [.font: NotesStyle.body, .foregroundColor: tk.inkQuiet, .mdMark: true,
                                                    .baselineOffset: LineBox.baselineOffset(NotesStyle.body, lineHeight: lh)]
            if l.isListItem || !d.touches(l.start, l.end) { a[.mdHidden] = true }
            ts.addAttributes(a, range: pr)
        }
        guard l.textStart < l.end else { return }
        // A box being typed (`- [`, `- [ `, `- [x`): the dot, and what's typed of the box as faint marks while the
        // selection is on the line, until `]` makes it the box (§5, the user, 2026-11-01).
        if l.partialBox && d.touches(l.start, l.end) {
            ts.addAttributes([.foregroundColor: tk.inkQuiet, .mdMark: true], range: NSRange(location: l.textStart, length: l.end - l.textStart))
            return
        }

        // Inline styles, as flags per character, then laid as runs. Most lines have no mark characters at all.
        let n = l.end - l.textStart
        var marked = false
        for i in l.textStart..<l.end {
            let c = d.units[i]
            if c == 42 || c == 95 || c == 96 || c == 91 || c == 104 { marked = true; break }
        }
        if !marked {
            if l.kind == .task && l.checked {
                ts.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: tk.inkQuiet],
                                 range: NSRange(location: l.textStart, length: n))
            }
            return
        }
        var flags = [UInt8](repeating: 0, count: n)
        var hrefs: [(Range<Int>, String)] = []
        var codes: [(Markdown.Token, Bool)] = []   // code token, its marks shown
        var marks: [(Range<Int>, Bool)] = []   // range, shown
        let bold: UInt8 = 1, ital: UInt8 = 2, code: UInt8 = 4, link: UInt8 = 8
        func set(_ r: Range<Int>, _ f: UInt8) { for i in r { flags[i - l.textStart] |= f } }
        for t in d.tokens(l) {
            let shown = d.touches(t.range.lowerBound, t.range.upperBound)
            switch t.kind {
            case .bold: set(t.inner, bold)
            case .italic: set(t.inner, ital)
            case .code:
                set(t.inner, code)
                codes.append((t, shown))
            case .link, .url:
                set(t.inner, link)
                hrefs.append((t.inner, String(utf16CodeUnits: Array(d.units[t.target]), count: t.target.count)))
            }
            if t.range.lowerBound < t.inner.lowerBound { marks.append((t.range.lowerBound..<t.inner.lowerBound, shown)) }
            if t.inner.upperBound < t.range.upperBound { marks.append((t.inner.upperBound..<t.range.upperBound, shown)) }
        }
        var i = 0
        while i < n {
            let f = flags[i]
            var j = i + 1
            while j < n && flags[j] == f { j += 1 }
            if f != 0 {
                var a: [NSAttributedString.Key: Any] = [:]
                var rf = font
                if f & code != 0 {
                    rf = NotesStyle.mono
                    a[.mdCode] = true
                } else {
                    rf = NotesStyle.font(rf, bold: f & bold != 0, italic: f & ital != 0)
                }
                if rf != font { a[.font] = rf }
                if f & link != 0 { a[.foregroundColor] = l.kind == .task && l.checked ? tk.inkTertiary : tk.accentText }
                if !a.isEmpty { ts.addAttributes(a, range: NSRange(location: l.textStart + i, length: j - i)) }
            }
            i = j
        }
        // Links are drawn and opened here, not by NSTextView's `.link` (its own underline and click handling).
        for (r, href) in hrefs { ts.addAttribute(.mdLink, value: href, range: NSRange(location: r.lowerBound, length: r.count)) }
        for (r, shown) in marks {
            let monoMark = r.count == 1 && d.units[r.lowerBound] == 96
            var a: [NSAttributedString.Key: Any] = [.font: monoMark ? NotesStyle.mono : NotesStyle.body, .foregroundColor: tk.inkQuiet,
                                                    .mdMark: true]
            if !shown { a[.mdHidden] = true }
            let nr = NSRange(location: r.lowerBound, length: r.count)
            ts.removeAttribute(.mdCode, range: nr)
            ts.removeAttribute(.mdLink, range: nr)
            ts.addAttributes(a, range: nr)
        }
        // `padding: 1px 4px` on inline code: 4pt before its text (as kerning on the glyph before it that shows) and
        // after it (on its last character); the box is drawn around both (md:14).
        for (t, shown) in codes where t.inner.count > 0 {
            // The glyph before the code's text that shows: its opening backtick, or the character before that.
            var before = shown ? t.inner.lowerBound - 1 : t.range.lowerBound - 1
            if !shown {
                while before >= l.textStart, ts.attribute(.mdHidden, at: before, effectiveRange: nil) != nil { before -= 1 }
            }
            if before >= l.start { ts.addAttribute(.kern, value: NotesStyle.codePad, range: NSRange(location: before, length: 1)) }
            ts.addAttribute(.kern, value: NotesStyle.codePad, range: NSRange(location: t.inner.upperBound - 1, length: 1))
        }
        // A checked item reads like a done task: struck through in ink-quaternary (md:51).
        if l.kind == .task && l.checked {
            ts.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: tk.inkQuiet],
                             range: NSRange(location: l.textStart, length: n))
        }
    }
}

// MARK: - Layout manager: hidden marks, collapsed fences, drawn decorations

/// What the layout manager draws the gutter from: the boxes' states and the hovered link.
@MainActor
protocol NotesDecorations: AnyObject {
    var document: NotesDocument { get }
    var palette: TK.Palette { get }
    func boxState(_ offset: Int) -> NotesBoxState
    var hoveredLink: NSRange? { get }
}

struct NotesBoxState {
    /// 0 at rest, 1 hovered (the ring goes ink-secondary).
    var hover: CGFloat = 0
    /// The press's scale (0.86 down, back on snappy).
    var scale: CGFloat = 1
    /// How much of the check is drawn (160 ms when checked).
    var check: CGFloat = 1
}

final class NotesLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    weak var decorations: (any NotesDecorations)?

    override init() {
        super.init()
        delegate = self
        allowsNonContiguousLayout = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // Hidden marks take no space and aren't drawn (§9 Hiding marks).
    func layoutManager(_ lm: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard let ts = lm.textStorage, range.length > 0 else { return 0 }
        let first = characterIndexes[0], last = characterIndexes[range.length - 1]
        var hidden: [NSRange] = []
        ts.enumerateAttribute(.mdHidden, in: NSRange(location: first, length: last - first + 1)) { v, r, _ in
            if v != nil { hidden.append(r) }
        }
        guard !hidden.isEmpty else { return 0 }
        let p = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: range.length)
        defer { p.deallocate() }
        var h = 0
        for i in 0..<range.length {
            let c = characterIndexes[i]
            while h < hidden.count && NSMaxRange(hidden[h]) <= c { h += 1 }
            p[i] = h < hidden.count && hidden[h].location <= c ? .controlCharacter : props[i]
        }
        lm.setGlyphs(glyphs, properties: p, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
        return range.length
    }

    // Hidden marks are zero-advance control glyphs, not null ones: null glyphs at the start of a paragraph were laid
    // on the line before it, which moved its first line's paragraph spacing (a heading's 6pt) and its gutter.
    func layoutManager(_ lm: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        guard let ts = lm.textStorage, charIndex < ts.length, ts.attribute(.mdHidden, at: charIndex, effectiveRange: nil) != nil else { return action }
        return .zeroAdvancement
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        let me = UnsafeSendableBox(self)
        MainActor.assumeIsolated { me.value.drawDecorations(glyphsToShow, origin) }
    }

    @MainActor
    private func drawDecorations(_ glyphs: NSRange, _ origin: NSPoint) {
        guard let d = decorations, let ts = textStorage, let tc = textContainers.first, ts.length > 0 else { return }
        let tk = d.palette
        let doc = d.document
        let chars = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        guard let range = doc.lines(touching: chars) else { return }
        let width = tc.containerSize.width

        // Code blocks: fill-control, radius 6, 6 / 10 padding, full width (md:61–65).
        var drawnBlocks = Set<Int>()
        for i in range where doc.lines[i].block >= 0 && !drawnBlocks.contains(doc.lines[i].block) {
            let b = doc.lines[i].block
            drawnBlocks.insert(b)
            guard let vis = doc.visibleLines(ofBlock: b), let top = fragment(doc.lines[vis.lowerBound], first: true),
                  let bottom = fragment(doc.lines[vis.upperBound], first: false) else { continue }
            // The fragments are the text's (their 8pt spacing taken off): the box is 6 beyond them, the 2 left outside.
            let y0 = top.minY - NotesStyle.blockPadY, y1 = bottom.maxY + NotesStyle.blockPadY
            tk.fillControl.setFill()
            NSBezierPath(roundedRect: CGRect(x: origin.x, y: origin.y + y0, width: width, height: y1 - y0), xRadius: 6, yRadius: 6).fill()
        }

        // Quote bars: 2pt fill-strong at x 7, inset 2 at a run's ends (md:55–58).
        for i in range where doc.lines[i].kind == .quote {
            guard let top = fragment(doc.lines[i], first: true), let bottom = fragment(doc.lines[i], first: false) else { continue }
            let firstOfRun = i == 0 || doc.lines[i - 1].kind != .quote
            let lastOfRun = i == doc.lines.count - 1 || doc.lines[i + 1].kind != .quote
            let y0 = top.minY + (firstOfRun ? 2 : 0), y1 = bottom.maxY - (lastOfRun ? 2 : 0)
            tk.fillStrong.setFill()
            let r = CGRect(x: origin.x + 7, y: origin.y + y0, width: 2, height: y1 - y0)
            NSBezierPath(roundedRect: r, xRadius: firstOfRun || lastOfRun ? 1 : 0, yRadius: firstOfRun || lastOfRun ? 1 : 0).fill()
        }

        // Inline code backgrounds and link underlines, under the glyphs.
        let mono = NotesStyle.mono
        let monoAscent = mono.ascender.rounded(), monoDescent = (-mono.descender).rounded()
        ts.enumerateAttribute(.mdCode, in: chars) { v, r, _ in
            guard v != nil else { return }
            tk.fillControl.setFill()
            spans(of: r) { line, x0, x1, baseline, first, last in
                let left = first ? max(line.minX, x0 - NotesStyle.codePad) : x0
                let right = x1
                let rr = CGRect(x: origin.x + left, y: origin.y + baseline - monoAscent - 1, width: right - left,
                                height: monoAscent + monoDescent + 2)
                NSBezierPath(roundedRect: rr, xRadius: 4, yRadius: 4).fill()
            }
        }
        let hovered = d.hoveredLink
        ts.enumerateAttribute(.mdLink, in: chars) { v, r, _ in
            guard v != nil else { return }
            let full = hovered.map { NSIntersectionRange($0, r).length > 0 } ?? false
            let done = (ts.attribute(.foregroundColor, at: r.location, effectiveRange: nil) as? NSColor) == tk.inkTertiary
            let c = done ? tk.inkTertiary : tk.accentText
            (full ? c : c.withAlphaComponent(0.4)).setFill()
            spans(of: r) { _, x0, x1, baseline, _, _ in
                CGRect(x: origin.x + x0, y: origin.y + baseline + 2, width: x1 - x0, height: 1).fill()
            }
        }

        // The gutter: dots, numbers and boxes in the 16pt column of each level (md:32–49).
        for i in range {
            let l = doc.lines[i]
            guard l.isListItem, let f = fragment(l, first: true) else { continue }
            let x = origin.x + CGFloat(l.level) * NotesStyle.column
            let y = origin.y + f.minY
            switch l.kind {
            case .bullet:
                let r = CGRect(x: x + 5.5, y: y + 7, width: 5, height: 5)
                if l.level % 2 == 1 {
                    tk.inkSecondary.setStroke()
                    let p = NSBezierPath(ovalIn: r.insetBy(dx: 0.625, dy: 0.625))
                    p.lineWidth = 1.25
                    p.stroke()
                } else {
                    tk.inkSecondary.setFill()
                    NSBezierPath(ovalIn: r).fill()
                }
            case .ordered:
                let text = "\(doc.numbers[l.index] ?? l.number)\(Character(UnicodeScalar(UInt8(l.delimiter))))" as NSString
                let a: [NSAttributedString.Key: Any] = [.font: NotesStyle.number, .foregroundColor: tk.inkSecondary]
                let w = text.size(withAttributes: a).width
                let base = LineBox.cssBaseline(NotesStyle.number, lineHeight: NotesStyle.lineHeight)
                text.draw(at: CGPoint(x: x + 18 - w, y: y + base - NotesStyle.number.ascender), withAttributes: a)
            case .task:
                drawBox(l, at: CGPoint(x: x + 2, y: y + 3.5), d.boxState(l.box), tk)
            default:
                break
            }
        }
    }

    /// A 12pt square, radius 3.5: a 1.25 `line-field` ring (`ink-secondary` hovered); checked, an `ink-tertiary` fill
    /// and a white check (md:39–50).
    @MainActor
    private func drawBox(_ l: Markdown.Line, at p: CGPoint, _ s: NotesBoxState, _ tk: TK.Palette) {
        var r = CGRect(x: p.x, y: p.y, width: 12, height: 12)
        if s.scale != 1 { r = r.insetBy(dx: 6 * (1 - s.scale), dy: 6 * (1 - s.scale)) }
        let radius = 3.5 * s.scale
        if l.checked {
            tk.inkTertiary.setFill()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
            guard s.check > 0 else { return }
            let k = r.width / 12
            let ck = NSBezierPath()
            // M3.8 8.4l2.7 2.7 5.7-6.2 in a 16 box, drawn 9pt square, centered.
            let s9 = 9 * k / 16, o = CGPoint(x: r.midX - 4.5 * k, y: r.midY - 4.5 * k)
            let pts = [CGPoint(x: 3.8, y: 8.4), CGPoint(x: 6.5, y: 11.1), CGPoint(x: 12.2, y: 4.9)].map {
                CGPoint(x: o.x + $0.x * s9, y: o.y + $0.y * s9)
            }
            ck.move(to: pts[0])
            if s.check >= 1 {
                ck.line(to: pts[1])
                ck.line(to: pts[2])
            } else {
                // Drawn on: the first leg, then the second, by length.
                let l1 = hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y), l2 = hypot(pts[2].x - pts[1].x, pts[2].y - pts[1].y)
                let want = (l1 + l2) * s.check
                if want <= l1 {
                    ck.line(to: CGPoint(x: pts[0].x + (pts[1].x - pts[0].x) * want / l1, y: pts[0].y + (pts[1].y - pts[0].y) * want / l1))
                } else {
                    ck.line(to: pts[1])
                    let t = (want - l1) / l2
                    ck.line(to: CGPoint(x: pts[1].x + (pts[2].x - pts[1].x) * t, y: pts[1].y + (pts[2].y - pts[1].y) * t))
                }
            }
            ck.lineWidth = 2.4 * s9
            ck.lineCapStyle = .round
            ck.lineJoinStyle = .round
            tk.onAccent.setStroke()
            ck.stroke()
        } else {
            let ring = s.hover > 0 ? blend(tk.lineField, tk.inkSecondary, s.hover) : tk.lineField
            ring.setStroke()
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.625, dy: 0.625), xRadius: radius - 0.625, yRadius: radius - 0.625)
            path.lineWidth = 1.25
            path.stroke()
        }
    }

    private func blend(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return t < 0.5 ? a : b }
        return NSColor(srgbRed: x.redComponent + (y.redComponent - x.redComponent) * t,
                       green: x.greenComponent + (y.greenComponent - x.greenComponent) * t,
                       blue: x.blueComponent + (y.blueComponent - x.blueComponent) * t, alpha: 1)
    }

    /// A line's first or last line fragment, in container coordinates, without its paragraph spacing.
    @MainActor
    func fragment(_ l: Markdown.Line, first: Bool) -> CGRect? {
        guard let ts = textStorage, ts.length > 0 else { return nil }
        if l.start >= ts.length { return extraLineFragmentRect.isEmpty ? nil : extraLineFragmentRect }
        // Anchored on a character that shows: a line's hidden prefix reports the line before it.
        let ci: Int
        if first {
            ci = l.textStart < l.end ? l.textStart : (l.end < ts.length ? l.end : l.start)
        } else {
            ci = l.end > l.textStart ? l.end - 1 : (l.end < ts.length ? l.end : l.start)
        }
        let g = glyphIndexForCharacter(at: ci)
        guard g < numberOfGlyphs else { return nil }
        var r = lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        let ps = ts.attribute(.paragraphStyle, at: ci, effectiveRange: nil) as? NSParagraphStyle
        if first, let b = ps?.paragraphSpacingBefore, b > 0, r.height > b {
            r.origin.y += b
            r.size.height -= b
        }
        if !first, let a = ps?.paragraphSpacing, a > 0, r.height > a { r.size.height -= a }
        return r
    }

    /// Each line's piece of `range`: its line fragment, the x span (container coordinates), the baseline, and whether
    /// it's the first / last piece.
    private func spans(of range: NSRange, _ body: (CGRect, CGFloat, CGFloat, CGFloat, Bool, Bool) -> Void) {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        withoutActuallyEscaping(body) { body in
            enumerateLineFragments(forGlyphRange: glyphs) { rect, used, _, lineGlyphs, _ in
                let piece = NSIntersectionRange(glyphs, lineGlyphs)
                guard piece.length > 0 else { return }
                let x0 = rect.minX + self.location(forGlyphAt: piece.location).x
                let after = NSMaxRange(piece)
                var x1 = after < NSMaxRange(lineGlyphs) ? rect.minX + self.location(forGlyphAt: after).x : used.maxX
                x1 = max(x0, x1)
                let baseline = rect.minY + self.location(forGlyphAt: piece.location).y
                body(rect, x0, x1, baseline, piece.location == glyphs.location, after == NSMaxRange(glyphs))
            }
        }
    }
}
