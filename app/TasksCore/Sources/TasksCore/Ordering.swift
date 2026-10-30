/// An item in a manually ordered sequence: a task in its list, or a list in the sidebar.
public struct OrderedItem: Hashable, Sendable {
    public var id: EntityID
    public var order: String

    public init(id: EntityID, order: String) {
        self.id = id
        self.order = order
    }
}

/// Sort by `order` byte-wise, ties broken by `id` (spec §3). Every Mac computes the same order.
@inline(__always)
public func orderPrecedes(_ aOrder: String, _ aID: String, _ bOrder: String, _ bID: String) -> Bool {
    if aOrder == bOrder { return aID.utf8.lexicographicallyPrecedes(bID.utf8) }
    return aOrder.utf8.lexicographicallyPrecedes(bOrder.utf8)
}

/// Keys for drags, moves and appends (spec §3): ties, re-keying tied runs and rebalancing.
/// Pure: it returns the new keys, and the caller turns them into ops.
public enum Ordering {
    /// A key longer than this triggers a rebalance of the whole sequence.
    public static let maxKeyLength = 32

    public enum Anchor: Hashable, Sendable {
        case top, bottom
        /// Right after this item: `keyBetween(item, item's successor)`.
        case after(EntityID)
        /// Right before this item: `keyBetween(item's predecessor, item)`.
        case before(EntityID)
    }

    /// New keys that place `moving` (in this order) at `anchor` in `items`.
    ///
    /// `items` is the destination sequence sorted by (order, id); moving items already in it are lifted out first.
    /// Usually only the moving items get keys. Inserting between two equal keys first re-keys the tied run, and a
    /// key over `maxKeyLength` re-keys the whole sequence; those extra items are included in the result.
    public static func place(_ moving: [EntityID], at anchor: Anchor, in items: [OrderedItem]) -> [OrderedItem] {
        guard !moving.isEmpty else { return [] }
        let movingSet = Set(moving)
        var rest = items.filter { !movingSet.contains($0.id) }
        let p: Int = switch anchor {
        case .top: 0
        case .bottom: rest.count
        case .after(let id): rest.firstIndex { $0.id == id }.map { $0 + 1 } ?? rest.count
        case .before(let id): rest.firstIndex { $0.id == id } ?? rest.count
        }

        var rekeyed: [OrderedItem] = []
        // Inserting between equal keys: give the tied run distinct keys first (rare).
        if p > 0, p < rest.count, rest[p - 1].order == rest[p].order {
            let tied = rest[p].order
            var s = p - 1
            while s > 0, rest[s - 1].order == tied { s -= 1 }
            var e = p + 1
            while e < rest.count, rest[e].order == tied { e += 1 }
            let above = e < rest.count ? rest[e].order : nil
            if let keys = try? FractionalIndex.keysBetween(tied, above, count: e - s - 1),
               keys.allSatisfy({ $0.utf8.count <= maxKeyLength }) {
                for (offset, key) in keys.enumerated() {
                    rest[s + 1 + offset].order = key
                    rekeyed.append(rest[s + 1 + offset])
                }
            } else {
                return rebalance(moving, at: p, in: rest)
            }
        }

        let prev = p > 0 ? rest[p - 1].order : nil
        let next = p < rest.count ? rest[p].order : nil
        guard let keys = try? FractionalIndex.keysBetween(prev, next, count: moving.count),
              keys.allSatisfy({ $0.utf8.count <= maxKeyLength }) else {
            return rebalance(moving, at: p, in: rest)
        }
        return rekeyed + zip(moving, keys).map { OrderedItem(id: $0, order: $1) }
    }

    /// Keys for appending `count` items after `last` (new tasks and lists go to the bottom).
    public static func append(_ moving: [EntityID], after items: [OrderedItem]) -> [OrderedItem] {
        place(moving, at: .bottom, in: items)
    }

    /// Fresh, short, evenly spaced keys for the whole sequence, in its new order (spec §3 "Rebalance").
    static func rebalance(_ moving: [EntityID], at p: Int, in rest: [OrderedItem]) -> [OrderedItem] {
        var ids = rest.map(\.id)
        ids.insert(contentsOf: moving, at: p)
        let keys = (try? FractionalIndex.keysBetween(nil, nil, count: ids.count)) ?? []
        let old = Dictionary(rest.map { ($0.id, $0.order) }, uniquingKeysWith: { a, _ in a })
        let movingSet = Set(moving)
        return zip(ids, keys).compactMap { id, key in
            movingSet.contains(id) || old[id] != key ? OrderedItem(id: id, order: key) : nil
        }
    }
}
