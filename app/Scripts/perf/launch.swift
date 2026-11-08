// Launches an app binary and times it to its first on-screen window (coord title-design T8).
//
//   swiftc -O app/Scripts/perf/launch.swift -o launchtime
//   launchtime <executable> [args…]
//
// Prints the pid, then the time from exec to the first on-screen window the process owns (CGWindowList, polled every
// 2 ms; no screen-recording permission needed for owner and bounds), then leaves the app running. Run it a few times
// and take the median: the first run after a build pays for the dyld closure and the page cache.
import CoreGraphics
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let exe = args.first else { print("usage: launchtime <executable> [args…]"); exit(2) }
let p = Process()
p.executableURL = URL(fileURLWithPath: exe)
p.arguments = Array(args.dropFirst())
p.standardOutput = FileHandle.nullDevice
p.standardError = FileHandle(forWritingAtPath: "/dev/null")
let t0 = DispatchTime.now().uptimeNanoseconds
try p.run()
let pid = p.processIdentifier
print("pid \(pid)")
fflush(stdout)
let deadline = t0 + 20_000_000_000
while DispatchTime.now().uptimeNanoseconds < deadline {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    if let w = list.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }) {
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        print(String(format: "first window %.0f ms  (%@x%@)", ms, "\(b["Width"] ?? "?")", "\(b["Height"] ?? "?")"))
        exit(0)
    }
    usleep(2000)
}
print("no window within 20 s")
exit(1)
