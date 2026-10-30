import Foundation

/// Where to sync: the Worker's base URL and the bearer token (spec §7).
public struct SyncConfig: Hashable, Sendable {
    public var url: URL
    public var token: String

    public init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    /// `POST {url}/v1/sync`.
    public var endpoint: URL { url.appendingPathComponent("v1").appendingPathComponent("sync") }
}

/// One `/v1/sync` response, classified by the error table (spec §5).
public enum SyncOutcome: Sendable {
    case page(SyncPage)
    /// 400 `invalid_op`: `ops[index]` failed validation at `field`.
    case invalidOp(ErrorBody)
    /// 400 `bad_request`: a client bug. Stop, no retry.
    case badRequest(String)
    /// 401: stop until the token changes or ⌘R.
    case badToken
    /// 404 / 405: a misconfigured server URL. Stop, no retry.
    case misconfigured(String)
    /// 409: the logs diverged. Recover (re-push everything) and retry from 0.
    case logMismatch
    /// 413: halve the batch and retry.
    case tooLarge
    /// 5xx, timeouts, network errors, non-JSON bodies: retry with backoff.
    case transient(String)
}

public protocol SyncTransport: Sendable {
    func send(_ body: Data, config: SyncConfig) async -> SyncOutcome
}

/// The real transport: URLSession, with the response decoded off the main actor.
public final class HTTPSyncTransport: SyncTransport {
    let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let c = URLSessionConfiguration.ephemeral
            c.requestCachePolicy = .reloadIgnoringLocalCacheData
            c.timeoutIntervalForRequest = 30
            c.waitsForConnectivity = false
            self.session = URLSession(configuration: c)
        }
    }

    public func send(_ body: Data, config: SyncConfig) async -> SyncOutcome {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .transient("No HTTP response") }
            return Self.classify(status: http.statusCode, body: data)
        } catch {
            return .transient(error.localizedDescription)
        }
    }

    /// The error table (spec §5). Anything that isn't one of its JSON bodies is treated as server or network
    /// trouble and retried with backoff (a Cloudflare edge error may be an HTML page).
    public static func classify(status: Int, body: Data) -> SyncOutcome {
        if status == 200 {
            guard let page = try? SyncPage.decode(body) else { return .transient("Unreadable 200 response") }
            return .page(page)
        }
        guard let error = try? JSONDecoder().decode(ErrorBody.self, from: body) else {
            return .transient("HTTP \(status)")
        }
        switch (status, error.error) {
        case (400, "invalid_op") where error.index != nil: return .invalidOp(error)
        case (400, _): return .badRequest(error.message ?? error.error)
        case (401, _): return .badToken
        case (404, _), (405, _): return .misconfigured(error.message ?? "HTTP \(status)")
        case (409, _): return .logMismatch
        case (413, _): return .tooLarge
        default: return .transient(error.message ?? "HTTP \(status)")
        }
    }
}
