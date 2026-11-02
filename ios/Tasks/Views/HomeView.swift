import SwiftUI

/// The root on the phone, and the sidebar on iPad and the Mac: Today, Upcoming, Undated · Lists · Completed, Trash.
struct HomeView: View {
    var sidebar = false
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        List {
            header.listRow()
            SourceRow(source: .today, count: app.todayCount(), sidebar: sidebar).listRow()
            SourceRow(source: .upcoming, sidebar: sidebar).listRow()
            SourceRow(source: .undated, sidebar: sidebar).listRow()
            GroupLabel(title: "Lists").listRow()
            ForEach(app.activeLists) { l in
                SourceRow(source: .list(l.id), count: app.openCount(l.id), sidebar: sidebar)
                    .contextMenu {
                        Button { app.listEditor = .init(listID: l.id, name: l.name) } label: { Label("Rename", systemImage: "pencil") }
                        Divider()
                        Button(role: .destructive) { app.deleteList(l.id) } label: { Label("Delete List", systemImage: "trash") }
                    }
                    .listRow()
            }
            Color.clear.frame(height: 14).listRow()
            SourceRow(source: .completed, sidebar: sidebar).listRow()
            SourceRow(source: .trash, sidebar: sidebar).listRow()
            if let s = app.syncSummary { SyncLine(text: s).listRow() }
            Color.clear.frame(height: sidebar ? 60 : Metric.bottomClearance).listRow()
        }
        .listStyle(.plain)
        .refreshable { await app.syncNow() }
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .background(AppBackground())
        .toolbar(sidebar ? .automatic : .hidden, for: .navigationBar)
        .navigationTitle("Tasks")
    }

    private var header: some View {
        HStack(spacing: sidebar ? 9 : 11) {
            LogoMark(size: sidebar ? 22 : 30)
            Text("Tasks")
                .font(sidebar ? .system(size: 20, weight: .semibold) : Typo.largeTitle)
                .foregroundStyle(p.ink)
            Spacer()
        }
        .padding(.leading, Metric.rowPad - 2)
        .padding(.top, sidebar ? 4 : 10)
        .padding(.bottom, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tasks")
        .accessibilityAddTraits(.isHeader)
    }
}

/// How sync is doing, quietly, under the views (the Mac's sync indicator, in words). Pull down to sync now.
struct SyncLine: View {
    let text: String
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "icloud").font(.system(size: 12, weight: .medium))
            Text(text).font(Typo.meta).lineLimit(1)
        }
        .foregroundStyle(p.inkTertiary)
        .padding(.leading, Metric.rowPad + 2)
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync: " + text)
    }
}

/// A view or list on the home screen: its tile, name and count. In the sidebar the current one is a lifted capsule.
struct SourceRow: View {
    let source: Source
    var count: Int? = nil
    var sidebar = false
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        let current = sidebar && app.selection == source
        Button { app.open(source) } label: {
            HStack(spacing: 12) {
                app.tile(for: source, palette: p)
                Text(app.title(source))
                    .font(Typo.row)
                    .foregroundStyle(current || !sidebar ? p.ink : p.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(Typo.row)
                        .monospacedDigit()
                        .foregroundStyle(source == .today ? p.inkSecondary : p.inkTertiary)
                }
            }
            .padding(.leading, Metric.rowPad)
            .padding(.trailing, Metric.rowPad)
            .frame(minHeight: Metric.rowHeight)
            .background {
                if current {
                    RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous)
                        .fill(p.fillStrong)
                        .overlay(RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous).strokeBorder(p.edgeInner, lineWidth: 1))
                        .overlay(RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous).strokeBorder(p.edgeOuter, lineWidth: 0.5))
                }
            }
        }
        .buttonStyle(RowStyle())
        .accessibilityLabel(count.map { "\(app.title(source)), \($0)" } ?? app.title(source))
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}
