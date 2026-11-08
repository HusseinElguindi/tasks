// Moves the scratch app between the idle scenarios without Accessibility or Automation permission (coord
// title-design T8): NSRunningApplication's hide, unhide and activate are Launch Services calls.
//
//   swiftc -O app/Scripts/perf/appctl.swift -o appctl
//   appctl <pid> hide|unhide|front|state      appctl front-pid      appctl activate-pid <pid>
import AppKit

let a = CommandLine.arguments
func app(_ s: String) -> NSRunningApplication? { Int32(s).flatMap { NSRunningApplication(processIdentifier: $0) } }
switch (a.count > 1 ? a[1] : "", a.count > 2 ? a[2] : "") {
case ("front-pid", _):
    print(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)
case ("activate-pid", let p):
    print(app(p)?.activate() ?? false)
case (let p, "hide"): print(app(p)?.hide() ?? false)
case (let p, "unhide"): print(app(p)?.unhide() ?? false)
case (let p, "front"): print(app(p)?.activate() ?? false)
case (let p, "state"):
    if let r = app(p) { print("active=\(r.isActive) hidden=\(r.isHidden)") } else { print("gone") }
default:
    print("usage: appctl <pid> hide|unhide|front|state | front-pid | activate-pid <pid>")
    exit(2)
}
