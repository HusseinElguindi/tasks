import Foundation

/// The notes' Markdown, read the way the app shows it (design/MARKDOWN.md §3): lines are the unit, a small set of
/// inline styles, and nothing the spec leaves out. A hand-written scanner over UTF-16 code units, so offsets are
/// `NSString` / `NSTextStorage` offsets and a 20,000-character note scans in one linear pass. It follows the
/// prototype's rules exactly (design/prototype-markdown/Main.dc.html, `mdParseLines` dc:509–531, `MD_INLINE` dc:536).
public enum Markdown {
    // MARK: Lines

    public enum Kind: Equatable, Sendable {
        case paragraph, blank
        /// `# ` (`heading1`) or `##`–`######` (`heading2`).
        case heading1, heading2
        /// `- `, `* `, `+ ` / `1. `, `1) ` / `- [ ] `, `- [x] `.
        case bullet, ordered, task
        /// `> `.
        case quote
        /// A ```` ``` ```` or `~~~` line (up to three spaces in), and the lines between two of them.
        case fence, code
    }

    public struct Line: Equatable, Sendable {
        public var index: Int
        /// The line's first and past-the-last offsets, the newline excluded.
        public var start: Int
        public var end: Int
        public var kind: Kind
        /// The marks at the start: `# `, `> `, `- `, `1. `, `- [ ] ` (zero for the other kinds).
        public var prefix = 0
        /// A list item's level: two leading spaces each, at most 2.
        public var level = 0
        /// A list item's leading spaces.
        public var lead = 0
        /// The bullet (`-`, `*`, `+`) of a bullet or task item.
        public var bullet: UInt16 = 0
        /// An ordered item's number and delimiter (`.` or `)`).
        public var number = 0
        public var delimiter: UInt16 = 0
        /// A task item: whether it's checked, and the offset of the character between its brackets.
        public var checked = false
        public var box = -1
        /// A bullet item whose whole text is the start of a box (`[`, `[ `, `[x`, `[X`): a box being typed. It shows
        /// as faint marks while the selection is on the line, not as the item's text (the user, 2026-11-01).
        public var partialBox = false
        /// A fence or code line: its block's index in `Document.blocks`.
        public var block = -1

        public var textStart: Int { start + prefix }
        public var isListItem: Bool { kind == .bullet || kind == .ordered || kind == .task }
        public var range: NSRange { NSRange(location: start, length: end - start) }
    }

    /// A fenced code block: its first and last lines (the closing fence, or the note's last line when it's never
    /// closed) and the offsets they span.
    public struct Block: Equatable, Sendable {
        public var first: Int
        public var last: Int
        public var start: Int
        public var end: Int
        public var closed: Bool
    }

    public struct Document: Equatable, Sendable {
        public var lines: [Line] = []
        public var blocks: [Block] = []

        public init() {}

