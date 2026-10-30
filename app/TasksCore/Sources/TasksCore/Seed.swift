/// Inbox seeding (spec §2). The fixed pair of ids lives here and nowhere else: the reducer, queries and UI
/// treat the Inbox as an ordinary list.
public enum Seed {
    static let inboxListID = "00000000-0000-0000-0000-000000000001"
    static let inboxOpID = "00000000-0000-0000-0000-000000000002"

    /// The one op that seeds the Inbox, or nil if a list with the Inbox id already exists in confirmed + pending.
    /// Every Mac sends the identical op id, so the server stores it once, and a second create would lose anyway.
    public static func inboxIfMissing(listExists: (EntityID) -> Bool, now: Int) -> Op? {
        guard !listExists(inboxListID) else { return nil }
        return Op(id: inboxOpID, at: now, type: .listCreate, target: inboxListID,
                  set: Patch(order: "a0", name: "Inbox"))
    }
}
