import AppKit
import SwiftUI

/// Lets the window be dragged by its empty background (the hidden title bar's area included), and puts the traffic
/// lights where Rex has them: 9pt further in and down than AppKit's (close button centered 25pt from the corner), on
/// the line of the pane titles. AppKit lays the title bar out again on resizes, key changes and appearance changes
/// (it shrinks the container back to 32pt and leaves the buttons where they were, so they rose to the window's top
/// edge: v2 feedback 9), so they are put back whenever the container or a button moves.
struct WindowConfigurator: NSViewRepresentable {
    var ground: NSColor
    var window: WindowState? = nil

    /// Rex's window controls: the close button's circle spans 18–32pt from the window's top-left corner.
    static let buttonsInset = CGSize(width: 18, height: 18)
    static let buttonSpacing: CGFloat = 23

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            configure(v.window, context.coordinator)
            window?.nsWindow = v.window
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window, context.coordinator) }
    }

    private func configure(_ window: NSWindow?, _ coordinator: Coordinator) {
        guard let window else { return }
        window.isMovableByWindowBackground = true
        window.backgroundColor = ground
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        coordinator.watch(window)
        Self.placeButtons(window)
    }

    @MainActor
    static func placeButtons(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview, let container = titlebar.superview else { return }
        // Room for the lowered buttons: the title bar container grows to Rex's toolbar height.
        let height: CGFloat = 50
        if container.frame.height != height, let frame = container.superview?.bounds {
            container.frame = NSRect(x: 0, y: frame.height - height, width: frame.width, height: height)
        }
        for (i, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(kind) else { continue }
            let size = button.frame.size
            // The circle is 14pt; center it on the button frame's slot.
            let x = buttonsInset.width + CGFloat(i) * buttonSpacing - (size.width - 14) / 2
            let top = buttonsInset.height - (size.height - 14) / 2
            let origin = NSPoint(x: x, y: titlebar.isFlipped ? top : titlebar.bounds.height - top - size.height)
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var window: NSWindow?
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
        nonisolated(unsafe) private var frameObservers: [NSObjectProtocol] = []
        private weak var container: NSView?

        func watch(_ window: NSWindow) {
            watchFrames(window)
            guard self.window !== window else { return }
            self.window = window
            observers.forEach(NotificationCenter.default.removeObserver)
            let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                              NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                                              NSWindow.didExitFullScreenNotification, NSWindow.didChangeScreenNotification]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let window else { return }
                        WindowConfigurator.placeButtons(window)
                        // AppKit may lay the title bar out once more after the notification.
                        DispatchQueue.main.async {
                            WindowConfigurator.placeButtons(window)
                            self?.watchFrames(window)
                        }
                    }
                }
            }
        }

        /// Puts the buttons back from inside AppKit's own title bar layout, the moment it resizes the container or
        /// moves a button, so there's no frame with them out of place. Watched again whenever the container is a new
        /// one (full screen moves the title bar to another window and back).
        private func watchFrames(_ window: NSWindow) {
            guard let close = window.standardWindowButton(.closeButton), let container = close.superview?.superview,
                  container !== self.container else { return }
            self.container = container
            frameObservers.forEach(NotificationCenter.default.removeObserver)
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
            frameObservers = ([container] + buttons).map { view in
                view.postsFrameChangedNotifications = true
                return NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: nil) { [weak window] _ in
                    MainActor.assumeIsolated {
                        guard let window else { return }
                        WindowConfigurator.placeButtons(window)
                    }
                }
            }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
            frameObservers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

#if DEBUG
/// Debug aid: `-snapshotTo /path.png` renders the key window to a PNG once data is on screen, then
/// `-snapshotQuit YES` quits. Used to check the UI against the design boards without screen-recording access.
enum DebugSnapshot {
    @MainActor
    static func runIfRequested() {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "snapshotTo") else { return }
        let delay = defaults.double(forKey: "snapshotDelay") > 0 ? defaults.double(forKey: "snapshotDelay") : 1.5
        if let size = defaults.string(forKey: "debugWindowSize")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let window = NSApp.windows.first(where: { $0.isVisible }) {
                    window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: size[0], height: size[1])), display: true)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView?.superview ?? window.contentView else { return }
            let bounds = view.bounds
            guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
            view.cacheDisplay(in: bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            if defaults.bool(forKey: "snapshotQuit") { NSApp.terminate(nil) }
        }
    }
}
#endif
