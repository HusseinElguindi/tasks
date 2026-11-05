import UIKit

/// The keyboard's machinery, made once soon after launch, while nothing moves, instead of in the first drag.
///
/// A drag session turns the keyboard off as it begins (`_UIRemoteKeyboards setKeyboardDisabled`, from the system), and
/// the first time in a launch that made the app's keyboard window and its parts then: the text-effects window, the
/// input-view placement, TextInputUI loaded. Measured on the simulator (Time Profiler, T21): about 250 ms of the main
/// thread, as the first drag's gap opened at its first new slot, a frame of 200-295 ms there (Home and the task lists
/// alike); later drags in the same launch had none of it. Home has no text field, so there it was every first drag.
///
/// Made here instead: a field out of sight is focused and let go in the same moment, with an empty input view, so no
/// keyboard shows (UIKit posts only a will-change-frame and a will-hide of a zero-height frame at the screen's foot,
/// which change nothing: PhoneRoot's `keyboardUp` and TaskCollection's inset stay as they are). It waits for the run
/// loop's default mode, so it never runs while a list scrolls or a finger tracks, and it's skipped while anything is
/// being typed into, under VoiceOver (whose focus would follow the field), and on iPad (its hardware-keyboard bars).
@MainActor
enum KeyboardWarmUp {
    private static var done = false

    /// After launch: 1.5 s on, in the run loop's default mode (not while scrolling or tracking).
    static func schedule(after delay: TimeInterval = 1.5) {
        guard !done else { return }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "noKeyboardWarmUp") { return }
        #endif
        let t = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { run() } }
        RunLoop.main.add(t, forMode: .default)
    }

    private static func run() {
        guard !done, UIDevice.current.userInterfaceIdiom == .phone, !UIAccessibility.isVoiceOverRunning else { return }
        // In the background, or while something is typed into: later.
        guard UIApplication.shared.applicationState == .active, !Responder.anyEditing(),
              let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else {
            schedule(after: 3)
            return
        }
        done = true
        let f = UITextField(frame: CGRect(x: -10_000, y: 0, width: 10, height: 10))
        f.inputView = UIView(frame: .zero)
        f.inputAssistantItem.leadingBarButtonGroups = []
        f.inputAssistantItem.trailingBarButtonGroups = []
        f.autocorrectionType = .no
        f.spellCheckingType = .no
        f.isAccessibilityElement = false
        w.addSubview(f)
        f.becomeFirstResponder()
        f.resignFirstResponder()
        f.removeFromSuperview()
    }

    /// The first responder, found by an action sent to it.
    @MainActor fileprivate enum Responder {
        static weak var found: UIResponder?
        static func anyEditing() -> Bool {
            found = nil
            UIApplication.shared.sendAction(#selector(UIResponder.keyboardWarmUpFind(_:)), to: nil, from: nil, for: nil)
            defer { found = nil }
            // With no first responder, the action may reach the window or the app itself.
            guard let r = found, r.isFirstResponder else { return false }
            return !(r is UIApplication || r is UIWindow)
        }
    }
}

extension UIResponder {
    /// KeyboardWarmUp's look for the first responder (sent to whichever it is).
    @objc fileprivate func keyboardWarmUpFind(_ sender: Any?) { KeyboardWarmUp.Responder.found = self }
}
