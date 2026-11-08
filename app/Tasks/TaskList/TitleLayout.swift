import AppKit

/// The large title's type and measure (§23; design/TITLE-RENAME.md, direction B): 20/26 semibold `ink` with −0.2
/// tracking, wrapping in the title line's width. One field draws it at rest and while it's renamed, with these
/// attributes in both, so editing changes nothing on screen but the caret and the selection. The layout leaves room for
/// as many lines as `measure` counts.
enum TitleLayout {
    nonisolated(unsafe) static let font: NSFont = NSFont.systemFont(ofSize: 20, weight: .semibold)   // .lhn 600 20/26
    static let kern: CGFloat = -0.2
    /// One line of text.
    static let lineHeight: CGFloat = 26
    /// The title line for one line of text: 2 above and below it (css:445, a 30pt `.lht`).
    static let line: CGFloat = 30
    /// The field draws its text this far in from its left and right edges (its line fragment padding).
    static let inset: CGFloat = 2

    /// The title's attributes, at rest and in the field editor. The paragraph holds each line at 26 with the baseline
    /// where CSS puts it (TextKit puts the spare height above the glyphs; CSS splits it).
    static func attributes(_ color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font, .kern: kern, .foregroundColor: color, .paragraphStyle: paragraph, .baselineOffset: baselineOffset]
    }

    nonisolated(unsafe) static let paragraph: NSParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = lineHeight
        ps.maximumLineHeight = lineHeight
        ps.lineBreakMode = .byWordWrapping
        return ps
    }()

    /// TextKit's baseline in a 26pt line minus CSS's, less the half point an NSTextField draws high (as TitleField).
    nonisolated(unsafe) static let baselineOffset: CGFloat = {
        let a = font.ascender.rounded(), d = (-font.descender).rounded()
        let css = a + (lineHeight - a - d) / 2
        let storage = NSTextStorage(string: "Xg", attributes: [.font: font, .paragraphStyle: paragraph])
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: 1000, height: 1000))
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        lm.ensureLayout(for: tc)
        let textKit = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY + lm.location(forGlyphAt: 0).y
        return textKit - css - 0.5
    }()

    struct Measure: Equatable {
        var lines: Int
        /// The last line's width, for what follows it (Today's date, "In Trash").
        var lastWidth: CGFloat
        /// The last line's characters.
        var lastChars: Int = 0

        /// Where what follows the title starts, from the title's left: 9 after the last line, measured as the
        /// one-line title always was (its width without the tracking, plus the tracking's size again and 2), so
        /// Today's date stays where it was.
        var follow: CGFloat { lastWidth + 2 * abs(TitleLayout.kern) * CGFloat(lastChars) + 2 + 9 }
    }

    nonisolated(unsafe) private static var cache: [String: Measure] = [:]

    /// The title's lines at `width` (the text's width, inside the field's insets), as the field breaks them.
    static func measure(_ text: String, width: CGFloat) -> Measure {
        let key = "\(width)|\(text)"
        if let m = cache[key] { return m }
        let s = text.isEmpty ? "X" : text
        let storage = NSTextStorage(string: s, attributes: attributes(.black))
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: max(1, width), height: .greatestFiniteMagnitude))
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        lm.ensureLayout(for: tc)
        var lines = 0
        var last: CGFloat = 0
        var chars = 0
        lm.enumerateLineFragments(forGlyphRange: lm.glyphRange(for: tc)) { _, used, _, glyphs, _ in
            lines += 1
            last = used.width
            chars = glyphs.length
        }
        let m = Measure(lines: max(1, lines), lastWidth: ceil(last), lastChars: chars)
        if cache.count > 500 { cache.removeAll() }
        cache[key] = m
        return m
    }

    /// The title line's height for `text` in `width`: its lines, with 2 above and below. One line is the 30pt line it
    /// always was. What follows the title (Today's date, "In Trash") never adds a line: it goes 9 after the last line
    /// and gives way there, as it did after the one line (css:441–442).
    static func lineBox(_ text: String, width: CGFloat) -> CGFloat {
        CGFloat(measure(text, width: width).lines) * lineHeight + (line - lineHeight)
    }
}
