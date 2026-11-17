import SwiftUI
import TasksCore
import UIKit

/// Whether a task's row is one line (T55; the user, 2026-11-08: "the quiz 2 task could fit on one line without any
/// truncation. what if we made those cases fit on one line?", "yes on the design question, we love consistency"): the
/// title and everything line 2 would hold (the list mark, a month row's day, the When, the count or notes glyph, the
/// deadline capsule) fit on one line, nothing cut, in the row's width at the current text size. Then the row is one 48pt
/// line: the title, those in line 2's order, the capsule at the trailing edge. Otherwise it's the two-line row (56pt).
/// A row with nothing for line 2, or the notes glyph alone, is one line whatever its title (ROW-DENSITY.md §6.4).
///
/// The words that decide it travel as the row's height signature (`TaskCollection.signatures`): a rename, a synced
/// edit, a date or a count changing the words changes the signature. The collection resolves it to "1" or "2" with its
/// row width and text size (`TaskCollectionController.resolve`), and again when either changes (rotation, Dynamic Type,
/// iPad's columns), so the height it lays out is the shape the row draws (`TaskRow.twoLineOverride`).
///
/// Widths are measured with UIKit's fonts for the rows' text styles: the same CoreText layout as SwiftUI's `Text`
/// (`RowFitTests` holds them to SwiftUI's own sizes).
struct RowFit: Equatable {
    var title: String
    var indent = false
    /// The list mark's short name (its tile is 16pt).
    var mark: String?
    var day: String?
    var when: String?
    /// The checklist's count ("3/8"), or "" for the notes glyph.
    var hint: String?
    var chip: String?

    // The row's fixed parts (TaskRow): the checkbox's 44pt column, 12 at the trailing end, 30 for a heading's task.
    static let lead: CGFloat = 44
    static let trail: CGFloat = 12
    static let indentW: CGFloat = 30
    /// Title to the first part, between the parts, the mark's tile to its name, and the least before the capsule.
    static let titleGap: CGFloat = 8
    static let gap: CGFloat = 9
    static let markGap: CGFloat = 6
    static let chipGap: CGFloat = 8
    /// Room to spare, so a row right at the edge takes two lines rather than fade by a fraction of a point.
    static let slack: CGFloat = 2

    /// Something for line 2: the notes glyph alone doesn't count (it stays after the title).
    var hasLine2: Bool { mark != nil || day != nil || when != nil || chip != nil || (hint.map { !$0.isEmpty } ?? false) }

    // MARK: The signature

    /// A fitted signature's start; "1" is a row with nothing for line 2.
    static let mark0 = "f\u{1}"
    private static let sep: Character = "\u{1}"

    var signature: String {
        guard hasLine2 else { return "1" }
        let parts = [title, indent ? "i" : "", mark.map { "m" + $0 } ?? "", day.map { "d" + $0 } ?? "",
                     when.map { "w" + $0 } ?? "", hint.map { "h" + $0 } ?? "", chip.map { "c" + $0 } ?? ""]
        return Self.mark0 + parts.map { $0.replacingOccurrences(of: String(Self.sep), with: " ") }.joined(separator: String(Self.sep))
    }

    init(title: String, indent: Bool = false, mark: String? = nil, day: String? = nil, when: String? = nil,
         hint: String? = nil, chip: String? = nil) {
        self.title = title; self.indent = indent; self.mark = mark; self.day = day; self.when = when
        self.hint = hint; self.chip = chip
    }

    init?(signature s: String) {
        guard s.hasPrefix(Self.mark0) else { return nil }
        let p = s.dropFirst(Self.mark0.count).split(separator: Self.sep, omittingEmptySubsequences: false).map(String.init)
        guard p.count == 7 else { return nil }
        func field(_ i: Int) -> String? { p[i].isEmpty ? nil : String(p[i].dropFirst()) }
        self.init(title: p[0], indent: p[1] == "i", mark: field(2), day: field(3), when: field(4), hint: field(5), chip: field(6))
    }

    /// "1" or "2" for a signature, at `width` (the row's, from its fill's edge to edge) and `category`; nil for one
    /// that isn't a task row's fit.
    @MainActor static func resolve(_ signature: String, width: CGFloat, category: UIContentSizeCategory) -> String? {
        if signature == "1" { return "1" }
        guard let f = RowFit(signature: signature) else { return nil }
        return f.fits(width: width, category: category) ? "1" : "2"
    }

    // MARK: Measuring

    /// The room the title and its parts have: the row less the checkbox's column, the trailing pad and an indent.
    func room(_ width: CGFloat) -> CGFloat { width - Self.lead - Self.trail - (indent ? Self.indentW : 0) }

    @MainActor func fits(width: CGFloat, category: UIContentSizeCategory) -> Bool {
        guard hasLine2 else { return true }
        // Not laid out yet: as if it fits nowhere, which is the old shape; it's resolved again once there's a width.
        guard width > 0 else { return false }
        return natural(category) + Self.slack <= room(width)
    }

