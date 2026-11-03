import SwiftUI

/// The phone gets a stack (home, then a list, details in a sheet); iPad gets the Mac's three panes.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var size

    var body: some View {
        Group {
            if size == .regular { SplitRoot() } else { PhoneRoot() }
        }
        .onAppear { app.isSplit = size == .regular }
        .onChange(of: size) { _, s in app.isSplit = s == .regular }
        // TasksCore's own notices ("A change couldn't be saved."), as the app's.
        .onChange(of: app.store.notice) { _, n in
            guard let n else { return }
            app.show(Notice(text: n, undo: nil))
            app.store.notice = nil
        }
        .onChange(of: app.syncStoppedWords) { old, new in
            if old == nil, let new { AccessibilityNotification.Announcement(new).post() }
        }
    }
}

private struct IDBox: Identifiable { let id: String }

// MARK: - Phone

struct PhoneRoot: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.interfaceStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyboardUp = false

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            HomeView()
                .navigationDestination(for: Source.self) { s in ListScreen(source: s) }
        }
        .overlay(alignment: .bottom) {
            // Out of the way while typing: the keyboard's Return adds the next task.
            FloatingControls(source: app.path.last, home: app.path.isEmpty)
                .ignoresSafeArea(.keyboard)
                .opacity(keyboardUp ? 0 : 1)
                .allowsHitTesting(!keyboardUp)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: keyboardUp)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .sheet(item: Binding(get: { app.detailTask.map(IDBox.init) }, set: { app.detailTask = $0?.id })) { box in
            TaskDetailView(taskID: box.id)
                .themed(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(style == .glass ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(p.base))
        }
        .sheet(item: Binding(get: { app.detailTask == nil ? app.dateTarget : nil }, set: { app.dateTarget = $0 })) { t in
            DatePickerSheet(target: t).themed(app).datePickerPresentation()
        }
        .sheet(isPresented: $app.showSettings) {
            SettingsView().themed(app).presentationDragIndicator(.visible)
        }
        .listEditorAlert()
    }
}

/// The bar on the home screen (New List, Settings), the + button, and the notice above them.
struct FloatingControls: View {
    let source: Source?
    let home: Bool
    var showBar = true
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let n = app.notice {
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
        // Reduce Motion: they change at once (IX:255).
        .animation(reduceMotion ? nil : Motion.natural, value: home)
        .animation(reduceMotion ? nil : Motion.natural, value: source?.canAdd)
    }

    private func add() {
        // No live list to put it in: say so, as the Mac does.
        guard let id = app.store.defaultListID else {
            app.show(Notice(text: "Create a list first", undo: nil))
            return
        }
        if home || source == nil {
            // From home, a new task in the default list (the first in the sidebar, as on the Mac).
            app.open(.list(id))
            app.startDraft(.list(id))
        } else if let s = source {
            if app.draft?.source == s, app.draft?.addsTask == true { app.submitDraft() } else { app.startDraft(s) }
        }
    }
}

/// The home screen's glass capsule: New List at the left, Settings at the right.
struct HomeBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 0) {
            Button { app.listEditor = .init(listID: nil, name: "") } label: {
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
            Button { app.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(p.inkSecondary)
                    .frame(width: 52, height: Metric.barHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .frame(height: Metric.barHeight)
        .floatingGlass(Capsule())
        // iPad's sidebar, while adding in the list beside it: a tap only ends adding (no new list, no Settings).
        .endsAddingOnTap()
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
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 12) {
            Text(notice.text)
                .font(Typo.body)
                .foregroundStyle(p.ink)
                .lineLimit(1)
            if notice.undo != nil {
                Button { app.undoNotice() } label: { Text("Undo") }
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
    @Environment(AppModel.self) private var app
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var app = app
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
        .sheet(item: $app.dateTarget) { t in DatePickerSheet(target: t).themed(app).datePickerPresentation() }
        .sheet(isPresented: $app.showSettings) { SettingsView().themed(app) }
        .listEditorAlert()
    }
}

/// The split view's middle column: the selected list as a pane, its + and notice at the foot.
/// (Its own view, so it observes the app model itself; the split view's column closures don't.)
private struct ContentColumn: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        let source = app.selection ?? .today
        ListScreen(source: source)
            .id(source)
            .pane(focused: app.selectedTask == nil)
            .overlay(alignment: .bottom) {
                FloatingControls(source: source, home: false, showBar: false)
                    .padding(.bottom, 8)
            }
    }
}

/// The split view's third column: the selected task's details, or nothing selected.
private struct DetailColumn: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        Group {
            if let id = app.selectedTask {
                TaskDetailView(taskID: id, inline: true).id(id)
            } else {
                NothingSelected()
            }
        }
        // While adding in the list beside it, a tap on the task shown here only ends adding.
        .endsAddingOnTap()
        .pane(focused: app.selectedTask != nil)
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

    /// Applies the theme: the appearance's palette, the interface style, the accent as tint and the colour scheme.
    func themed(_ app: AppModel) -> some View { modifier(Themed(app: app)) }

    func listEditorAlert() -> some View { modifier(ListEditorAlert()) }
}

struct Themed: ViewModifier {
    let app: AppModel
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark = app.appearance == .system ? scheme == .dark : app.appearance == .dark
        let pal = Palette.make(dark: dark)
        content
            .environment(app)
            .environment(\.palette, pal)
            .environment(\.interfaceStyle, app.style)
            .tint(pal.accent)
            .preferredColorScheme(app.appearance == .system ? nil : (dark ? .dark : .light))
    }
}

/// New List and Rename: one alert with the name field.
private struct ListEditorAlert: ViewModifier {
    @Environment(AppModel.self) private var app
    func body(content: Content) -> some View {
        @Bindable var app = app
        content.alert(app.listEditor?.listID == nil ? "New List" : "Rename List",
                      isPresented: Binding(get: { app.listEditor != nil }, set: { if !$0 { app.listEditor = nil } })) {
            TextField("Name", text: Binding(get: { app.listEditor?.name ?? "" }, set: { app.listEditor?.name = $0 }))
            Button("Cancel", role: .cancel) { app.listEditor = nil }
            Button(app.listEditor?.listID == nil ? "Create" : "Rename") {
                if let e = app.listEditor { app.saveList(e) }
                app.listEditor = nil
            }
        }
    }
}
