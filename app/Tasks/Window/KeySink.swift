import AppKit
import SwiftUI

/// An invisible first responder for a pane that has no field editing (the detail pane): it takes the keys so Esc,
/// Tab and the arrows work from there (§5, §21 Keys).
final class KeySinkView: NSView {
    var onKey: ((NSEvent) -> Bool)?
    var onFocus: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        onFocus?()
        return true
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
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

    func makeNSView(context: Context) -> KeySinkView {
        let v = KeySinkView()
        v.onKey = onKey
        v.onFocus = onFocus
        register(v)
        return v
    }

    func updateNSView(_ v: KeySinkView, context: Context) {
        v.onKey = onKey
        v.onFocus = onFocus
    }
}
