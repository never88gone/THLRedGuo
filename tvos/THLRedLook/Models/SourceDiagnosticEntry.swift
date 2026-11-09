import Foundation

public struct SourceDiagnosticEntry: Identifiable {
    public let id = UUID()
    public let at = Date()
    public let context: String
    public let stage: String
    public var host = ""
    public var url = ""
    public var method = "GET"
    public var logId = ""
    public var status = 0
    public var businessCode = ""
    public var errorCode = ""
    public var elapsedMs = 0
    public var count: Int?
    public var category: DiagnosticCategory = .unknown
    public var errorDetail: String = ""
    public var suggestion: String = ""
    public var responseSnippet: String = ""
    public var searchTabsSummary: String = ""
    public var sessionStatus: String = ""
    public var bodyBytes: Int?
    public var contentType = ""
    public var contentEncoding = ""
    public var declaredBodyBytes: Int?

    public var failed: Bool {
        !errorCode.isEmpty || category != .unknown && category != .invalidResponse
    }

    public var text: String {
        var parts = [ISO8601DateFormatter().string(from: at), "[\(context)] \(stage)"]
        if category != .unknown { parts.append("【\(category.tag)】") }
        if !host.isEmpty { parts.append(host) }
        if status > 0 { parts.append("HTTP \(status)") }
        if !businessCode.isEmpty { parts.append("业务码 \(businessCode)") }
        if !logId.isEmpty { parts.append("LogID: \(logId)") }
        if !searchTabsSummary.isEmpty { parts.append(searchTabsSummary) }
        if !errorCode.isEmpty && errorCode != category.tag { parts.append(errorCode) }
        if elapsedMs > 0 { parts.append("\(elapsedMs)ms") }
        if let count { parts.append("\(count) 条结果") }
        if !errorDetail.isEmpty { parts.append("原因: \(errorDetail)") }
        return parts.joined(separator: " · ")
    }

    public init(
        context: String,
        stage: String,
        host: String = "",
        url: String = "",
        method: String = "GET",
        logId: String = "",
        status: Int = 0,
        businessCode: String = "",
        errorCode: String = "",
        elapsedMs: Int = 0,
        count: Int? = nil,
        category: DiagnosticCategory = .unknown,
        errorDetail: String = "",
        suggestion: String = "",
        responseSnippet: String = "",
        searchTabsSummary: String = "",
        sessionStatus: String = "",
        bodyBytes: Int? = nil,
        contentType: String = "",
        contentEncoding: String = "",
        declaredBodyBytes: Int? = nil
    ) {
        self.context = context
        self.stage = stage
        self.host = host
        self.url = url
        self.method = method
        self.logId = logId
        self.status = status
        self.businessCode = businessCode
        self.errorCode = errorCode
        self.elapsedMs = elapsedMs
        self.count = count
        self.category = category
        self.errorDetail = errorDetail
        self.suggestion = suggestion
        self.responseSnippet = responseSnippet
        self.searchTabsSummary = searchTabsSummary
        self.sessionStatus = sessionStatus
        self.bodyBytes = bodyBytes
        self.contentType = contentType
        self.contentEncoding = contentEncoding
        self.declaredBodyBytes = declaredBodyBytes
    }
}
