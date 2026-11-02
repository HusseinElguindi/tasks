import SwiftUI

/// The phone gets a stack (home, then a list, details in a sheet); iPad gets the Mac's three panes.
struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.horizontalSizeClass) private var size

    var body: some View {
        Group {
            if size == .regular { SplitRoot() } else { PhoneRoot() }
        }
        .onAppear { store.isSplit = size == .regular }
        .onChange(of: size) { _, s in store.isSplit = s == .regular }
    }
}

private struct IDBox: Identifiable { let id: String }

// MARK: - Phone

struct PhoneRoot: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.interfaceStyle) private var style
    @State private var keyboardUp = false

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            HomeView()
                .navigationDestination(for: Source.self) { s in ListScreen(source: s) }
        }
        .overlay(alignment: .bottom) {
            // Out of the way while typing: the keyboard's Return adds the next task.
            FloatingControls(source: store.path.last, home: store.path.isEmpty)
                .ignoresSafeArea(.keyboard)
                .opacity(keyboardUp ? 0 : 1)
                .allowsHitTesting(!keyboardUp)
                .animation(.easeOut(duration: 0.15), value: keyboardUp)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .sheet(item: Binding(get: { store.detailTask.map(IDBox.init) }, set: { store.detailTask = $0?.id })) { box in
            TaskDetailView(taskID: box.id)
                .themed(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(style == .glass ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(p.base))
        }
        .sheet(item: Binding(get: { store.detailTask == nil ? store.dateTarget : nil }, set: { store.dateTarget = $0 })) { t in
            DatePickerSheet(target: t).themed(store).datePickerPresentation()
        }
        .sheet(isPresented: $store.showSettings) {
            SettingsView().themed(store).presentationDragIndicator(.visible)
        }
        .listEditorAlert()
    }
}

/// The bar on the home screen (New List, Settings), the + button, and the notice above them.
struct FloatingControls: View {
    let source: Source?
    let home: Bool
    var showBar = true
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let n = store.notice {
                NoticeView(notice: n)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .center, spacing: 12) {
                if home && showBar { HomeBar() } else { Spacer() }
                if home || (source?.canAdd ?? false) {
                    AddButton { add() }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(Motion.natural, value: home)
        .animation(Motion.natural, value: source?.canAdd)
    }

    private func add() {
        if home || source == nil {
            store.open(.list("inbox"))
            store.startDraft(.list("inbox"))
        } else if let s = source {
            if store.draft?.source == s { store.commitDraft() } else { store.startDraft(s) }
        }
    }
}

/// The home screen's glass capsule: New List at the left, Settings at the right.
struct HomeBar: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 0) {
            Button { store.listEditor = .init(listID: nil, name: "") } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                    Text("New List").font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(p.ink)
                .padding(.horizontal, 18)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { store.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(p.ink2)
                    .frame(width: 52, height: Metric.barHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .frame(height: Metric.barHeight)
        .floatingGlass(Capsule())
    }
}

/// The round + : a new task in this list, or in the Inbox from home.
struct AddButton: View {
    let action: () -> Void
    @Environment(\.palette) private var p
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(p.onAccent)
                .frame(width: Metric.fab, height: Metric.fab)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .floatingGlass(Circle(), tint: p.accent)
        .shadow(color: p.accent.opacity(0.28), radius: 12, y: 4)
        .accessibilityLabel("New Task")
    }
}

