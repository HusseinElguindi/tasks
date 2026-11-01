import Foundation
import TasksCore

/// SplitMix64, with its own range helpers (not the stdlib's `random(in:using:)`), so the stream never depends on
/// the toolchain.
struct Rng {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< n
    mutating func int(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
    mutating func int(in r: ClosedRange<Int>) -> Int { r.lowerBound + int(r.upperBound - r.lowerBound + 1) }
    mutating func chance(_ p: Double) -> Bool { Double(next() >> 11) / 9_007_199_254_740_992.0 < p }
    mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }

    mutating func uuid() -> String {
        func hex(_ v: UInt64, _ n: Int) -> String {
            let s = String(v, radix: 16)
            return String(repeating: "0", count: max(0, n - s.count)) + s.suffix(n)
        }
        let a = next(), b = next()
        return "\(hex(a >> 32, 8))-\(hex((a >> 16) & 0xFFFF, 4))-4\(hex(a & 0xFFF, 3))-\(hex(0x8000 | (b >> 48) & 0x3FFF, 4))-\(hex(b & 0xFFFF_FFFF_FFFF, 12))"
    }

    mutating func hash() -> String {
        (0..<4).map { _ in
            let s = String(next(), radix: 16)
            return String(repeating: "0", count: 16 - s.count) + s
        }.joined()
    }
}

func gregorian(_ zone: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    return c
}

func dayOf(now: Int, zone: String) -> Day {
    Day(containing: Date(timeIntervalSince1970: Double(now) / 1000), calendar: gregorian(zone))
}

/// Epoch ms of a UTC wall time, by integer arithmetic.
func utcMs(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0, _ ms: Int = 0) -> Int {
    let days = CalendarDate(year: y, month: mo, day: d)!.dayNumber
    return ((days * 24 + h) * 60 + mi) * 60_000 + s * 1000 + ms
}

/// Epoch ms of a local wall time at a fixed UTC offset in minutes (east positive).
func localMs(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, offset: Int, s: Int = 0, ms: Int = 0) -> Int {
    utcMs(y, mo, d, h, mi, s, ms) - offset * 60_000
}

func date(_ s: String) -> CalendarDate { CalendarDate(s)! }

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // golden
    .deletingLastPathComponent() // Sources
    .deletingLastPathComponent() // parity
    .deletingLastPathComponent() // remote
    .deletingLastPathComponent()

/// Warnings about Swift behaving unexpectedly (internal consistency checks); printed at the end.
nonisolated(unsafe) var warnings: [String] = []
