// The theme is the Mac's own, shared through the TasksTheme package (app/TasksCore/Sources/TasksTheme): Rex with the
// Ember accent, its tokens and the lit tile's finish, as sRGB values. This is iOS's side of it: the values as SwiftUI
// colours (the Mac's `ns`, in app/Tasks/Theme/Theme.swift, is AppKit's).
import SwiftUI
import TasksTheme

extension RGBA {
    /// Pure white and black stay the system's own (a gray colour space), as the Mac's `ns` keeps them.
    var color: Color {
        if r == g, g == b, r == 1 || r == 0 { return (r == 1 ? Color.white : .black).opacity(a) }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
