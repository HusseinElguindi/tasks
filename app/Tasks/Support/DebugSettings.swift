#if DEBUG
import AppKit
import SwiftUI

/// Debug aid: `-snapshotSettings /path.png` renders Settings (⌘,) to a PNG from a window that's never shown, so it can
/// be checked with the app in the background (opening the real Settings window would bring the app forward).
@MainActor
enum DebugSettingsSnapshot {
    private static var window: NSWindow?

    static func runIfRequested(_ model: AppModel) {
        guard let path = UserDefaults.standard.string(forKey: "snapshotSettings") else { return }
        let host = NSHostingView(rootView: ThemedRoot(model: model) { SettingsView() }.environment(model))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = host
        window = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            host.setFrameSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
#endif