        /// The line holding `offset` (a line's end counts as on it).
        public func line(at offset: Int) -> Line? {
            guard !lines.isEmpty else { return nil }
            var lo = 0, hi = lines.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if offset <= lines[mid].end { hi = mid } else { lo = mid + 1 }
            }
            return lines[lo]
        }
    }

    public static func parse(_ text: String) -> Document { parse(Array(text.utf16)) }

    public static func parse(_ u: [UInt16]) -> Document {
        u.withUnsafeBufferPointer { parse($0) }
    }

    public static func parse(_ u: UnsafeBufferPointer<UInt16>) -> Document {
        var doc = Document()
        var start = 0, index = 0
        var open: Int?   // the open block's index
        while true {
            var end = start
            while end < u.count && u[end] != 10 { end += 1 }
            var line = classify(u, start, end, index: index)
            if line.kind == .fence {
                if let b = open {
                    line.block = b
                    doc.blocks[b].last = index
                    doc.blocks[b].end = end
                    doc.blocks[b].closed = true
                    open = nil
                } else {
                    open = doc.blocks.count
                    line.block = open!
                    doc.blocks.append(Block(first: index, last: index, start: start, end: end, closed: false))
                }
            } else if let b = open {
                line = Line(index: index, start: start, end: end, kind: .code, block: b)
                doc.blocks[b].last = index
                doc.blocks[b].end = end
            }
            doc.lines.append(line)
            if end >= u.count { break }
            start = end + 1
            index += 1
        }
        return doc
    }

    /// One line on its own: a fence line says `.fence`; whether other lines are code depends on the fences around
    /// them, which `parse` works out.
    public static func classify(_ u: UnsafeBufferPointer<UInt16>, _ start: Int, _ end: Int, index: Int) -> Line {
        var line = Line(index: index, start: start, end: end, kind: .paragraph)
        func at(_ i: Int) -> UInt16 { i < end ? u[i] : 0 }
        // ``` or ~~~, up to three spaces in.
        var s = start
        while s < end && s - start < 3 && u[s] == 32 { s += 1 }
        if (at(s) == 96 && at(s + 1) == 96 && at(s + 2) == 96) || (at(s) == 126 && at(s + 1) == 126 && at(s + 2) == 126) {
            line.kind = .fence
            return line
        }
        var blank = true
        for i in start..<end where !isSpace(u[i]) { blank = false; break }
        if blank { line.kind = .blank; return line }
        // # through ######, then spaces or tabs.
        var h = start
        while h < end && u[h] == 35 && h - start < 7 { h += 1 }
        let hashes = h - start
        if hashes >= 1 && hashes <= 6 && (at(h) == 32 || at(h) == 9) {
            while h < end && (u[h] == 32 || u[h] == 9) { h += 1 }
            line.kind = hashes == 1 ? .heading1 : .heading2
            line.prefix = h - start
            return line
        }
        // Lists: leading spaces, then a bullet or a number.
        var p = start
        while p < end && u[p] == 32 { p += 1 }
        let lead = p - start
        let c = at(p)
        if c == 45 || c == 42 || c == 43, at(p + 1) == 32 || at(p + 1) == 9 {
            var q = p + 1
            while q < end && (u[q] == 32 || u[q] == 9) { q += 1 }
            line.lead = lead
            line.level = min(2, lead >> 1)
            line.bullet = c
            // [ ], [x] or [X], then spaces, tabs or the end of the line.
            if at(q) == 91, at(q + 1) == 32 || at(q + 1) == 120 || at(q + 1) == 88, at(q + 2) == 93,
               q + 3 == end || at(q + 3) == 32 || at(q + 3) == 9 {
                var r = q + 3
                while r < end && (u[r] == 32 || u[r] == 9) { r += 1 }
                line.kind = .task
                line.checked = at(q + 1) != 32
                line.box = q + 1
                line.prefix = r - start
                return line
            }
            line.kind = .bullet
            line.prefix = q - start
            line.partialBox = at(q) == 91 && (end == q + 1 || end == q + 2 && (at(q + 1) == 32 || at(q + 1) == 120 || at(q + 1) == 88))
            return line
        }
        var d = p
        var number = 0
        while d < end && d - p < 9 && u[d] >= 48 && u[d] <= 57 { number = number * 10 + Int(u[d] - 48); d += 1 }
        // One to nine digits, then . or ) (a tenth digit isn't a delimiter, so it fails, as `\d{1,9}` does).
        if d > p, at(d) == 46 || at(d) == 41, at(d + 1) == 32 || at(d + 1) == 9 {
            var q = d + 1
            while q < end && (u[q] == 32 || u[q] == 9) { q += 1 }
            line.kind = .ordered
            line.lead = lead
            line.level = min(2, lead >> 1)
            line.number = number
            line.delimiter = at(d)
            line.prefix = q - start
            return line
        }
        if at(start) == 62 {
            line.kind = .quote
            line.prefix = at(start + 1) == 32 || at(start + 1) == 9 ? 2 : 1
            return line
        }
        return line
    }

    // MARK: Typing a box

    /// What typing `typed` with the caret at `at` on `l` puts in, for a checklist box being typed (the user,
    /// 2026-11-01). A `]` that closes one (`- [ ` or `- [x` before it) comes with the space after it, so typing straight
    /// on gives `- [ ] text`, a checklist item, and not `- [ ]text`, a bullet. A space typed at the start of a checklist
    /// item's text, right after its box's space, adds nothing: that space is there already. nil: type it as it is.
    public static func typing(_ typed: String, at: Int, on l: Line, _ u: UnsafeBufferPointer<UInt16>) -> String? {
        switch typed {
        case "]":
            guard l.kind == .bullet, at == l.textStart + 2, at <= l.end, at <= u.count else { return nil }
            let inside = u[l.textStart + 1]
            guard u[l.textStart] == 91, inside == 32 || inside == 120 || inside == 88 else { return nil }
            // A space or a tab after it already: `]` alone closes the box.
            if at < l.end, u[at] == 32 || u[at] == 9 { return nil }
            return "] "
        case " ":
            guard l.kind == .task, at == l.textStart, at > l.start, at <= u.count, u[at - 1] == 32 || u[at - 1] == 9 else { return nil }
            return ""
        default:
            return nil
        }
    }

    // MARK: Inline

    public struct Token: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case code, link, url, bold, italic }
        public var kind: Kind
        /// The whole token, marks included.
        public var range: Range<Int>
        /// What shows: the code, the link's text, the URL, the bold or italic text.
        public var inner: Range<Int>
        /// A link's address (`[text](address)`), or a bare URL's whole text.
        public var target: Range<Int>
        /// 0 for a token in the line's text, 1 inside a bold or italic one, and so on.
        public var depth: Int
    }

    /// The inline tokens in `from..<to`, in order, nested ones after the token that holds them.
    public static func inline(_ u: UnsafeBufferPointer<UInt16>, _ from: Int, _ to: Int) -> [Token] {
        var out: [Token] = []
        scan(u, from, to, depth: 0, into: &out)
        return out
    }

    public static func inline(_ text: String) -> [Token] {
        let u = Array(text.utf16)
        return u.withUnsafeBufferPointer { inline($0, 0, $0.count) }
    }

    private static func scan(_ u: UnsafeBufferPointer<UInt16>, _ from: Int, _ to: Int, depth: Int, into out: inout [Token]) {
        var i = from
        while i < to {
            guard let t = token(u, at: i, from, to, depth: depth) else { i += 1; continue }
            out.append(t)
            if t.kind == .bold || t.kind == .italic { scan(u, t.inner.lowerBound, t.inner.upperBound, depth: depth + 1, into: &out) }
            i = t.range.upperBound
        }
    }

    /// The token starting at `i`, trying `MD_INLINE`'s alternatives in its order. Lookarounds see only `from..<to`, as
    /// the prototype's regex sees only the substring it's given.
    private static func token(_ u: UnsafeBufferPointer<UInt16>, at i: Int, _ from: Int, _ to: Int, depth: Int) -> Token? {
        func at(_ k: Int) -> UInt16 { k >= from && k < to ? u[k] : 0 }
        let c = u[i]
        switch c {
        case 96:   // `code`: one or more characters that aren't a backtick
            var k = i + 1
            while k < to && u[k] != 96 { k += 1 }
            if k < to && k > i + 1 { return Token(kind: .code, range: i..<k + 1, inner: i + 1..<k, target: i + 1..<k, depth: depth) }
        case 91:   // [text](address): text without ], address without ( ) or whitespace
            var k = i + 1
            while k < to && u[k] != 93 { k += 1 }
            if k < to && k > i + 1 && at(k + 1) == 40 {
                var e = k + 2
                while e < to && u[e] != 40 && u[e] != 41 && !isSpace(u[e]) { e += 1 }
                if e < to && u[e] == 41 && e > k + 2 {
                    return Token(kind: .link, range: i..<e + 1, inner: i + 1..<k, target: k + 2..<e, depth: depth)
                }
            }
        case 104:   // http:// or https://, to the last character that isn't trailing punctuation
            var p = i
            for ch in [104, 116, 116, 112] as [UInt16] { guard at(p) == ch else { return nil }; p += 1 }
            if at(p) == 115 { p += 1 }
            guard at(p) == 58, at(p + 1) == 47, at(p + 2) == 47 else { return nil }
            p += 3
            var r = p
            while r < to && !isSpace(u[r]) && u[r] != 60 && u[r] != 62 { r += 1 }
            while r > p && isTrailingPunctuation(u[r - 1]) { r -= 1 }
            if r > p { return Token(kind: .url, range: i..<r, inner: i..<r, target: i..<r, depth: depth) }
        case 42:   // **bold**, then *italic*
            if at(i + 1) == 42, i + 2 < to, !isSpace(u[i + 2]) {
                var k = i + 3
                while k + 1 < to {
                    if u[k] == 42 && u[k + 1] == 42 && !isSpace(u[k - 1]) {
                        return Token(kind: .bold, range: i..<k + 2, inner: i + 2..<k, target: i + 2..<k, depth: depth)
                    }
                    k += 1
                }
            }
            if i + 1 < to, !isSpace(u[i + 1]), u[i + 1] != 42 {
                var k = i + 2
                while k < to {
                    if u[k] == 42 && !isSpace(u[k - 1]) && u[k - 1] != 42 {
                        return Token(kind: .italic, range: i..<k + 1, inner: i + 1..<k, target: i + 1..<k, depth: depth)
                    }
                    k += 1
                }
            }
        case 95:   // __bold__ (not followed by a word character), then _italic_ (not inside a word)
            if at(i + 1) == 95, i + 2 < to, !isSpace(u[i + 2]) {
                var k = i + 3
                while k + 1 < to {
                    if u[k] == 95 && u[k + 1] == 95 && !isSpace(u[k - 1]) && !isWord(at(k + 2)) {
                        return Token(kind: .bold, range: i..<k + 2, inner: i + 2..<k, target: i + 2..<k, depth: depth)
                    }
                    k += 1
                }
            }
            if !isWord(at(i - 1)), i + 1 < to, !isSpace(u[i + 1]), u[i + 1] != 95 {
                var k = i + 2
                while k < to {
                    if u[k] == 95 && !isSpace(u[k - 1]) && u[k - 1] != 95 && !isWord(at(k + 1)) {
                        return Token(kind: .italic, range: i..<k + 1, inner: i + 1..<k, target: i + 1..<k, depth: depth)
                    }
                    k += 1
                }
            }
        default:
            break
        }
        return nil
    }

    /// The text as it reads, without marks (`mdPlain`, dc:566): for VoiceOver and a box's label.
    public static func plain(_ u: UnsafeBufferPointer<UInt16>, _ from: Int, _ to: Int) -> String {
        var out: [UInt16] = []
        out.reserveCapacity(to - from)
        func emit(_ a: Int, _ b: Int, depth: Int) {
            var i = a
            for t in inline(u, a, b) where t.depth == 0 {
                out.append(contentsOf: u[i..<t.range.lowerBound])
                switch t.kind {
                case .bold, .italic: emit(t.inner.lowerBound, t.inner.upperBound, depth: depth + 1)
                default: out.append(contentsOf: u[t.inner])
                }
                i = t.range.upperBound
            }
            out.append(contentsOf: u[i..<b])
        }
        emit(from, to, depth: 0)
        return String(utf16CodeUnits: out, count: out.count)
    }

    // MARK: Characters

    /// JavaScript's `\s`.
    @inline(__always)
    public static func isSpace(_ c: UInt16) -> Bool {
        switch c {
        case 9...13, 32, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    /// JavaScript's `\w`.
    @inline(__always)
    public static func isWord(_ c: UInt16) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }

    /// `.,;:!?'")]*_`: what a bare URL doesn't end on.
    @inline(__always)
    static func isTrailingPunctuation(_ c: UInt16) -> Bool {
        switch c {
        case 46, 44, 59, 58, 33, 63, 39, 34, 41, 93, 42, 95: true
        default: false
        }
    }
}

/// What a row shows of a task's notes (design/MARKDOWN.md §7): whether there are any, and the checklist's count.
/// Computed once when the notes change, never while drawing.
public struct NotesSummary: Equatable, Sendable {
    public var hasNotes = false
    public var checked = 0
    public var total = 0

    public init() {}

    public init(_ notes: String) {
        guard !notes.isEmpty else { return }
        let u = Array(notes.utf16)
        hasNotes = u.contains { !Markdown.isSpace($0) }
        guard hasNotes, u.contains(91) else { return }
        for line in Markdown.parse(u).lines where line.kind == .task {
            total += 1
            if line.checked { checked += 1 }
        }
    }
}
