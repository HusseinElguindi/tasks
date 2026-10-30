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
    /// Pasted line breaks become spaces (§7).
    var singleLine = true
    private let fieldUndo = UndoManager()

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

    /// Wrapping (the detail title): grows with its text.
    func makeWrapping() {
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

    // The field's own undo (§9: inside a text field ⌘Z is the field's).
    @objc func undoManager(for view: NSTextView) -> UndoManager? { fieldUndo }
    override var undoManager: UndoManager? { fieldUndo }

    // A press inside the field moves the caret and never ends the edit (§7).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
