import Foundation
import TasksCore

// MARK: - ordering.json

enum OrderingCases {
    static func sorted(_ items: [OrderedItem]) -> [OrderedItem] {
        items.sorted { orderPrecedes($0.order, $0.id, $1.order, $1.id) }
    }

    static func items(_ pairs: [(String, String)]) -> [OrderedItem] {
        sorted(pairs.map { OrderedItem(id: $0.0, order: $0.1) })
    }

    static func anchorJSON(_ a: Ordering.Anchor) -> J {
        switch a {
        case .top: .str("top")
        case .bottom: .str("bottom")
        case .after(let id): .obj(["after": .str(id)])
        case .before(let id): .obj(["before": .str(id)])
        }
    }

    static func row(_ items: [OrderedItem], _ moving: [String], _ anchor: Ordering.Anchor) -> J {
        let r = Ordering.place(moving, at: anchor, in: items)
        func enc(_ x: [OrderedItem]) -> J { .arr(x.map { .obj(["id": .str($0.id), "order": .str($0.order)]) }) }
        return .obj(["items": enc(items), "moving": .ids(moving), "anchor": anchorJSON(anchor), "expect": enc(r)])
    }

    /// Keys that crowd towards `a`, getting about one character longer every six steps.
    static func crowded(from a: String, to b: String, steps: Int) -> [String] {
        var out: [String] = []
        var hi = b
        for _ in 0..<steps {
            guard let k = try? FractionalIndex.keyBetween(a, hi) else { break }
            out.append(k)
            hi = k
        }
        return out
    }

    static func build() -> (J, Int) {
        var cases: [J] = []
        let abc = items([("x", "a0"), ("y", "a1"), ("z", "a2")])
        let anchors: [Ordering.Anchor] = [.top, .bottom, .after("x"), .after("y"), .after("z"), .before("x"),
                                          .before("y"), .before("z"), .after("nope"), .before("nope")]
        // Empty sequences and nothing to move.
        for a in [Ordering.Anchor.top, .bottom, .after("x"), .before("x")] {
            cases.append(row([], ["n"], a))
            cases.append(row([], ["n1", "n2", "n3"], a))
        }
        cases.append(row(abc, [], .top))
        // New items, existing items (lifted out first), anchors on moving items.
        for a in anchors {
            cases.append(row(abc, ["n"], a))
            cases.append(row(abc, ["n1", "n2"], a))
            cases.append(row(abc, ["y"], a))
            cases.append(row(abc, ["z", "x"], a))
            cases.append(row(abc, ["x", "n"], a))
        }
        cases.append(row(abc, ["x", "y", "z"], .after("y")))
        cases.append(row(abc, ["n", "n"], .bottom)) // the same id twice
        // Tied runs: inserting between equal keys re-keys the run first.
        let tied = items([("p", "a0"), ("q", "a1"), ("r", "a1"), ("s", "a1"), ("t", "a2")])
        for a in [Ordering.Anchor.after("q"), .after("r"), .before("s"), .before("r"), .after("s"), .before("q"),
                  .top, .bottom] {
            cases.append(row(tied, ["n"], a))
            cases.append(row(tied, ["r"], a))
        }
        let tiedEnd = items([("p", "a0"), ("q", "a1"), ("r", "a1"), ("s", "a1")])
        cases.append(row(tiedEnd, ["n"], .after("q")))
        cases.append(row(tiedEnd, ["n"], .after("r")))
        let allTied = items([("p", "a0"), ("q", "a0"), ("r", "a0"), ("s", "a0")])
        for a in [Ordering.Anchor.after("p"), .after("q"), .before("s"), .top, .bottom] {
            cases.append(row(allTied, ["n"], a))
            cases.append(row(allTied, ["p"], a))
        }
        // Ties broken by id as UTF-8 bytes.
        let utf = items([("😀", "a0"), ("～", "a0"), ("a", "a0"), ("B", "a1")])
        cases.append(row(utf, ["n"], .after(utf[0].id)))
        cases.append(row(utf, ["n"], .after(utf[1].id)))
        // Invalid neighbour keys fall back to a rebalance.
        for bad in ["a10", "", "zz", "a 0", "A00000000000000000000000000", "😀", "a0\u{301}"] {
            let it = items([("p", "a0"), ("q", bad), ("r", "b0")])
            cases.append(row(it, ["n"], .after("q")))
            cases.append(row(it, ["n"], .before("q")))
            cases.append(row(it, ["n"], .bottom))
        }
        // Keys near the 32-character limit: a key over it rebalances the whole sequence.
        let near = crowded(from: "a0", to: "a1", steps: 200)
        for len in [30, 31, 32, 33] {
            guard let i = near.firstIndex(where: { $0.utf8.count == len }), i + 1 < near.count else { continue }
            let lo = near[i + 1], hi = near[i]
            let it = items([("p", "a0"), ("q", lo), ("r", hi), ("s", "a1")])
            cases.append(row(it, ["n"], .after("q")))
            cases.append(row(it, ["n1", "n2", "n3"], .after("q")))
            cases.append(row(it, ["n"], .before("q")))
            cases.append(row(it, ["s"], .after("q")))
            // A tied run whose re-keying would itself be too long.
            let tiedLong = items([("p", "a0"), ("q", lo), ("q2", lo), ("q3", lo), ("r", hi)])
            cases.append(row(tiedLong, ["n"], .after("q")))
        }

        // Random sequences built the way the app builds them, with ties and long keys mixed in.
        var rng = Rng(7)
        while cases.count < 260 {
            var pairs: [(String, String)] = []
            let n = rng.pick([0, 1, 2, 3, 5, 8, 13, 30])
            var key: String? = nil
            for k in 0..<n {
                switch rng.int(10) {
                case 0: break // a tie with the previous key
                case 1: key = near[rng.int(near.count)]
                default: key = (try? FractionalIndex.keyBetween(key.flatMap { FractionalIndex.isValidKey($0) ? $0 : nil }, nil)) ?? "a0"
                }
                pairs.append(("i\(k)", key ?? "a0"))
            }
            let it = items(pairs)
            var moving: [String] = []
            for _ in 0..<rng.int(in: 1...4) {
                if !it.isEmpty, rng.chance(0.5) {
                    let id = it[rng.int(it.count)].id
                    if !moving.contains(id) { moving.append(id) }
                } else {
                    moving.append("m\(moving.count)")
                }
            }
            let anchor: Ordering.Anchor
            switch rng.int(6) {
            case 0: anchor = .top
            case 1: anchor = .bottom
            case 2, 3: anchor = .after(it.isEmpty || rng.chance(0.1) ? "nope" : it[rng.int(it.count)].id)
            default: anchor = .before(it.isEmpty || rng.chance(0.1) ? "nope" : it[rng.int(it.count)].id)
            }
            cases.append(row(it, moving, anchor))
        }
        return (.obj(["cases": .arr(cases)]), cases.count)
    }
}
