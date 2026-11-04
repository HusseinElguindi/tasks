import SwiftUI

/// The root on the phone, and the sidebar on iPad and the Mac: Today, Upcoming, Undated · Lists · Completed, Trash.
struct HomeView: View {
    var sidebar = false
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @State private var folded = false

    var body: some View {
        // A UICollectionView with the app's SwiftUI rows in its cells (HomeCollection.swift).
        HomeCollection(items: HomeCollection.items(app), sidebar: sidebar,
                       folded: Binding(get: { folded }, set: { v in animate(.easeOut(duration: 0.15)) { folded = v } }))
            // Its own bottom inset on the phone, the floating controls' clearance (HomeCollection.swift).
            .ignoresSafeArea(.all, edges: sidebar ? [] : .bottom)
            .background(AppBackground())
            // The phone's bar stays, as on a list's screen (ListScreen): pull to refresh draws its indicator only with
            // the bar there. Empty at rest; the name fades in once the large one has gone under it.
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !sidebar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 7) {
                            LogoMark(size: 20)
                            Text("Tasks").font(.system(size: 17, weight: .semibold)).foregroundStyle(p.ink)
                        }
                        .opacity(folded ? 1 : 0)
                        .accessibilityHidden(!folded)
                    }
                }
            }
    }
}

/// Home's header: the mark and "Tasks", large on the phone.
struct HomeHeader: View {
    let sidebar: Bool
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: sidebar ? 9 : 11) {
            LogoMark(size: sidebar ? 22 : 30)
            Text("Tasks")
                .font(sidebar ? .system(size: 20, weight: .semibold) : Typo.largeTitle)
                .foregroundStyle(p.ink)
            Spacer()
        }
        .padding(.leading, Metric.rowPad - 2)
        .padding(.top, 4)
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
            let counted = (count ?? 0) > 0
            HStack(spacing: 0) {
                app.tile(for: source, palette: p)
                    .padding(.trailing, 12)
                // A long name fades out over its last 21pt instead of an ellipsis (§12, Rex), ending 39 short of the
                // row's edge when there's a count (a wider count, 8 before it) and 13 short when not (§12).
                Text(app.title(source))
                    .font(Typo.row)
                    .foregroundStyle(current || !sidebar ? p.ink : p.inkSecondary)
                    .fadeTruncation(Metric.nameFade, text: app.title(source))
                Spacer(minLength: 0)
                if let count, counted {
                    Text("\(count)")
                        .font(Typo.row)
                        .monospacedDigit()
                        .foregroundStyle(source == .today ? p.inkSecondary : p.inkTertiary)
                        .padding(.leading, 8)
                        .frame(minWidth: Metric.nameEnd - Metric.rowPad, alignment: .trailing)
                }
            }
            .padding(.leading, Metric.rowPad)
            .padding(.trailing, counted ? Metric.rowPad : Metric.nameEndBare)
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
        // iPad's sidebar, while adding in the list beside it: a tap only ends adding, and opens nothing.
        .endsAddingOnTap()
        .accessibilityLabel(count.map { "\(app.title(source)), \($0)" } ?? app.title(source))
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}
