import SwiftUI

/// Settings: the theme cards, Light / Dark / System, and Classic or Glass, in Pane's sections and cards.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 17, weight: .semibold)).foregroundStyle(p.ink)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(CapsuleButtonStyle(kind: .tinted, height: 32))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Section("Theme") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 12)], spacing: 16) {
                            ForEach(TasksTheme.all) { t in
                                ThemeCard(theme: t, dark: p.isDark, selected: store.themeID == t.id) {
                                    store.themeID = t.id
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(p.base, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text(TasksTheme.byID(store.themeID).mood + ".")
                            .font(Typo.meta).foregroundStyle(p.ink3).padding(.leading, 4)
                    }

                    Section("Appearance") {
                        VStack(spacing: 0) {
                            stacked("Appearance", "System follows the phone’s Light and Dark.") {
                                Picker("Appearance", selection: $store.appearance) {
                                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                            divider
                            stacked("Interface style", "Glass lets a wallpaper show through the window, the bars and the sheets.") {
                                Picker("Interface style", selection: $store.style) {
                                    ForEach(InterfaceStyle.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        .background(p.base, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Section("About") {
                        VStack(spacing: 0) {
                            row("Tasks", "Version 1.0 · a preview with sample data; nothing is saved.") { EmptyView() }
                            divider
                            row("Lists", "\(store.liveLists.count) lists, \(store.tasks.filter { !$0.isDone && !$0.isTrashed }.count) open tasks.") { EmptyView() }
                        }
                        .background(p.base, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
        .background(p.ground)
        .animation(Motion.natural, value: store.themeID)
    }

    private var divider: some View {
        Rectangle().fill(p.lineSep).frame(height: 1).padding(.horizontal, 14)
    }

    private func row<T: View>(_ title: String, _ description: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.body).foregroundStyle(p.ink)
                Text(description).font(Typo.meta).foregroundStyle(p.ink2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func stacked<T: View>(_ title: String, _ description: String, @ViewBuilder control: () -> T) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.body).foregroundStyle(p.ink)
                Text(description).font(Typo.meta).foregroundStyle(p.ink2).fixedSize(horizontal: false, vertical: true)
            }
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func Section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.ink).padding(.leading, 4)
            content()
        }
    }
}

/// Pane's ThemeTile: a small window in that theme's own palette, its name under it.
struct ThemeCard: View {
    let theme: TasksTheme
    let dark: Bool
    let selected: Bool
    let action: () -> Void
    @Environment(\.palette) private var ui

    var body: some View {
        let p = Palette.make(theme.id, dark: dark)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        Text("Aa").font(.system(size: 19)).foregroundStyle(p.ink)
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2).fill(p.accent).frame(width: 5, height: 16)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(p.accent).frame(width: 9, height: 9)
                        Capsule().fill(p.ink2).frame(height: 3)
                    }
                    HStack(spacing: 5) {
                        Circle().strokeBorder(p.lineField, lineWidth: 1).frame(width: 9, height: 9)
                        Capsule().fill(p.ink3).frame(width: 34, height: 3)
                        Spacer(minLength: 0)
                        Capsule().fill(p.dangerTint).frame(width: 16, height: 7)
                    }
                }
                .padding(10)
                .frame(height: 72)
                .frame(maxWidth: .infinity)
                .background(p.base, in: shape)
                .overlay(shape.strokeBorder(p.linePaneDim, lineWidth: 1))
                .overlay(shape.inset(by: -3.5).strokeBorder(selected ? ui.accent : .clear, lineWidth: 2.5))
                Text(theme.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? ui.ink : ui.ink2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
