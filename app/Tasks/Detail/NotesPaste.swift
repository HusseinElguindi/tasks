import AppKit

/// Rich text on the clipboard as the notes' Markdown (design/MARKDOWN.md §6 Pasting; the prototype's `htmlToMd`,
/// dc:643–703). The styles the notes have carry over: bold, italic, code, links, headings (`#` for the largest, `##`
/// for the rest), lists (two levels), code blocks and table rows (cells joined by " · "). Fonts, colors, sizes,
/// images and everything else are dropped. Paragraphs get a blank line between them; list items and table rows don't.
@MainActor
enum NotesPaste {
    static func markdown(from text: NSAttributedString) -> String {
        let ns = text.string as NSString
        guard ns.length > 0 else { return "" }
        let body = commonSize(text)
        var blocks: [(text: String, kind: Kind)] = []
        var listCounts: [ObjectIdentifier: Int] = [:]
        var code: [String] = []
        var row: (table: ObjectIdentifier, row: Int, cells: [String])?

        func flushCode() {
            guard !code.isEmpty else { return }
            blocks.append(("```\n" + code.joined(separator: "\n") + "\n```", .code))
            code = []
        }
        func flushRow() {
            guard let r = row else { return }
            let cells = r.cells.filter { !$0.isEmpty }
            if !cells.isEmpty { blocks.append((cells.joined(separator: " · "), .row)) }
            row = nil
        }

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs]) { _, range, _, _ in
            let ps = range.length > 0 ? text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : nil
            // Table cells: one row's cells are consecutive paragraphs in the same table.
            if let cell = ps?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).last {
                flushCode()
                let id = ObjectIdentifier(cell.table)
                if let r = row, r.table != id || r.row != cell.startingRow { flushRow() }
                if row == nil { row = (id, cell.startingRow, []) }
                row?.cells.append(inline(text, range).collapsingSpaces)
                return
            }
            flushRow()
            let line = inline(text, range)
            if range.length > 0, isMonospaced(text, range) {
                code.append(ns.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: ""))
                return
            }
            flushCode()
            var s = line.collapsingSpaces
            if let lists = ps?.textLists, let list = lists.last {
                // The marker AppKit writes into the text ("\t•\t", "\t1.\t") goes; ours replaces it.
                if let r = s.range(of: #"^\s*\S*\t"#, options: .regularExpression) { s.removeSubrange(r) }
                s = s.trimmingCharacters(in: .whitespaces)
                let id = ObjectIdentifier(list)
                let n = (listCounts[id] ?? 0) + 1
                listCounts[id] = n
                let ordered = list.markerFormat.rawValue.contains("decimal") || list.markerFormat.rawValue.contains("alpha")
                    || list.markerFormat.rawValue.contains("roman")
                let indent = String(repeating: "  ", count: min(lists.count - 1, 2))
                blocks.append((indent + (ordered ? "\(n). " : "- ") + s, .item))
                return
            }
            s = s.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return }
            // Headings by size against the clipboard's body text, as H1 and H2–H6 (§6).
            let size = maxSize(text, range)
            if size >= body * 1.45 || (size >= body * 1.12 && isBold(text, range)) {
                let plain = s.replacingOccurrences(of: "**", with: "")
                blocks.append(((size >= body * 1.45 ? "# " : "## ") + plain, .heading))
                return
            }
            blocks.append((s, .paragraph))
        }
        flushCode()
        flushRow()
        var out = ""
        for (i, b) in blocks.enumerated() {
            if i > 0 {
                let prev = blocks[i - 1].kind
                out += prev == b.kind && (b.kind == .item || b.kind == .row) ? "\n" : "\n\n"
            }
            out += b.text
        }
        return out
    }

    private enum Kind { case paragraph, heading, item, code, row }

    /// A paragraph's text with bold, italic, code and links as Markdown.
    private static func inline(_ text: NSAttributedString, _ range: NSRange) -> String {
        var out = ""
        text.enumerateAttributes(in: range) { a, r, _ in
            var s = (text.string as NSString).substring(with: r).replacingOccurrences(of: "\u{FFFC}", with: "")
            guard !s.isEmpty else { return }
            let font = a[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            if traits.contains(.monoSpace) || font?.isFixedPitch == true {
                let t = s.replacingOccurrences(of: "`", with: "")
                out += t.trimmingCharacters(in: .whitespaces).isEmpty ? t : "`" + t + "`"
                return
            }
            if let link = (a[.link] as? URL)?.absoluteString ?? (a[.link] as? String),
               link.range(of: #"^(https?:|mailto:)"#, options: [.regularExpression, .caseInsensitive]) != nil,
               !s.trimmingCharacters(in: .whitespaces).isEmpty {
                let label = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                let addr = link.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
                    .replacingOccurrences(of: " ", with: "%20")
                out += "[" + label + "](" + addr + ")"
                return
            }
            let bold = traits.contains(.bold) || (font.map { weight($0) >= 0.3 } ?? false)
            if traits.contains(.italic) || (a[.obliqueness] as? CGFloat ?? 0) > 0 { s = wrap(s, "_") }
            if bold { s = wrap(s, "**") }
            out += s
        }
        return out
    }

    /// `wrap` (dc:648): spaces at either end stay outside the marks; text over several lines isn't wrapped.
    private static func wrap(_ s: String, _ m: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.contains("\n") else { return s }
        let lead = s.prefix { $0 == " " || $0 == "\t" }
        let trail = String(s.reversed().prefix { $0 == " " || $0 == "\t" })
        return String(lead) + m + t + m + trail
    }

    private static func weight(_ f: NSFont) -> CGFloat {
        let traits = f.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        return traits?[.weight] as? CGFloat ?? 0
    }

    private static func isMonospaced(_ text: NSAttributedString, _ range: NSRange) -> Bool {
        var all = true
        text.enumerateAttribute(.font, in: range) { v, r, stop in
            let s = (text.string as NSString).substring(with: r)
            guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let f = v as? NSFont
            if !(f?.isFixedPitch == true || f?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true) { all = false; stop.pointee = true }
        }
        return all
    }

    private static func isBold(_ text: NSAttributedString, _ range: NSRange) -> Bool {
        var all = true
        text.enumerateAttribute(.font, in: range) { v, _, stop in
            guard let f = v as? NSFont else { return }
            if !(f.fontDescriptor.symbolicTraits.contains(.bold) || weight(f) >= 0.3) { all = false; stop.pointee = true }
        }
        return all
    }

    private static func maxSize(_ text: NSAttributedString, _ range: NSRange) -> CGFloat {
        var m: CGFloat = 0
        text.enumerateAttribute(.font, in: range) { v, _, _ in m = max(m, (v as? NSFont)?.pointSize ?? 0) }
        return m
    }

    /// The size most of the text is in: what headings are measured against.
    private static func commonSize(_ text: NSAttributedString) -> CGFloat {
        var counts: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { v, r, _ in
            if let f = v as? NSFont { counts[f.pointSize, default: 0] += r.length }
        }
        return counts.max { $0.value < $1.value }?.key ?? 13
    }
}

private extension String {
    /// Runs of spaces (and the non-breaking kind) as one, as the browser reads HTML text.
    var collapsingSpaces: String {
        replacingOccurrences(of: #"[ \u{00A0}]{2,}"#, with: " ", options: .regularExpression)
    }
}
