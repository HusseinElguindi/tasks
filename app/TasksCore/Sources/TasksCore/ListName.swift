import Foundation

/// A list's short name, for the list mark on rows that mix lists (design/INTERACTIONS-v2.md §22 "The list mark",
/// design/ROW-DENSITY.md direction C; the user, 2026-11-08: "Short names, yes (but not just --, do : and other common
/// separators)"). Derived from the name on every client, so there's no new field to sync.
///
/// The rule: the part of the name before its first separator, trimmed, when that part is 1 to `maxLength` characters;
/// otherwise the whole name, trimmed.
/// - **Separators:** an em dash "—" or an en dash "–" (spaced or not), a hyphen with a space on both sides (" - ", so
///   "ECE-358" and "e-mail" keep theirs), a colon followed by a space or ending the name ("SE 463: …", but not "10:30"),
///   a vertical bar "|", a middle dot "·", and an opening parenthesis after a space ("ECE 358 (Computer Networks)").
/// - **The first one wins,** whichever kind it is: "SE 463 — Part 1: Intro" is "SE 463".
/// - **A separator at the very start doesn't count:** the search starts after any separators and spaces the name
///   begins with, so "— Notes" has no short name, and "| Work | Home" is "Work".
/// - **Too long:** a part over `maxLength` characters ("Groceries and errands — weekly") gives the whole name; a
///   short name is one you can tell apart at a glance, and a long first part rarely is.
/// - **No separator:** the whole name ("Inbox", "CS 489").
public enum ListName {
    /// The longest short name, in characters (grapheme clusters): "EARTH 121" is 9.
    public static let maxLength = 12

    /// The short name of `name`. An empty or blank name gives "".
    public static func short(_ name: String) -> String {
        let whole = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(whole)
        // Skip what the name starts with: separators and spaces.
        var start = 0
        while start < chars.count, chars[start].isWhitespace || separatorLength(chars, at: start) > 0 { start += 1 }
        var i = start
        while i < chars.count {
            if separatorLength(chars, at: i) > 0 {
                let head = String(chars[start..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
                return !head.isEmpty && head.count <= maxLength ? head : whole
            }
            i += 1
        }
        return whole
    }

    /// How many characters a separator starting at `i` takes, 0 when none does.
    private static func separatorLength(_ c: [Character], at i: Int) -> Int {
        switch c[i] {
        case "—", "–", "|", "·":
            return 1
        case ":":
            // "SE 463: …" or a trailing colon, not "10:30".
            return i + 1 == c.count || c[i + 1].isWhitespace ? 1 : 0
        case " ":
            guard i + 1 < c.count else { return 0 }
            // " - " (both spaces), and " (".
            if c[i + 1] == "-", i + 2 < c.count, c[i + 2] == " " { return 3 }
            if c[i + 1] == "(" { return 2 }
            return 0
        default:
            return 0
        }
    }
}

extension ListModel {
    /// The list mark's name (`ListName.short`).
    public var shortName: String { ListName.short(name) }
}
