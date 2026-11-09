import Foundation

final class DownloadJobStore {
    static let shared = DownloadJobStore()
    static let legacyKey = "zgj_tv_download_jobs"

    private let defaults: UserDefaults
    private let fileURL: URL
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, fileURL: URL? = nil) {
        self.defaults = defaults
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = fileURL ?? base.appendingPathComponent("DownloadMetadata/jobs.json")
    }

    func migrateLegacyJobs() throws {
        try lock.withLock { try migrateLocked() }
    }

    func load() throws -> [DownloadJob] {
        try lock.withLock {
            try migrateLocked()
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            return try JSONDecoder().decode([DownloadJob].self, from: Data(contentsOf: fileURL))
        }
    }

    func save(_ jobs: [DownloadJob]) throws {
        try lock.withLock {
            try migrateLocked()
            try write(JSONEncoder().encode(jobs))
        }
    }

    private func migrateLocked() throws {
        guard let data = defaults.data(forKey: Self.legacyKey) else { return }
        _ = try JSONDecoder().decode([DownloadJob].self, from: data)
        try write(data)
        guard try Data(contentsOf: fileURL) == data else {
            throw CocoaError(.fileWriteUnknown)
        }
        defaults.removeObject(forKey: Self.legacyKey)
    }

    private func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
