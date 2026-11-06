import Foundation

/// The app's URL scheme (WIDGETS.md §2.2): how a widget opens the app at a place. The widgets build these links; the
/// app reads them (`AppModel.follow(_:)`).
///
///     tasks://today            Today
///     tasks://upcoming         Upcoming
///     tasks://list/<id>        a list
///     tasks://task/<id>        a task: its list, then its details
///     tasks://new              a new task in Today
///     tasks://new?list=<id>    a new task in a list
enum DeepLink: Hashable, Sendable {
    case today
    case upcoming
    case list(String)
    case task(String)
    /// A new task: in a list, or in Today when nil.
    case new(list: String?)

    static let scheme = "tasks"

    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case .today: c.host = "today"
        case .upcoming: c.host = "upcoming"
        case let .list(id): c.host = "list"; c.path = "/" + id
        case let .task(id): c.host = "task"; c.path = "/" + id
        case let .new(list):
            c.host = "new"
            if let list { c.queryItems = [URLQueryItem(name: "list", value: list)] }
        }
        return c.url!
    }

    /// The link a URL names, or nil for one this app doesn't know (another scheme, a missing id).
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let id = c.path.split(separator: "/").first.map(String.init)
        switch c.host?.lowercased() {
        case "today": self = .today
        case "upcoming": self = .upcoming
        case "list":
            guard let id, !id.isEmpty else { return nil }
            self = .list(id)
        case "task":
            guard let id, !id.isEmpty else { return nil }
            self = .task(id)
        case "new":
            let list = c.queryItems?.first { $0.name == "list" }?.value
            self = .new(list: list?.isEmpty == false ? list : nil)
        default: return nil
        }
    }
}
