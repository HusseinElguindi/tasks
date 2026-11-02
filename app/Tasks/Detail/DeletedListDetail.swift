import SwiftUI
import TasksCore

/// A deleted list selected in Trash (§28 Selecting the row, `Del-A`): its tile and name where a task's checkbox and
/// title go, read-only; Tasks ("11 open · 4 completed") and Place (where Restore will put it); Restore and Open; the
/// separator; its notes, read-only; and "Created Aug 31 · Deleted Nov 1".
struct DeletedListDetail: View {
    let store: Store
    let list: ListModel
    let actions: WindowActions
    @Environment(\.tk) private var tk

    var body: some View {
        let p = store.projection
        let open = p.openTaskCount(in: list.id)
        let done = p.completedTasks(in: list.id).count
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                // The tile 2 left of the box's column, so the name starts where a title does (`.dlt`).
                HStack(spacing: 8) {
                    TileView(monogram: list.monogram, hue: tk.tile(slot: list.colorSlot))
                        .padding(.leading, -2)
                    Text(list.name.isEmpty ? "Untitled" : list.name)
                        .font(Font(TK.Font.detailTitle))
                        .foregroundStyle(tk.ink.swiftUI)
                        .lineLimit(2)
                }
                .frame(minHeight: 20)
                VStack(alignment: .leading, spacing: 0) {
                    PropRow(glyph: .lines, label: "Tasks") { _ in value("\(open) open · \(done) completed") }
                    PropRow(glyph: .putBack, label: "Place") { _ in value(place(p)) }
                }
                .padding(.top, 12)
                .allowsHitTesting(false)
                HStack(spacing: 8) {
                    CapsuleButton(tinted: true, action: { actions.restoreList(list.id) }) { Text(TrashVerb.list.title) }
                    CapsuleButton(action: { actions.openDeletedList(list.id) }) { Text("Open") }
                }
                .padding(.top, 8)
                Rectangle()
                    .fill(tk.lineSeparator.swiftUI)
                    .frame(height: 1)
                    .padding(.top, 10)
                if !list.notes.isEmpty {
                    Text(list.notes)
                        .font(Font(TK.Font.body))
                        .foregroundStyle(tk.inkSecondary.swiftUI)
                        .lineSpacing(19 - NSLayoutManager().defaultLineHeight(for: TK.Font.body))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.top, 12)
                }
                Text(meta)
                    .font(Font(TK.Font.caption))
                    .foregroundStyle(tk.inkTertiary.swiftUI)
                    .lineLimit(1)
                    .frame(height: 14)
                    .padding(.top, 14)
            }
            .padding(.top, 8)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(list.name), deleted list")
    }

    private func value(_ s: String) -> some View {
        Text(s).font(Font(TK.Font.body)).foregroundStyle(tk.ink.swiftUI).lineLimit(1).frame(height: 16)
    }

    /// Where Restore will put it: after the nearest live list above its key, else "The top of Lists".
    private func place(_ p: Projection) -> String {
        let above = p.activeLists.ids.compactMap(p.list).last { orderPrecedes($0.order, $0.id, list.order, list.id) }
        guard let above else { return "The top of Lists" }
        return "Lists, after " + (above.name.isEmpty ? "Untitled" : above.name)
    }

    private var meta: String {
        func day(_ ms: Int) -> String { DateLabel.monthDay(CalendarDate(Date(timeIntervalSince1970: TimeInterval(ms) / 1000))) }
        return "Created " + day(list.createdAt) + (list.archivedAt.map { " · Deleted " + day($0) } ?? "")
    }
}
