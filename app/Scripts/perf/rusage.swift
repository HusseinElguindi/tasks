// Samples a process's resource use with proc_pid_rusage, which needs no root for the user's own processes and never
// attaches to them (coord title-design T8). Safe to point at the installed Tasks.app: it only reads the kernel's
// counters.
//
//   swiftc -O app/Scripts/perf/rusage.swift -o rusage
//   rusage <pid> <seconds per sample> <samples> [label]
//
// One line per sample, as tab-separated deltas over the interval, then a TOTAL line over the whole run:
//   cpu%  (user + system time / wall time), idle wakeups/s (package idle exits), interrupt wakeups/s,
//   disk bytes written (physical, to the device), logical bytes written (what the process asked to write, before the
//   cache), disk bytes read, energy mW (the kernel's billed energy), and the footprint (phys_footprint) at the end.
import Darwin
import Foundation

let args = CommandLine.arguments
guard args.count >= 4, let pid = Int32(args[1]), let interval = Double(args[2]), let count = Int(args[3]) else {
    FileHandle.standardError.write("usage: rusage <pid> <seconds> <samples> [label]\n".data(using: .utf8)!)
    exit(2)
}
let label = args.count > 4 ? args[4] : ""

var tb = mach_timebase_info_data_t()
mach_timebase_info(&tb)
func ns(_ ticks: UInt64) -> Double { Double(ticks) * Double(tb.numer) / Double(tb.denom) }

func sample() -> rusage_info_v6? {
    var info = rusage_info_v6()
    let r = withUnsafeMutablePointer(to: &info) { p in
        p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
    }
    return r == 0 ? info : nil
}

struct Row {
    var cpu = 0.0, idleW = 0.0, intW = 0.0, diskW = 0.0, logW = 0.0, diskR = 0.0, mW = 0.0, fp = 0.0
}

func delta(_ a: rusage_info_v6, _ b: rusage_info_v6, _ wall: Double) -> Row {
    var r = Row()
    let cpuNs = ns(b.ri_user_time - a.ri_user_time) + ns(b.ri_system_time - a.ri_system_time)
    r.cpu = cpuNs / (wall * 1e9) * 100
    r.idleW = Double(b.ri_pkg_idle_wkups - a.ri_pkg_idle_wkups) / wall
    r.intW = Double(b.ri_interrupt_wkups - a.ri_interrupt_wkups) / wall
    r.diskW = Double(b.ri_diskio_byteswritten - a.ri_diskio_byteswritten)
    r.logW = Double(b.ri_logical_writes - a.ri_logical_writes)
    r.diskR = Double(b.ri_diskio_bytesread - a.ri_diskio_bytesread)
    r.mW = Double(b.ri_billed_energy - a.ri_billed_energy) / 1e6 / wall // nJ → mW
    r.fp = Double(b.ri_phys_footprint) / 1_048_576
    return r
}

func line(_ tag: String, _ r: Row) -> String {
    String(format: "%@\t%@\tcpu %.3f%%\tidleW/s %.2f\tintW/s %.2f\tdiskW %.0f B\tlogW %.0f B\tdiskR %.0f B\t%.2f mW\tfp %.1f MB",
           label, tag, r.cpu, r.idleW, r.intW, r.diskW, r.logW, r.diskR, r.mW, r.fp)
}

guard let first = sample() else { print("no such process or no access: \(pid)"); exit(1) }
var prev = first
let start = Date()
var last = start
for i in 0..<count {
    Thread.sleep(forTimeInterval: interval)
    guard let s = sample() else { print("process \(pid) ended"); break }
    let now = Date()
    print(line(String(i + 1), delta(prev, s, now.timeIntervalSince(last))))
    fflush(stdout)
    prev = s
    last = now
}
print(line("TOTAL", delta(first, prev, last.timeIntervalSince(start))))
print(String(format: "%@\tLIFETIME\tcpu-seconds %.2f\tdiskW %.0f B\tlogW %.0f B\tidle wakeups %llu", label,
             (ns(prev.ri_user_time) + ns(prev.ri_system_time)) / 1e9, Double(prev.ri_diskio_byteswritten),
             Double(prev.ri_logical_writes), prev.ri_pkg_idle_wkups))
