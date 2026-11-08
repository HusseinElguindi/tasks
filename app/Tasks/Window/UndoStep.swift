import Foundation

/// One named undo step (§9): `WindowActions.undoable`'s group, on its own so the tests can run it.
@MainActor
enum UndoStep {
    /// Runs `body` (calls that register their own undo) as one undo group, named `name` if it did something. The name
    /// is set while the group is open: the same name as after it closes when the manager groups by event (the window's
    /// does), and one that doesn't has no group to name after it closes and throws an Objective-C exception (the
    /// SyncCloud crash, 2026-11-08: thrown under a Swift Task, it left the main thread's executor record stale).
    @discardableResult
    static func run(_ um: UndoManager, name: String, _ body: () -> Bool) -> Bool {
        um.beginUndoGrouping()
        let did = body()
        if did { um.setActionName(name) }
        um.endUndoGrouping()
        return did
    }
}
