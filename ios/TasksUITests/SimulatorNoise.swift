import XCTest

extension XCTestCase {
    /// The iOS 27.2 simulator's intelligencetasksd traps at every launch ("XPC Peer Requirement isn't implemented
    /// on simulators yet"), and XCTest blames whichever UI test is running, because its crash-report watcher matches
    /// "intelligencetasksd" against our process name "Tasks". Only that issue is expected; any other failure,
    /// an app crash included, still fails the test.
    func expectSimulatorDaemonCrash() {
        #if targetEnvironment(simulator)
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { $0.compactDescription.hasPrefix("Critical process intelligencetasksd crashed") }
        XCTExpectFailure("Apple's intelligencetasksd crash on the simulator, not the app", options: options)
        #endif
    }
}
