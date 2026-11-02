/// What a text field's edit writes when it ends: the Mac's rule (app/Tasks/Window/EditSession.swift, the user,
/// 2026-11-02; INTERACTIONS-v2 §7 "When an edit is written"). A field writes once, at the end, and only what the user
/// changed: nothing unless the text differs from where the edit began. Comparing with the model's value at the end
/// instead wrote an untouched field's stale text back over a change that synced in during the edit. Text the user did
/// change is written, and wins over one that synced in (the log's last writer wins).
enum EditSession {
    /// The text to write, or nil. `original` is the text when the edit began; `current` the model's value now.
    static func write(_ text: String, original: String, current: String?) -> String? {
        guard text != original, text != current else { return nil }
        return text
    }
}
