import Foundation

final class NativeHTTPResult: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 0
    private var headers: [String: String] = [:]
    private var body = ""
    private var bodyBytes = 0
    private var error = ""
    private var rawError: Error?
    private var category: DiagnosticCategory = .unknown
    private var errorDetail: String = ""

    func complete(data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        self.rawError = error
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let response = response as? HTTPURLResponse {
            for (key, value) in response.allHeaderFields {
                headers[String(describing: key).lowercased()] = String(describing: value)
            }
        }
        bodyBytes = data?.count ?? 0
        if let data { body = String(data: data, encoding: .utf8) ?? "" }
        self.error = SourceDiagnostics.networkCode(error)
        if error == nil, status == 200, bodyBytes > 0, body.isEmpty {
            self.error = "RESPONSE_NOT_UTF8"
            category = .invalidResponse
            errorDetail = "收到 \(bodyBytes) 字节正文，但无法按 UTF-8 解码"
            return
        }
        let classified = SourceDiagnostics.classify(error: error, httpStatus: status, body: body)
        self.category = classified.category
        self.errorDetail = classified.reason
    }

    func snapshot(timedOut: Bool) -> (status: Int, headers: [String: String], body: String, bodyBytes: Int, error: String, errorDetail: String, category: DiagnosticCategory, rawError: Error?) {
        lock.lock()
        defer { lock.unlock() }
        if timedOut {
            return (0, [:], "", 0, "TIMEOUT:-1001", "网络请求超时 (12s)", .networkTimeout, NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        }
        return (status, headers, body, bodyBytes, error, errorDetail, category, rawError)
    }
}
