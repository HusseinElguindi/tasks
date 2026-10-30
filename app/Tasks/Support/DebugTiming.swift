#if DEBUG
import AppKit
import Foundation
import OSLog
import QuartzCore
import TasksCore

/// Debug aid for the last §9 budget, "switching lists ≤ 1 frame (16 ms) to first rows": `-debugMeasureSwitch <file>`
/// switches between lists and records, per switch, the time from changing the route to the first row of the new list
/// appearing (latency, which includes waiting for the display's update cycle) and the main-thread work the switch
/// costs (the route change, then the window's update and layout forced right away: our work plus SwiftUI's), then
/// quits. `-debugBulk N` first adds a list "Big" with N open tasks; `-debugRounds N` (default 3) sets the rounds.
@MainActor
enum DebugTiming {
    private static var started: CFTimeInterval?
    private static var waiting: CheckedContinuation<Double, Never>?
    private static var token = 0
    /// Row bodies evaluated since the last switch.
    static var rowBodies = 0
    /// Each measured switch is a "switch" interval in Instruments' Points of Interest.
    private static let signposter = OSSignposter(subsystem: "com.elguindi.Tasks.dev", category: .pointsOfInterest)
    private static var interval: OSSignpostIntervalState?

    /// Called by every task row's onAppear.
    static func rowAppeared() {
        guard let start = started, let c = waiting else { return }
        started = nil
        waiting = nil
        if let interval { signposter.endInterval("switch", interval) }
        interval = nil
        c.resume(returning: (CACurrentMediaTime() - start) * 1000)
    }

    static func runIfRequested(_ store: Store, _ window: WindowState) {
        let args = ProcessInfo.processInfo.arguments
        func arg(_ name: String) -> String? {
            guard let i = args.firstIndex(of: "-" + name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let out = arg("debugMeasureSwitch") else { return }
        Task { @MainActor in
            if let n = arg("debugBulk").flatMap(Int.init), n > 0 {
                let big = store.projection.activeLists.ids.first { store.projection.list($0)?.name == "Big" }
                    ?? store.createList(name: "Big")
                if store.projection.openTasks(in: big).count < n {
                    for i in 0..<n { store.createTask(title: "Bulk task \(i) with a title of a realistic length", in: big) }
                }
            }
            try? await Task.sleep(for: .seconds(1))
            var lines: [String] = []
            let routes: [(String, WindowState.Route)] = [("today", .today)]
                + store.projection.activeLists.ids.map { (store.projection.list($0)?.name ?? $0, .list($0)) }
            // Walk the sidebar in order, so most switches are list → list (the common case), plus list → Today.
            var previous = "start"
            window.route = .today
            try? await Task.sleep(for: .milliseconds(300))
            let rounds = Int(arg("debugRounds") ?? "") ?? 3
            for round in 0...rounds {
                for (name, route) in routes.dropFirst() + [routes[0]] {
                    token += 1
                    let mine = token
                    rowBodies = 0
                    var work = 0.0
                    let ms = await withCheckedContinuation { c in
                        waiting = c
                        interval = signposter.beginInterval("switch", "\(previous) → \(name)")
                        let t0 = CACurrentMediaTime()
                        started = t0
                        window.route = route
                        if let view = NSApp.windows.first(where: { $0.isVisible })?.contentView {
                            view.layoutSubtreeIfNeeded()
                            view.displayIfNeeded()
                        }
                        work = (CACurrentMediaTime() - t0) * 1000
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            // An empty list shows no rows; give up on this one only.
                            if token == mine, let w = waiting { waiting = nil; started = nil; w.resume(returning: -1) }
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                    if round > 0 {
                        lines.append(String(format: "%@ → %@\t%.2f ms\t%.2f ms work\t%d row bodies", previous, name, ms, work, rowBodies))
                    }
                    previous = name
                }
            }
            try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
}
#endif

#if DEBUG
/// Debug aid: `-debugKeyLog <file>` appends each key event with the key window and its first responder.
@MainActor
enum DebugKeyLog {
    private static var monitor: Any?

    static func installIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard monitor == nil, let i = args.firstIndex(of: "-debugKeyLog"), i + 1 < args.count else { return }
        let path = args[i + 1]
        func append(_ line: String) {
            if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
            else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
        }
        PaneHoverDebug.log = { append(String(format: "%.3f ", CACurrentMediaTime()) + $0 + "\n") }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            let key = NSApp.keyWindow.map { "\(type(of: $0))#\($0.windowNumber)" } ?? "none"
            let responder = NSApp.keyWindow?.firstResponder.map { "\(type(of: $0))" } ?? "none"
            append("\(event.type == .keyDown ? "key \(event.keyCode)" : "mouse") keyWindow=\(key) firstResponder=\(responder)\n")
            return event
        }
    }
}
#endif
