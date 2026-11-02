import SwiftUI
import TasksCore

/// Settings: System / Light / Dark and Classic or Glass, in Pane's sections and cards. One theme, the Mac's.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var app = app
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
                    Section("Appearance") {
                        VStack(spacing: 0) {
                            stacked("Appearance", "System follows the phone’s Light and Dark.") {
                                Picker("Appearance", selection: $app.appearance) {
                                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                            divider
                            stacked("Interface style", "Glass lets a wallpaper show through the window, the bars and the sheets.") {
                                Picker("Interface style", selection: $app.style) {
                                    ForEach(InterfaceStyle.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        .background(p.base, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Section("About") {
                        VStack(spacing: 0) {
                            row("Tasks", "Version \(version)") { EmptyView() }
                            divider
                            row("Lists", "\(lists.count) lists, \(lists.reduce(0) { $0 + app.openCount($1.id) }) open tasks.") { EmptyView() }
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
    }

    private var lists: [ListModel] { app.activeLists }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }

    private var divider: some View {
        Rectangle().fill(p.lineSeparator).frame(height: 1).padding(.horizontal, 14)
    }

    private func row<T: View>(_ title: String, _ description: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.body).foregroundStyle(p.ink)
                Text(description).font(Typo.meta).foregroundStyle(p.inkSecondary).fixedSize(horizontal: false, vertical: true)
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
                Text(description).font(Typo.meta).foregroundStyle(p.inkSecondary).fixedSize(horizontal: false, vertical: true)
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
