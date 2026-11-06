import SwiftUI
import TasksCore

/// Notes as they read at rest, from TasksCore's Markdown (design/MARKDOWN.md §3): the lines `Markdown.parse` finds,
/// each drawn by its kind, with `Markdown.inline`'s styles, and no marks. The text stays the source: a checklist box
/// flips the one character between its brackets, as the Mac does (§5).
struct MarkdownText: View {
    let text: String
    var font: Font = Typo.detailNotes
    var ink: Color? = nil
    var lineSpacing: CGFloat = 6
    /// Notes typed into in place (a heading's, a list's): every line in the editor's line box (InPlaceNotes.swift), so
    /// plain lines and blank ones stand where the editor puts them, and nothing moves as editing starts or ends: the
    /// lines and wrapped lines `InPlaceNotes.gap` apart, a blank line a whole line. (A Markdown line's marks show while
    /// it's typed into, so a heading, a bullet or a box still changes there.)
    var lineBox = false
    /// A box was clicked: the notes with it flipped, and whether that checked it. Nil: boxes are read-only.
    var onToggle: ((String, Bool) -> Void)? = nil
    @Environment(\.palette) private var p

    /// A line to draw, or a fenced block's lines as one.
    private enum Item: Identifiable {
        case line(Markdown.Line)
        case code(block: Int, text: String)
        var id: String {
            switch self {
            case let .line(l): "l\(l.index)"
            case let .code(b, _): "c\(b)"
            }
        }
    }

    var body: some View {
        let u = Array(text.utf16)
        let doc = u.withUnsafeBufferPointer { Markdown.parse($0) }
        let numbers = doc.shownNumbers
        VStack(alignment: .leading, spacing: lineBox ? InPlaceNotes.gap : 4) {
            ForEach(items(doc, u)) { item in
                switch item {
                case let .line(l): line(l, u, number: numbers[l.index] ?? l.number)
                case let .code(_, code):
                    Text(code)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(ink ?? p.ink)
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.fillControl, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .font(font)
        .lineSpacing(lineBox ? InPlaceNotes.gap : lineSpacing)
        .foregroundStyle(ink ?? p.ink)
        .tint(p.accentText)
    }

    /// Fence lines take no room at rest; a block's code lines are one box.
    private func items(_ doc: Markdown.Document, _ u: [UInt16]) -> [Item] {
        var out: [Item] = []
        for l in doc.lines {
            switch l.kind {
            case .fence:
                continue
            case .code:
                let s = String(decoding: u[l.start..<l.end], as: UTF16.self)
                if case let .code(b, text)? = out.last, b == l.block {
                    out[out.count - 1] = .code(block: b, text: text + "\n" + s)
                } else {
                    out.append(.code(block: l.block, text: s))
                }
            default:
                out.append(.line(l))
            }
        }
        return out
    }

    /// `number`: an ordered item's shown number (`shownNumbers`: lists number themselves from their first item).
    @ViewBuilder private func line(_ l: Markdown.Line, _ u: [UInt16], number: Int) -> some View {
        let indent = CGFloat(l.level) * 26
        switch l.kind {
        case .blank:
            Color.clear.frame(height: lineBox ? InPlaceNotes.line : 6)
        case .heading1:
            rich(u, l.textStart, l.end).font(Typo.detailNotes.weight(.semibold)).padding(.top, 6)
        case .heading2:
            rich(u, l.textStart, l.end).font(Typo.notes.weight(.semibold)).padding(.top, 4)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(l.level == 0 ? "•" : "◦").foregroundStyle(p.inkTertiary).frame(width: 16)
                rich(u, l.textStart, l.end)
            }
            .padding(.leading, indent)
        case .ordered:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(number)" + String(Character(UnicodeScalar(UInt8(truncatingIfNeeded: l.delimiter)))))
                    .monospacedDigit().foregroundStyle(p.inkSecondary).frame(width: 18, alignment: .trailing)
                rich(u, l.textStart, l.end)
            }
            .padding(.leading, indent)
        case .task:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button { toggle(l, u) } label: {
                    Image(systemName: l.checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(l.checked ? p.inkTertiary : p.lineField)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .disabled(onToggle == nil)
                .accessibilityLabel(plain(u, l.textStart, l.end))
                .accessibilityValue(l.checked ? "Checked" : "Unchecked")
                rich(u, l.textStart, l.end)
                    .foregroundStyle(l.checked ? p.inkTertiary : (ink ?? p.ink))
                    .strikethrough(l.checked, color: p.inkQuiet)
            }
            .padding(.leading, indent)
        case .quote:
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(p.fillStrong).frame(width: 2)
                rich(u, l.textStart, l.end).foregroundStyle(p.inkSecondary)
            }
            .padding(.leading, 7)
            .fixedSize(horizontal: false, vertical: true)
        default:
            rich(u, l.start, l.end)
        }
    }

    /// The text from `from` to `to` with its inline styles: bold, italic, code, links and bare URLs (`Markdown.inline`),
    /// the marks left out.
    private func rich(_ u: [UInt16], _ from: Int, _ to: Int) -> Text {
        let tokens = u.withUnsafeBufferPointer { Markdown.inline($0, from, to) }
        func s(_ a: Int, _ b: Int) -> String { String(decoding: u[a..<b], as: UTF16.self) }
        var out = AttributedString()
        func emit(_ a: Int, _ b: Int, depth: Int, intent: InlinePresentationIntent) {
            var i = a
            for t in tokens where t.depth == depth && t.range.lowerBound >= a && t.range.upperBound <= b {
                out += styled(s(i, t.range.lowerBound), intent)
                switch t.kind {
                case .bold:
                    emit(t.inner.lowerBound, t.inner.upperBound, depth: depth + 1, intent: intent.union(.stronglyEmphasized))
                case .italic:
                    emit(t.inner.lowerBound, t.inner.upperBound, depth: depth + 1, intent: intent.union(.emphasized))
                case .code:
                    var x = AttributedString(s(t.inner.lowerBound, t.inner.upperBound))
                    x.inlinePresentationIntent = intent.union(.code)
                    x.backgroundColor = p.fillControl
                    out += x
                case .link, .url:
                    var x = styled(s(t.inner.lowerBound, t.inner.upperBound), intent)
                    x.link = URL(string: s(t.target.lowerBound, t.target.upperBound))
                    x.foregroundColor = p.accentText
                    out += x
                }
                i = t.range.upperBound
            }
            out += styled(s(i, b), intent)
        }
        emit(from, to, depth: 0, intent: [])
        return Text(out)
    }

    private func styled(_ s: String, _ intent: InlinePresentationIntent) -> AttributedString {
        var x = AttributedString(s)
        if !intent.isEmpty { x.inlinePresentationIntent = intent }
        return x
    }

    private func plain(_ u: [UInt16], _ from: Int, _ to: Int) -> String {
        u.withUnsafeBufferPointer { Markdown.plain($0, from, to) }
    }

    /// Flips the character between the box's brackets: a space checks it, anything else unchecks it (§5).
    private func toggle(_ l: Markdown.Line, _ u: [UInt16]) {
        guard let onToggle, l.kind == .task, l.box >= 0, l.box < u.count else { return }
        var v = u
        let checking = v[l.box] == 32
        v[l.box] = checking ? 120 : 32   // "x" or " "
        onToggle(String(decoding: v, as: UTF16.self), checking)
    }
}
