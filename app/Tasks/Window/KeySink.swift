import AppKit
import SwiftUI

/// An invisible first responder for a pane that has no field editing (the detail pane): it takes the keys so Esc,
/// Tab and the arrows work from there (§5, §21 Keys).
final class KeySinkView: NSView {
    var onKey: ((NSEvent) -> Bool)?
    var onFocus: (() -> Void)?
    /// It's in a window now: a pane that opens with the keys takes them here.
    var onAttach: ((KeySinkView) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        onFocus?()
        return true
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onAttach?(self) }
    }

    func takeKeys() {
        guard let w = window, w.firstResponder !== self else { return }
        w.makeFirstResponder(self)
    }
}

struct KeySink: NSViewRepresentable {
    let register: (KeySinkView) -> Void
    let onKey: (NSEvent) -> Bool
    var onFocus: () -> Void = {}
    var onAttach: (KeySinkView) -> Void = { _ in }

    func makeNSView(context: Context) -> KeySinkView {
        let v = KeySinkView()
        v.onKey = onKey
        v.onFocus = onFocus
        v.onAttach = onAttach
        register(v)
        return v
    }

    func updateNSView(_ v: KeySinkView, context: Context) {
        v.onKey = onKey
        v.onFocus = onFocus
    }
}
