import Foundation

final class ApkImportPermit: @unchecked Sendable {
    private let lock = NSLock()
    private var occupied = false

    func acquire() -> Bool {
        lock.withLock {
            guard !occupied else { return false }
            occupied = true
            return true
        }
    }

    func release() { lock.withLock { occupied = false } }
}
