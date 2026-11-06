import SwiftUI
import UIKit

// Notes typed into in place on the list: a heading's (HeadingNotesRow) and a list's, under its title (ListNotesEditor).
// The details' notes keep SwiftUI's TextEditor (NotesEditor).
//
// Two things went wrong with TextEditor here (T33, filmed with -editTrace, EditProbe.swift):
// - A Return at the end of the notes sometimes left the caret on its line until the next character (the user: "pressing
//   enter/return doesn't do anything until you type another character"). At the text view's change its caret was
//   already on the new line; one run-loop turn later, after SwiftUI's update of the editor and before the row's resize,
//   the text view's layout no longer had the new empty last line (its caret back on the line above, its content height
//   unchanged). The row was then measured from that layout and didn't grow, and with its frame unchanged nothing laid
//   the text view out again; asked 300 ms later, it fitted the new line (161 against 136 pt). Filmed: 2 of 5 Returns at
//   the end of a heading's notes, 4 of 5 in a list's; in FlowTests' 24 Returns from fresh launches
//   (testAReturnInNotesAlwaysMovesTheCaretDown), 10 failed in one run and none in the next (4 of 18 in an earlier one),
//   at the end and on an empty last line, and in a film once in the middle: whenever the Return added a line. Making
//   the text view finish its layout (TextKit 2's ensureLayout) before the row was measured didn't help (8 and 11 of 24
//   failed), which leaves TextEditor's own sizing of itself; ours replaces it.
// - Its lines weren't the rest view's: 25 pt apart against MarkdownText's 22, and a blank line a full line against
//   10 pt. So as editing started every line below the first moved down (3 pt each, 15 more after a blank line), and
//   back up at Done: "jumps of the text".
//
// So the editor is a UITextView of our own, on TextKit 1 (the Mac's NotesView is too): every line is one line box,
// `InPlaceNotes.line` tall with `gap` under it, as MarkdownText draws the same notes at rest (`lineBox`), and its
// height is measured from its whole text laid out fresh (`sizeThatFits`), the empty last line included. Its storage is
// never restyled while it's typed into (typed text takes the typing attributes), so nothing undoes its layout.

/// The one line box of notes in place, at rest and typed into.
@MainActor
enum InPlaceNotes {
    /// Typo.notes (subheadline, 15 pt at the default size).
    static var font: UIFont { UIFont.preferredFont(forTextStyle: .subheadline) }
    /// A line's height: the font's, as SwiftUI's Text draws one line of it.
    static var line: CGFloat { font.lineHeight }
    /// The space under every line, wrapped or not (MarkdownText's line spacing and its lines' spacing, at rest).
    static let gap: CGFloat = 4
    /// The height of notes whose last line's top is `lastTop`: as tall at rest (MarkdownText's lines, `gap` between
    /// them) as typed into, so the rows below stay put as editing starts and ends. (The editor's least height used to be
    /// 60 pt: a one-line note's row grew 42 pt as it was tapped, and shrank back.)
    static func height(lastTop: CGFloat) -> CGFloat { lastTop + line }

    static func attributes(_ ink: UIColor) -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = line
        ps.maximumLineHeight = line
        ps.lineSpacing = gap
        ps.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: ink, .paragraphStyle: ps]
    }
}

/// A heading's or a list's notes being typed, in place: the caret in them as they appear, at the end. `onChange` has
/// each new text (cut at NotesLimit, with its notice); `onEnd` runs as the caret leaves them (a tap elsewhere, the
/// keyboard put away).
struct InPlaceNotesEditor: View {
    let text: String
    let identifier: String
    let onChange: (String) -> Void
    let onEnd: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        InPlaceNotesView(text: text, identifier: identifier, ink: UIColor(p.inkSecondary),
                         tint: UIColor(p.accent)) { new in
            guard new.utf16.count > NotesLimit.max else { onChange(new); return }
            // Past 20,000 characters the text is cut there, with the Mac's notice (NotesView.swift:703).
            onChange(NotesLimit.prefix(new))
            app.show(Notice(text: NotesLimit.notice, undo: nil))
        } onEnd: { onEnd() }
    }
}

