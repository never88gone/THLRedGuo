import Foundation

final class HttpTraceHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _url = ""
    private var _method = "GET"
    private var _status = 0
    private var _logId = ""
    private var _snippet = ""
    private var _tabsSummary = ""
    private var _guestCreatedAt: TimeInterval = 0
    private var _guestJSON = ""

    func record(url: String, method: String, status: Int, logId: String, snippet: String, tabsSummary: String) {
        lock.lock()
        defer { lock.unlock() }
        _url = url
        _method = method
        _status = status
        _logId = logId
        _snippet = snippet
        _tabsSummary = tabsSummary
    }

    func recordGuest(json: String, createdAt: TimeInterval) {
        lock.withLock {
            _guestJSON = json
            _guestCreatedAt = createdAt
        }
    }

    var guestSnapshot: (json: String, createdAt: TimeInterval) {
        lock.withLock { (_guestJSON, _guestCreatedAt) }
    }

    var snapshot: (url: String, method: String, status: Int, logId: String, snippet: String, tabsSummary: String) {
        lock.lock()
        defer { lock.unlock() }
        return (_url, _method, _status, _logId, _snippet, _tabsSummary)
    }
}
