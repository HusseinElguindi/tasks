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

/// A title is one line (INTERACTIONS-v2 §7 "The detail title"): pasted line breaks become spaces, as the Mac's field
/// makes them, and Return ends the edit.
enum TitleText {
    /// Each line break (CR LF is one) as a space.
    static func oneLine(_ s: String) -> String {
        s.contains(where: \.isNewline) ? String(s.map { $0.isNewline ? " " : $0 }) : s
    }

    /// The change from `old` to `new` was a typed Return: one line break added and nothing else, or one at the end (fast
    /// typing can bring a keystroke with it). The text without it; nil for a paste.
    static func typedReturn(old: String, new: String) -> String? {
        guard !old.contains(where: \.isNewline), new.filter(\.isNewline).count == 1 else { return nil }
        let rest = new.filter { !$0.isNewline }
        return rest == old || new.last?.isNewline == true ? rest : nil
    }
}

/// The notes' limit (the core clamps a write at 20,000 UTF-16 units, Store+Actions.swift:6): the editor keeps to it and
/// says so, and the details' footer counts from 18,000 (the Mac's NotesView.swift:703, DetailPane.swift:434).
enum NotesLimit {
    static let max = 20_000
    static let near = 18_000
    static let notice = "Notes hold up to 20,000 characters"

    /// The text cut to `max` UTF-16 units, at a character's edge.
    static func prefix(_ s: String) -> String {
        guard s.utf16.count > max else { return s }
        var n = 0
        var end = s.startIndex
        for i in s.indices {
            let w = s[i].utf16.count
            if n + w > max { break }
            n += w
            end = s.index(after: i)
        }
        return String(s[..<end])
    }

    /// " · 19,412 / 20,000" from 18,000; empty below.
    static func counter(_ s: String) -> String {
        let n = s.utf16.count
        guard n >= near else { return "" }
        return " · " + n.formatted(.number) + " / " + max.formatted(.number)
    }
}
