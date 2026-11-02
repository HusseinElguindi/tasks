/// What a text field's editing session writes when it ends (docs/MAC-EDIT-DURABILITY.md). Every field (the detail
/// title, the notes, the renames in place) writes once, at the end, and only what the user changed: nothing unless the
/// text differs from where the session began. Comparing with the model's value at the end instead wrote an untouched
/// field's stale text back over a change that synced in during the session.
enum EditSession {
    /// The text to write, or nil. `original` is the text when the session began; `current` the model's value now.
    static func write(_ text: String, original: String, current: String?) -> String? {
        guard text != original, text != current else { return nil }
        return text
    }
}