    /// The one-line row's natural width, from the title's start to the capsule's end.
    @MainActor func natural(_ c: UIContentSizeCategory) -> CGFloat {
        let m = Measure.shared
        var x = m.text(title, .body, c: c)
        var parts: [CGFloat] = []
        if let mark { parts.append(Metric.markTileW + Self.markGap + m.text(mark, .footnote, c: c)) }
        if let day { parts.append(m.text(day, .footnote, mono: true, c: c)) }
        if let when { parts.append(Self.whenWidth(when, c)) }
        if let hint { parts.append(Self.hintWidth(hint, c)) }
        if !parts.isEmpty { x += Self.titleGap + parts.reduce(0, +) + Self.gap * CGFloat(parts.count - 1) }
        if let chip { x += Self.chipGap + Self.chipWidth(chip, c) }
        return x
    }

    /// `QuietWhen`: the calendar glyph, 3, the words.
    @MainActor static func whenWidth(_ s: String, _ c: UIContentSizeCategory) -> CGFloat {
        let m = Measure.shared
        return m.symbol("calendar", 10.5, .medium) + 3 + m.text(s, .footnote, mono: true, c: c)
    }

    /// `NotesHint`: the count, or the glyph.
    @MainActor static func hintWidth(_ s: String, _ c: UIContentSizeCategory) -> CGFloat {
        let m = Measure.shared
        return s.isEmpty ? m.symbol("text.alignleft", 10, .semibold) : m.text(s, .caption1, weight: .medium, mono: true, c: c)
    }

    /// `DeadlineChip`, compact: 7, the flag, 4, the words, 7.
    @MainActor static func chipWidth(_ s: String, _ c: UIContentSizeCategory) -> CGFloat {
        let m = Measure.shared
        return 7 + m.symbol("flag.fill", 9.5, .semibold) + 4 + m.text(s, .caption1, weight: .medium, mono: true, c: c) + 7
    }
}

extension AppModel {
    /// A task's fit in `source` (`RowFit`), from its row details.
    func rowFit(_ t: TaskModel, source: Source, indent: Bool, groupDay: CalendarDate?, day: CalendarDate?,
                when: CalendarDate? = nil) -> RowFit {
        let d = rowDetails(t, source: source, indent: indent, groupDay: groupDay, day: day, when: when)
        var f = RowFit(title: t.title.isEmpty ? "New Task" : t.title, indent: indent)
        if let l = d.mark { f.mark = l.shortName.isEmpty ? "Untitled" : l.shortName }
        f.day = d.day.map(DateLabel.monthDay)
        f.when = d.when
        if let s = d.summary { f.hint = s.total > 0 ? "\(s.checked)/\(s.total)" : (s.hasNotes ? "" : nil) }
        f.chip = d.deadline.map { DeadlineChip.label($0, today: today, groupDay: groupDay, upcoming: source == .upcoming).text }
        return f
    }
}

/// Text and symbol widths for `RowFit`, remembered (a screen asks for the same words at each update).
@MainActor
final class Measure {
    static let shared = Measure()
    private var texts: [String: CGFloat] = [:]
    private var symbols: [String: CGFloat] = [:]
    private var fonts: [String: UIFont] = [:]

    /// The font SwiftUI draws for `style` (with `weight` and monospaced digits) at the text size `c`.
    func font(_ style: UIFont.TextStyle, weight: UIFont.Weight? = nil, mono: Bool = false, c: UIContentSizeCategory) -> UIFont {
        let key = "\(style.rawValue)|\(weight?.rawValue ?? -9)|\(mono)|\(c.rawValue)"
        if let f = fonts[key] { return f }
        var f = UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: c))
        if let weight {
            let d = f.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            f = UIFont(descriptor: d, size: f.pointSize)
        }
        if mono {
            let d = f.fontDescriptor.addingAttributes([.featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]]])
            f = UIFont(descriptor: d, size: f.pointSize)
        }
        fonts[key] = f
        return f
    }

    func text(_ s: String, _ style: UIFont.TextStyle, weight: UIFont.Weight? = nil, mono: Bool = false,
              c: UIContentSizeCategory) -> CGFloat {
        let key = "\(style.rawValue)|\(weight?.rawValue ?? -9)|\(mono)|\(c.rawValue)|" + s
        if let w = texts[key] { return w }
        let w = (s as NSString).size(withAttributes: [.font: font(style, weight: weight, mono: mono, c: c)]).width
        if texts.count > 4000 { texts.removeAll() }
        texts[key] = w
        return w
    }

    /// An SF Symbol at a fixed size (the rows' glyphs don't scale with the text).
    func symbol(_ name: String, _ size: CGFloat, _ weight: UIImage.SymbolWeight) -> CGFloat {
        let key = "\(name)|\(size)|\(weight.rawValue)"
        if let w = symbols[key] { return w }
        let w = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight))?.size.width ?? size
        symbols[key] = w
        return w
    }
}