/// "Completed “Email TA…”" with Undo: a floating capsule that goes after four seconds.
struct NoticeView: View {
    let notice: Notice
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 12) {
            Text(notice.text)
                .font(Typo.body)
                .foregroundStyle(p.ink)
                .lineLimit(1)
            if notice.undo != nil {
                Button { store.undo() } label: { Text("Undo") }
                    .buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 32))
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, notice.undo == nil ? 18 : 7)
        .frame(height: 46)
        .background(p.popover, in: Capsule())
        .overlay(Capsule().strokeBorder(p.ink.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(p.isDark ? 0.45 : 0.14), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - iPad

/// The Mac's window, on iPad: the sidebar on the ground, the list and the details as panes 8 apart.
struct SplitRoot: View {
    @Environment(Store.self) private var store
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columns) {
            HomeView(sidebar: true)
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 320)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom) { HomeBar().padding(.horizontal, 12).padding(.bottom, 6) }
        } content: {
            ContentColumn()
                .navigationSplitViewColumnWidth(min: 360, ideal: 440)
        } detail: {
            DetailColumn()
                .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
        .background(AppBackground())
        .sheet(item: $store.dateTarget) { t in DatePickerSheet(target: t).themed(store).datePickerPresentation() }
        .sheet(isPresented: $store.showSettings) { SettingsView().themed(store) }
        .listEditorAlert()
    }
}

/// The split view's middle column: the selected list as a pane, its + and notice at the foot.
/// (Its own view, so it observes the store itself; the split view's column closures don't.)
private struct ContentColumn: View {
    @Environment(Store.self) private var store
    var body: some View {
        let source = store.selection ?? .today
        ListScreen(source: source)
            .id(source)
            .pane(focused: store.selectedTask == nil)
            .overlay(alignment: .bottom) {
                FloatingControls(source: source, home: false, showBar: false)
                    .padding(.bottom, 8)
            }
    }
}

/// The split view's third column: the selected task's details, or nothing selected.
private struct DetailColumn: View {
    @Environment(Store.self) private var store
    var body: some View {
        Group {
            if let id = store.selectedTask {
                TaskDetailView(taskID: id, inline: true).id(id)
            } else {
                NothingSelected()
            }
        }
        .pane(focused: store.selectedTask != nil)
    }
}

private struct PaneModifier: ViewModifier {
    let focused: Bool
    @Environment(\.palette) private var p
    @Environment(\.interfaceStyle) private var style
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        content
            .background { shape.fill((focused ? p.base : p.dim).opacity(style == .glass ? 0.88 : 1)) }
            .clipShape(shape)
            .overlay(shape.strokeBorder(focused ? p.linePane : p.linePaneDim, lineWidth: 1))
            .padding(8)
            .background(AppBackground())
            .animation(.easeOut(duration: 0.06), value: focused)
    }
}

extension View {
    func pane(focused: Bool) -> some View { modifier(PaneModifier(focused: focused)) }

    func datePickerPresentation() -> some View {
        presentationDetents([.height(560), .large]).presentationDragIndicator(.visible)
    }

    /// Applies the chosen theme: the derived palette, the interface style, the accent as tint and the colour scheme.
    func themed(_ store: Store) -> some View { modifier(Themed(store: store)) }

    func listEditorAlert() -> some View { modifier(ListEditorAlert()) }
}

struct Themed: ViewModifier {
    let store: Store
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark = store.appearance == .system ? scheme == .dark : store.appearance == .dark
        let pal = Palette.make(store.themeID, dark: dark)
        content
            .environment(store)
            .environment(\.palette, pal)
            .environment(\.interfaceStyle, store.style)
            .tint(pal.accent)
            .preferredColorScheme(store.appearance == .system ? nil : (dark ? .dark : .light))
    }
}

/// New List and Rename: one alert with the name field.
private struct ListEditorAlert: ViewModifier {
    @Environment(Store.self) private var store
    func body(content: Content) -> some View {
        @Bindable var store = store
        content.alert(store.listEditor?.listID == nil ? "New List" : "Rename List",
                      isPresented: Binding(get: { store.listEditor != nil }, set: { if !$0 { store.listEditor = nil } })) {
            TextField("Name", text: Binding(get: { store.listEditor?.name ?? "" }, set: { store.listEditor?.name = $0 }))
            Button("Cancel", role: .cancel) { store.listEditor = nil }
            Button(store.listEditor?.listID == nil ? "Create" : "Rename") {
                if let e = store.listEditor { store.saveList(e) }
                store.listEditor = nil
            }
        }
    }
}
