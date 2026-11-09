import Foundation

enum PlaybackRetryPolicy {
    static func delay(code: String, attempt: Int) -> UInt64? {
        if code.hasPrefix("LOCAL_PROFILE_") { return nil }
        let delays: [UInt64] = ["EMPTY_RESPONSE", "RESPONSE_NOT_UTF8"].contains(code)
            ? [1_000_000_000, 3_000_000_000]
            : [500_000_000, 1_000_000_000, 2_000_000_000, 4_000_000_000, 6_000_000_000]
        guard attempt > 0, attempt <= delays.count else { return nil }
        return delays[attempt - 1]
    }
}
