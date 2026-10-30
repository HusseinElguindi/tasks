import Foundation
@testable import TasksCore

/// Deterministic RNG for randomized tests (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Fixtures {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // TasksCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // TasksCore
        .deletingLastPathComponent() // app
        .deletingLastPathComponent()

    static var syncDirectory: URL { repoRoot.appendingPathComponent("fixtures/sync") }
}

/// The spec's test-vector ops (§5 worked examples).
enum Spec {
    static let opAJSON = #"{"id":"00000000-0000-0000-0000-000000000002","at":1761811200000,"type":"list.create","target":"00000000-0000-0000-0000-000000000001","set":{"name":"Inbox","order":"a0"}}"#
    static let opBJSON = #"{"id":"5b0c6c1e-3f0a-4c8e-9d61-0f4f6f1a2b3c","at":1761811260000,"type":"task.create","target":"9f8e7d6c-5b4a-4321-8fed-cba987654321","set":{"list":"00000000-0000-0000-0000-000000000001","order":"a0","title":"Buy milk","when":"2026-10-30"}}"#
    static let hash0 = "bc2a6e3a4de77a2ce16c4a38c6f4d76237a98434f7d213049e3fd77dde66dacd"
    static let hash1 = "184ceb4c3d11bd53025385963c25f50298c2d652f84d5989941d2ec13a66fd79"
    static let inbox = "00000000-0000-0000-0000-000000000001"
}

func op(_ json: String) -> Op {
    try! JSONDecoder().decode(Op.self, from: Data(json.utf8))
}

/// Builders for ops in tests.
struct OpMaker {
    var counter = 0
    var at = 1_761_811_200_000

    mutating func next() -> (String, Int) {
        counter += 1
        at += 1000
        return (String(format: "op-%06d", counter), at)
    }

    mutating func createTask(_ id: String, list: String, order: String, title: String = "", when: CalendarDate? = nil,
                             deadline: CalendarDate? = nil) -> Op {
        let (opID, at) = next()
        return Op(id: opID, at: at, type: .taskCreate, target: id,
                  set: Patch(list: list, order: order, title: title,
                             when: when.map { .some($0) }, deadline: deadline.map { .some($0) }))
    }

    mutating func updateTask(_ id: String, _ patch: Patch) -> Op {
        let (opID, at) = next()
        return Op(id: opID, at: at, type: .taskUpdate, target: id, set: patch)
    }

    mutating func createList(_ id: String, name: String, order: String) -> Op {
        let (opID, at) = next()
        return Op(id: opID, at: at, type: .listCreate, target: id, set: Patch(order: order, name: name))
    }

    mutating func updateList(_ id: String, _ patch: Patch) -> Op {
        let (opID, at) = next()
        return Op(id: opID, at: at, type: .listUpdate, target: id, set: patch)
    }
}

func date(_ s: String) -> CalendarDate { CalendarDate(s)! }

extension TaskItem {
    /// Equal in everything a user can see (updatedAt is informational and moves with every op).
    func sameContent(as other: TaskItem) -> Bool {
        var a = self, b = other
        a.updatedAt = 0
        b.updatedAt = 0
        return a == b
    }
}

extension TaskList {
    func sameContent(as other: TaskList) -> Bool {
        var a = self, b = other
        a.updatedAt = 0
        b.updatedAt = 0
        return a == b
    }
}

/// A flag an Observation `onChange` closure can set.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func set() { lock.withLock { _value = true } }
}