private struct InPlaceNotesView: UIViewRepresentable {
    let text: String
    let identifier: String
    let ink: UIColor
    let tint: UIColor
    let onChange: (String) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NotesTextView {
        // TextKit 1, as the Mac's notes: fixed line boxes, laid out at once.
        let tv = NotesTextView(usingTextLayoutManager: false)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        // Its frame leaves out the last line's gap (`InPlaceNotes.height`): the caret on that line draws into it.
        tv.clipsToBounds = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.accessibilityIdentifier = identifier
        tv.delegate = context.coordinator
        context.coordinator.view = self
        style(tv, text: text)
        // The caret in them as they appear, at the end.
        tv.selectedRange = NSRange(location: text.utf16.count, length: 0)
        DispatchQueue.main.async { [weak tv] in tv?.becomeFirstResponder() }
        return tv
    }

    func updateUIView(_ tv: NotesTextView, context: Context) {
        context.coordinator.view = self
        tv.tintColor = tint
        tv.accessibilityIdentifier = identifier
        if tv.ink != Self.key(ink) || tv.size != InPlaceNotes.font.pointSize {
            // The look changed (Dark, Light, the text size): restyled whole, the caret kept.
            let sel = tv.selectedRange
            style(tv, text: tv.text)
            tv.selectedRange = NSRange(location: min(sel.location, tv.text.utf16.count), length: 0)
        }
        if tv.text != text {
            // Changed from outside the typing (cut at the limit, another device): the caret stays where it was.
            let sel = tv.selectedRange
            tv.attributedText = NSAttributedString(string: text, attributes: InPlaceNotes.attributes(ink))
            tv.selectedRange = NSRange(location: min(sel.location, text.utf16.count), length: 0)
        }
    }

    private func style(_ tv: NotesTextView, text: String) {
        let a = InPlaceNotes.attributes(ink)
        tv.ink = Self.key(ink)
        tv.size = InPlaceNotes.font.pointSize
        tv.typingAttributes = a
        tv.attributedText = NSAttributedString(string: text, attributes: a)
        tv.tintColor = tint
    }

    /// A colour by its value (a new UIColor is made from the palette each update): restyling is only for a new look.
    private static func key(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.4f %.4f %.4f %.4f", r, g, b, a)
    }

    /// Its whole text laid out at the proposed width, fresh (the empty line after a last new line included).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: NotesTextView, context: Context) -> CGSize? {
        guard let w = proposal.width, w.isFinite, w > 0 else { return nil }
        return CGSize(width: w, height: tv.textHeight(width: w))
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var view: InPlaceNotesView?

        func textViewDidChange(_ tv: UITextView) { view?.onChange(tv.text) }
        func textViewDidEndEditing(_ tv: UITextView) { view?.onEnd() }
    }
}

/// The in-place notes' text view: what it was styled with, and its text's height at a width.
final class NotesTextView: UITextView {
    /// The ink and text size it was styled with.
    var ink = ""
    var size: CGFloat = 0

    /// The text's height laid out at `width` in a layout of its own (the text view's own may be at another width, or
    /// not yet laid out past an edit): its last line's top plus a line (`InPlaceNotes.height`). After a last new line
    /// that's the empty line under it, which a layout manager of its own doesn't lay out (no text view gives it one).
    func textHeight(width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: attributedText)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var last: CGRect?
        let all = NSRange(location: 0, length: manager.numberOfGlyphs)
        manager.enumerateLineFragments(forGlyphRange: all) { rect, _, _, _, _ in last = rect }
        var top = last?.minY ?? 0
        if let last, text.hasSuffix("\n") { top = last.minY + InPlaceNotes.line + InPlaceNotes.gap }
        let h = InPlaceNotes.height(lastTop: top)
        let scale = max(1, traitCollection.displayScale)
        return ceil(h * scale) / scale + textContainerInset.top + textContainerInset.bottom
    }

    /// Its text laid out whole, never cut at its own height (a line past it had no caret).
    override func layoutSubviews() {
        if textContainer.heightTracksTextView || textContainer.size.height < 100_000 {
            textContainer.heightTracksTextView = false
            textContainer.size = CGSize(width: textContainer.size.width, height: .greatestFiniteMagnitude)
        }
        super.layoutSubviews()
    }
}
