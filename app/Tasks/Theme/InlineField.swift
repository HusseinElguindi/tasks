import AppKit

/// The text field that renames in place (§7, §18.6): borderless, no background, no focus ring, in the font and color
/// of the label it replaces. Return, Tab, ⇧Tab, Esc and ⌘Return come out as callbacks; ⌘Z is the field's own undo
/// (a private undo manager, so it never reaches the window's).
final class InlineField: NSTextField, NSTextFieldDelegate {
    enum Key { case returnKey, tab, backtab, escape, commandReturn }

    /// Return true when handled (the field editor then does nothing with the key).
    var onKey: ((Key) -> Bool)?
    var onChange: ((String) -> Void)?
    /// Editing ended for any reason (a press elsewhere, focus moving away), after `onKey` if a key ended it.
    var onEnd: ((String) -> Void)?
    var onBegin: (() -> Void)?
    /// The field took the keys (a press in it, or `focus(_:)`), before anything is typed; `currentEditor()` is set.
    var onFocus: (() -> Void)?
    /// Pasted line breaks become spaces (§7).
    var singleLine = true
    private let fieldUndo = UndoManager()

    override class var cellClass: AnyClass? {
        get { InlineFieldCell.self }
        set {}
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        isEditable = true
        isSelectable = true
        lineBreakMode = .byClipping
        cell?.isScrollable = true
        cell?.wraps = false
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Wrapping (the detail title, the list's large title): grows with its text. The detail title replaces no label,
    /// so it keeps AppKit's own editor; the large title (`matchingLabels`) keeps the unsmoothed one, to draw at the
    /// weight of the other titles in the list, which are `CATextLayer`s.
    func makeWrapping(matchingLabels: Bool = false) {
        (cell as? InlineFieldCell)?.matchesLabel = matchingLabels
        cell?.isScrollable = false
        cell?.wraps = true
        lineBreakMode = .byWordWrapping
        usesSingleLineMode = false
        maximumNumberOfLines = 0
    }

    // MARK: Caret

    enum Caret { case all, end, at(Int) }

    /// Takes the keys and puts the caret (or selection) where asked.
    func focus(_ caret: Caret) {
        guard let w = window else { return }
        if currentEditor() == nil { w.makeFirstResponder(self) }
        guard let editor = currentEditor() else { return }
        let n = (stringValue as NSString).length
        switch caret {
        case .all: editor.selectedRange = NSRange(location: 0, length: n)
        case .end: editor.selectedRange = NSRange(location: n, length: 0)
        case .at(let i): editor.selectedRange = NSRange(location: min(max(i, 0), n), length: 0)
        }
    }

    var isEditing: Bool { currentEditor() != nil }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    // MARK: NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let key: Key?
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            key = NSApp.currentEvent?.modifierFlags.contains(.command) == true ? .commandReturn : .returnKey
        case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            key = .returnKey
        case #selector(NSResponder.insertTab(_:)): key = .tab
        case #selector(NSResponder.insertBacktab(_:)): key = .backtab
        case #selector(NSResponder.cancelOperation(_:)): key = .escape
        default: key = nil
        }
        guard let key else { return false }
        return onKey?(key) ?? false
    }

    func controlTextDidBeginEditing(_ obj: Notification) { onBegin?() }

    func controlTextDidChange(_ obj: Notification) {
        if singleLine, stringValue.contains(where: \.isNewline) {
            let editor = currentEditor()
            let sel = editor?.selectedRange
            stringValue = stringValue.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            if let sel { editor?.selectedRange = sel }
        }
        onChange?(stringValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) { onEnd?(stringValue) }

    // The field's own undo (§9: inside a text field ⌘Z is the field's). The selector is spelled out: inferred, it's
    // `undoManagerFor:`, which the field editor never calls, so its typing went to another undo manager (v2
    // feedback 13).
    @objc(undoManagerForTextView:) func undoManager(for view: NSTextView) -> UndoManager? { fieldUndo }
    override var undoManager: UndoManager? { fieldUndo }
    @objc func undo(_ sender: Any?) { FieldUndo.undo(fieldUndo) }
    @objc func redo(_ sender: Any?) { FieldUndo.redo(fieldUndo) }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        FieldUndo.validate(item, fieldUndo) ?? super.validateUserInterfaceItem(item)
    }

    // A press inside the field moves the caret and never ends the edit (§7).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// ⌘Z and ⇧⌘Z in a text field with its own undo manager (§9: inside a text field ⌘Z is the field's own undo). The field
/// takes `undo:` and `redo:` itself, ahead of the window in the responder chain: SwiftUI's window answers them from the
/// app's undo manager for some first responders, and greyed Undo out in the notes and the date field while they had
/// typing to undo (v2 feedback 13). With nothing left to undo they're off, as in the prototype's browser fields.
@MainActor
enum FieldUndo {
    static func undo(_ um: UndoManager) { if um.canUndo { um.undo() } }
    static func redo(_ um: UndoManager) { if um.canRedo { um.redo() } }

    /// Undo's and Redo's state, titled as the Edit menu titles them ("Undo Typing"); nil for any other item.
    static func validate(_ item: NSValidatedUserInterfaceItem, _ um: UndoManager) -> Bool? {
        switch item.action {
        case Selector(("undo:")):
            (item as? NSMenuItem)?.title = um.undoMenuItemTitle
            return um.canUndo
        case Selector(("redo:")):
            (item as? NSMenuItem)?.title = um.redoMenuItemTitle
            return um.canRedo
        default:
            return nil
        }
    }
}

/// The labels a rename field replaces are `CATextLayer`s, which draw text without font smoothing; AppKit's field
/// editor smooths, so the title thickened for the length of a rename, a visible jump as it began and ended (v2 feedback
/// 5). This cell draws, and edits with, an editor that doesn't smooth: the same weight as the label, pixel for pixel.
private final class InlineFieldCell: NSTextFieldCell {
    var matchesLabel = true
    private lazy var editor: NSTextView = {
        let v = UnsmoothedFieldEditor(usingTextLayoutManager: false)
        v.isFieldEditor = true
        return v
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        matchesLabel ? editor : super.fieldEditor(for: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        if matchesLabel { NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false) }
        super.drawInterior(withFrame: cellFrame, in: controlView)
    }
}

private final class UnsmoothedFieldEditor: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
        super.draw(dirtyRect)
    }
}
