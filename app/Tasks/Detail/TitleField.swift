import AppKit
import SwiftUI
import TasksCore

/// The detail pane's title (§6 Keys in the title, §7 The detail title, css:259): an always-editable wrapping field,
/// 15/20 semibold `ink`, placeholder "New Task", no ring (the caret is the cue). For a new task it types into the
/// draft (its row follows each keystroke); for an existing one the row updates when the title commits.
final class TitleFieldView: NSView {
    let field = InlineField(frame: .zero)
    var store: Store!
    var state: WindowState!
    weak var refs: DetailRefs?
    private(set) var taskID: EntityID?
    var palette = TK.Palette.dark
    /// The text being typed into an existing task's title (nil when not editing), for measuring.
    var onLiveText: ((String?) -> Void)?

    /// One editing session: from the caret arriving to the commit (or Esc).
    private struct Session {
        var id: EntityID
        var original: String
    }
    private var session: Session?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(field)
        field.makeWrapping()
        field.font = TK.Font.detailTitle
        field.setAccessibilityLabel("Title")
        field.onFocus = { [weak self] in self?.began() }
        field.onChange = { [weak self] in self?.changed($0) }
        field.onKey = { [weak self] in self?.key($0) ?? false }
        field.onEnd = { [weak self] _ in
            self?.finish()
            self?.restyle()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private var actions: WindowActions { WindowActions(store: store, window: state) }

    // MARK: Type (15/20, the baseline where the browser puts it)

    static let lineHeight: CGFloat = 20
    /// The cell's text sits 2pt in from the field's left edge (its field editor's line fragment padding).
    static let inset: CGFloat = 2

    /// The title's attributes: 20pt lines with the baseline where the browser has it (15.5 down, measured in Chromium
    /// at 2×). The text field, at rest and in its field editor, draws 0.5pt higher than a text view with the same
    /// attributes, so it gets 0.5pt less offset (measured against the prototype, one line and two, both states). The
    /// editor's attributes are the same; they're set on its text because it hands back plain text.
    func attributes(_ color: NSColor, editor: Bool = false) -> [NSAttributedString.Key: Any] {
        let font = TK.Font.detailTitle
        let offset = LineBox.baselineOffset(font, lineHeight: Self.lineHeight) - 0.5
        return [.font: font, .foregroundColor: color, .paragraphStyle: LineBox.paragraph(lineHeight: Self.lineHeight),
                .baselineOffset: offset]
    }

    /// Puts the cell's attributes back on what's shown: the field editor hands back plain text in the cell's font, once
    /// it has let go.
    private func restyle() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.field.isEditing, !self.isStyled else { return }
            self.field.attributedStringValue = NSAttributedString(string: self.field.stringValue, attributes: self.attributes(self.palette.ink))
        }
    }

    /// What's shown carries the title's line box.
    private var isStyled: Bool {
        let s = field.attributedStringValue
        guard s.length > 0 else { return true }
        let want = attributes(palette.ink)
        return s.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? CGFloat == want[.baselineOffset] as? CGFloat
            && (s.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.maximumLineHeight
            == (want[.paragraphStyle] as? NSParagraphStyle)?.maximumLineHeight
    }

    /// Whole 20pt lines at `width` (the textarea's `field-sizing: content`, min 20).
    static func height(_ text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let s = text.isEmpty ? "X" : text
        let r = (s as NSString).boundingRect(with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin], attributes: attributes)
        return max(lineHeight, (r.height / lineHeight).rounded(.up) * lineHeight)
    }

    override func layout() {
        super.layout()
        field.frame = NSRect(x: -Self.inset, y: 0, width: bounds.width + 2 * Self.inset, height: bounds.height)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { refs?.titleAttached(self) }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Leaving the screen mid-edit commits, as a press elsewhere would.
        if newWindow == nil, session != nil { finish() }
        super.viewWillMove(toWindow: newWindow)
    }

    func contains(_ event: NSEvent) -> Bool {
        guard window != nil else { return false }
        return visibleRect.contains(convert(event.locationInWindow, from: nil))
    }

    // MARK: Binding

    func bind(id: EntityID, text: String, palette: TK.Palette) {
        let themeChanged = palette != self.palette
        self.palette = palette
        if taskID != id {
            taskID = id
            session = nil
        }
        field.textColor = palette.ink
        if themeChanged || field.placeholderAttributedString == nil {
            field.placeholderAttributedString = NSAttributedString(string: "New Task", attributes: attributes(palette.inkTertiary))
        }
        if !field.isEditing, themeChanged || field.stringValue != text || !isStyled {
            field.attributedStringValue = NSAttributedString(string: text, attributes: attributes(palette.ink))
        }
    }

    /// Puts the caret in the title: at the end (a new task) or with the text selected (⇧Tab from the notes).
    func takeCaret(_ selection: WindowState.TitleFocus.Selection) {
        // A request taken a turn late (`DetailRefs.titleAttached`) may no longer apply: Esc dropped the new task, the
        // pane closed, or another task was selected meanwhile (T50).
        guard window != nil, state.detailOpen, let id = taskID, state.selection == [id] else { return }
        field.focus(selection == .all ? .all : .end)
    }

    // MARK: Editing

    private var isDraft: Bool { taskID != nil && state.draft?.id == taskID }

    private func began() {
        guard let id = taskID else { return }
        if session == nil { session = Session(id: id, original: isDraft ? "" : field.stringValue) }
        if state.detailEditing != .title { state.detailEditing = .title }
        if state.focus != .detail { state.focus = .detail }
        styleEditor()
        // The cell sets the editor up again once it has the keys.
        DispatchQueue.main.async { [weak self] in self?.styleEditor() }
    }

    /// The field editor takes plain text in the cell's font: give it the title's line box (again after a paste whose
    /// line breaks the field rewrote).
    private func styleEditor() {
        guard let editor = field.currentEditor() as? NSTextView else { return }
        let a = attributes(palette.ink, editor: true)
        editor.insertionPointColor = palette.ink
        editor.selectedTextAttributes = [.backgroundColor: palette.textSelection]
        editor.defaultParagraphStyle = a[.paragraphStyle] as? NSParagraphStyle
        if let storage = editor.textStorage, storage.length > 0,
           storage.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? CGFloat != a[.baselineOffset] as? CGFloat
            || storage.attribute(.baselineOffset, at: storage.length - 1, effectiveRange: nil) == nil {
            let sel = editor.selectedRanges
            storage.setAttributes(a, range: NSRange(location: 0, length: storage.length))
            editor.selectedRanges = sel
        }
        editor.typingAttributes = a
    }

    private func changed(_ text: String) {
        styleEditor()
        if isDraft {
            actions.setDraftTitle(text)
        } else {
            onLiveText?(text)
        }
    }

    /// Ends the session: a new task is written (or, untitled, dropped); an existing one is renamed if it changed.
    private func finish() {
        guard let s = session else { return }
        session = nil
        if state.detailEditing == .title { state.detailEditing = nil }
        onLiveText?(nil)
        if state.draft?.id == s.id {
            actions.commitDraft()
            // Dropping it hands the keys to the list, but when that happens inside `makeFirstResponder(nil)` (the ×,
            // ⌘D) the outer call wins: give them to the list once it's done.
            let state = state!
            DispatchQueue.main.async {
                guard state.focus == .list, let w = state.nsWindow, w.firstResponder === w || w.firstResponder == nil else { return }
                state.taskList?.takeKeys()
            }
            return
        }
        // Only what the user changed (`EditSession`): a title left as it was never goes back over one that synced in
        // during the session; the field shows that one instead.
        guard let t = store.projection.task(s.id), !t.deleted,
              let text = EditSession.write(field.stringValue, original: s.original, current: t.title) else {
            showModel()
            return
        }
        let a = actions
        let store = store!
        a.undoable("Rename Task") { store.setTitle(s.id, text, name: "Rename Task", undoManager: a.undo) }
    }

    /// Once the field has let go, shows the task's title as the model has it (the field ignores the model while it
    /// has the caret, so a title that synced in meanwhile isn't on screen yet).
    private func showModel() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.field.isEditing, let id = self.taskID, let t = self.store.projection.task(id),
                  self.field.stringValue != t.title else { return }
            self.field.attributedStringValue = NSAttributedString(string: t.title, attributes: self.attributes(self.palette.ink))
        }
    }

    /// The title has the caret.
    var isEditingTitle: Bool {
        guard let editor = field.currentEditor() else { return false }
        return window?.firstResponder === editor
    }

    /// The keys (§6 table, §7 table). An untitled new task is dropped by any of them. ⌘Return comes from the pane's
    /// key monitor: AppKit has no key binding for it, so the field editor never reports it.
    @discardableResult
    func key(_ k: InlineField.Key) -> Bool {
        let a = actions
        if isDraft, a.untitledDraft {
            session = nil
            if state.detailEditing == .title { state.detailEditing = nil }
            a.dropDraft()
            if state.focus != .list { a.focus(.list) } else { state.taskList?.takeKeys() }
            return true
        }
        switch k {
        case .returnKey, .tab:
            // Commit, caret to the notes.
            finish()
            refs?.startNotes()
        case .escape:
            if isDraft {
                // Esc keeps a new task's title.
                finish()
            } else if let s = session {
                // An existing one gets its title back: the model's, which is the old one unless one synced in.
                session = nil
                if state.detailEditing == .title { state.detailEditing = nil }
                onLiveText?(nil)
                field.abortEditing()
                let title = store.projection.task(s.id)?.title ?? s.original
                field.attributedStringValue = NSAttributedString(string: title, attributes: attributes(palette.ink))
            }
            a.focus(.list)
        case .backtab, .commandReturn:
            finish()
            a.focus(.list)
        }
        return true
    }
}

struct TitleField: NSViewRepresentable {
    let store: Store
    let window: WindowState
    let refs: DetailRefs
    let id: EntityID
    /// The model's title (or the draft's).
    let text: String
    /// What to measure: the text being typed, else `text`.
    let measure: String
    let palette: TK.Palette
    let onLiveText: (String?) -> Void

    func makeNSView(context: Context) -> TitleFieldView {
        let v = TitleFieldView(frame: NSRect(x: 0, y: 0, width: 358, height: 20))
        v.store = store
        v.state = window
        v.refs = refs
        v.onLiveText = onLiveText
        v.bind(id: id, text: text, palette: palette)
        refs.title = v
        return v
    }

    func updateNSView(_ v: TitleFieldView, context: Context) {
        v.store = store
        v.state = window
        v.refs = refs
        v.onLiveText = onLiveText
        v.bind(id: id, text: text, palette: palette)
        if refs.title !== v { refs.title = v }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: TitleFieldView, context: Context) -> CGSize? {
        let w = proposal.width ?? 358
        return CGSize(width: w, height: TitleFieldView.height(measure, width: w, attributes: v.attributes(palette.ink)))
    }
}
