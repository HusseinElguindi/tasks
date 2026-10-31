import AppKit
import SwiftUI
import TasksCore

/// The detail pane's checkbox (§8, css:190–202): the rows' `CheckLayer`, 16pt in a 30×30 hit area. Hovering the area
/// brightens the ring; pressing shrinks it to 0.86 over 80 ms and releasing springs it back; checking fills it, draws
/// the check and pops it. A new task's box is a placeholder ring that ignores the pointer until the task is written.
final class DetailCheckView: FlippedLayerView {
    let check = CheckLayer()
    var boundID: EntityID?
    var onToggle: (() -> Void)?
    var interactive = true {
        didSet {
            guard interactive != oldValue else { return }
            if !interactive { check.hovered = false; check.setPressed(false) }
            window?.invalidateCursorRects(for: self)
        }
    }
    private var tracking: NSTrackingArea?

    static let side: CGFloat = TK.M.checkHit

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        layer?.addSublayer(check)
        check.position = CGPoint(x: Self.side / 2, y: Self.side / 2)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.setInstant { check.position = CGPoint(x: bounds.midX, y: bounds.midY) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { interactive ? super.hitTest(point) : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { if interactive { check.hovered = true } }
    override func mouseExited(with event: NSEvent) { check.hovered = false }

    private var pressing = false

    override func mouseDown(with event: NSEvent) {
        guard interactive else { return }
        pressing = true
        check.setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        // CSS `:active` holds while the button is down, wherever the pointer goes.
        guard pressing else { return }
        check.hovered = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard pressing else { return }
        pressing = false
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        check.setPressed(false)
        check.hovered = inside && interactive
        if inside { onToggle?() }
    }

    // MARK: Accessibility (§18.15: the detail pane's box is "Complete")

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilityLabel() -> String? { "Complete" }
    override func accessibilityValue() -> Any? { check.isOn ? 1 : 0 }
    override func isAccessibilityEnabled() -> Bool { interactive }
    override func accessibilityPerformPress() -> Bool {
        guard interactive else { return false }
        onToggle?()
        return true
    }
}

struct DetailCheckbox: NSViewRepresentable {
    let id: EntityID
    let on: Bool
    /// A new task's box until it's written: `ink-quiet` at 70%, ignoring the pointer (css:201).
    let placeholder: Bool
    /// Under an untitled new task's title: 45% (css:286).
    let inert: Bool
    let palette: TK.Palette
    let action: () -> Void

    func makeNSView(context: Context) -> DetailCheckView {
        let v = DetailCheckView(frame: .zero)
        update(v, animated: false)
        return v
    }

    func updateNSView(_ v: DetailCheckView, context: Context) {
        update(v, animated: v.boundID == id && v.window != nil)
    }

    private func update(_ v: DetailCheckView, animated: Bool) {
        v.boundID = id
        v.onToggle = action
        v.interactive = !placeholder && !inert
        // The placeholder's 70% is the layer's own; under an untitled title the whole box is 45% (the switch is
        // instant: the checkbox has no opacity transition).
        v.alphaValue = inert ? 0.45 / (placeholder ? 0.7 : 1) : 1
        v.check.set(on: on, placeholder: placeholder, palette: palette, animated: animated && v.check.isOn != on)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DetailCheckView, context: Context) -> CGSize? {
        CGSize(width: DetailCheckView.side, height: DetailCheckView.side)
    }
}

/// Weak references between the pane's pieces: the press monitor asks whether a press is in the title or the notes,
/// Return in the title starts the notes, ⇧Tab in the notes selects the title, and a title focus request waits here
/// until the title is on screen.
@MainActor
final class DetailRefs {
    weak var title: TitleFieldView?
    weak var notes: NotesField.Coordinator?
    /// The header's × in window coordinates (top-left origin): the one press that doesn't keep an untitled new task's
    /// caret (§6 The pointer while adding).
    var closeFrame: CGRect = .zero
    private var pending: (selection: WindowState.TitleFocus.Selection, id: EntityID?, at: TimeInterval)?

    /// With `id`, only that task's title takes the caret: until it's on screen the request waits.
    func focusTitle(_ selection: WindowState.TitleFocus.Selection, of id: EntityID? = nil) {
        if let t = title, t.window != nil, id == nil || t.taskID == id {
            pending = nil
            t.takeCaret(selection)
        } else {
            pending = (selection, id, Date.timeIntervalSinceReferenceDate)
        }
    }

    /// The title arrived on screen (a new task opening the pane, another task selected): it takes a request made just
    /// before, if it's for this task.
    func titleAttached(_ t: TitleFieldView) {
        title = t
        guard let p = pending, p.id == nil || p.id == t.taskID else { return }
        pending = nil
        guard Date.timeIntervalSinceReferenceDate - p.at < 1 else { return }
        DispatchQueue.main.async { [weak t] in t?.takeCaret(p.selection) }
    }

    func startNotes() { notes?.startEditing() }
}
