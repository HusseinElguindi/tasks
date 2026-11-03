import GameController
import SwiftUI
import UIKit

// The date sheet's field (batch 2 §2; the Mac's `DateFieldView` and `DateTypingField`, DatePopover.swift:481–660). A
// UIKit field, as the Mac's is an AppKit one, for what SwiftUI's can't do: autocorrection, capitals, spell checking,
// smart punctuation and inline predictions all off, so "11/9" and "+5" stay as typed; Return that keeps the keyboard;
// and a hardware keyboard's arrows, Page Up and Page Down and Esc for the calendar instead of the caret.

/// The keys the sheet takes from a hardware keyboard while the field has the caret (DatePopover.swift:256).
enum DateKey {
    case left, right, up, down, pageUp, pageDown, escape

    /// The arrows, from `pressesBegan`.
    init?(arrow code: UIKeyboardHIDUsage) {
        switch code {
        case .keyboardLeftArrow: self = .left
        case .keyboardRightArrow: self = .right
        case .keyboardUpArrow: self = .up
        case .keyboardDownArrow: self = .down
        // Page Up, Page Down and Esc are key commands (`DateTypingField.keyCommands`).
        default: return nil
        }
    }
}

/// Whether a hardware keyboard is connected: the field then takes the caret when the sheet opens, as on the Mac.
@MainActor func hardwareKeyboard() -> Bool { GCKeyboard.coalesced != nil }

struct DateField: UIViewRepresentable {
    let placeholder: String
    let ink: Color
    let placeholderInk: Color
    let tint: Color
    /// Takes the caret once it's on screen (a hardware keyboard).
    let focusOnAppear: Bool
    let onText: (String) -> Void
    let onFocus: (Bool) -> Void
    let onReturn: () -> Void
    let onKey: (DateKey) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> DateTypingField {
        let f = DateTypingField()
        f.delegate = context.coordinator
        f.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        f.font = .systemFont(ofSize: 17)
        f.keyboardType = .default
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        f.spellCheckingType = .no
        f.smartQuotesType = .no
        f.smartDashesType = .no
        f.smartInsertDeleteType = .no
        f.inlinePredictionType = .no
        f.returnKeyType = .done
        f.enablesReturnKeyAutomatically = false
        f.clearButtonMode = .never
        f.accessibilityLabel = "Date"
        f.accessibilityHint = "Type a day, like Friday, 3 days or November 9"
        f.focusOnAppear = focusOnAppear
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return f
    }

    func updateUIView(_ f: DateTypingField, context: Context) {
        context.coordinator.parent = self
        f.textColor = UIColor(ink)
        f.tintColor = UIColor(tint)
        f.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: UIColor(placeholderInk), .font: UIFont.systemFont(ofSize: 17),
        ])
        f.onKey = { context.coordinator.parent.onKey($0) }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DateField
        init(_ parent: DateField) { self.parent = parent }

        @objc func changed(_ f: UITextField) { parent.onText(f.text ?? "") }
        func textFieldDidBeginEditing(_ f: UITextField) { parent.onFocus(true) }
        func textFieldDidEndEditing(_ f: UITextField) { parent.onFocus(false) }
        /// Return sets the highlighted day; the keyboard stays (a miss keeps typing, a hit closes the sheet).
        func textFieldShouldReturn(_ f: UITextField) -> Bool {
            parent.onReturn()
            return false
        }
    }
}

final class DateTypingField: UITextField {
    var onKey: ((DateKey) -> Void)?
    var focusOnAppear = false
    /// The presses taken for the calendar, whose ends aren't passed on either.
    private var taken: Set<UIKeyboardHIDUsage> = []

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, focusOnAppear else { return }
        focusOnAppear = false
        DispatchQueue.main.async { [weak self] in _ = self?.becomeFirstResponder() }
    }

    /// Esc, Page Up and Page Down don't reach `pressesBegan` while the field edits (UIKit takes them first), so
    /// they're key commands.
    override var keyCommands: [UIKeyCommand]? {
        [(UIKeyCommand.inputEscape, #selector(escape)), (UIKeyCommand.inputPageUp, #selector(pageUp)),
         (UIKeyCommand.inputPageDown, #selector(pageDown))].map { input, action in
            let c = UIKeyCommand(input: input, modifierFlags: [], action: action)
            c.wantsPriorityOverSystemBehavior = true
            return c
        }
    }

    @objc private func escape() { onKey?(.escape) }
    @objc private func pageUp() { onKey?(.pageUp) }
    @objc private func pageDown() { onKey?(.pageDown) }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.count == 1, markedTextRange == nil, let key = presses.first?.key,
           key.modifierFlags.intersection([.command, .control, .alternate, .shift]).isEmpty,
           let k = DateKey(arrow: key.keyCode) {
            taken.insert(key.keyCode)
            onKey?(k)
            return
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { p in p.key.map { taken.remove($0.keyCode) == nil } ?? true }
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { p in p.key.map { taken.remove($0.keyCode) == nil } ?? true }
        if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }
}
