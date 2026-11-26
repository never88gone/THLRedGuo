import Foundation

public struct DramaDownloadGroup: Identifiable, Hashable {
    public var id: String { drama.id }
    public let drama: Drama
    public var jobs: [DownloadJob]

    public init(drama: Drama, jobs: [DownloadJob]) {
        self.drama = drama
        self.jobs = jobs.sorted { $0.episode.number < $1.episode.number }
    }

    public var completedJobs: [DownloadJob] {
        jobs.filter(\.isCompleted)
    }

    public var completedCount: Int {
        completedJobs.count
    }

    public var totalCount: Int {
        jobs.count
    }

    public var totalBytes: Int {
        jobs.reduce(0) { $0 + $1.bytes }
    }

    public var isAllCompleted: Bool {
        !jobs.isEmpty && jobs.allSatisfy(\.isCompleted)
    }

    public var hasActive: Bool {
        jobs.contains(where: { $0.isActive })
    }

    public var hasResumable: Bool {
        jobs.contains(where: { $0.isResumable })
    }

    public var latestCreated: Int64 {
        jobs.map(\.created).max() ?? 0
    }

    public var statusSummary: String {
        let mb = Double(totalBytes) / (1024 * 1024)
        let sizePart = totalBytes > 0 ? String(format: " · %.1f MB", mb) : ""
        if isAllCompleted {
            return "全部 \(totalCount) 集已下载\(sizePart)"
        } else {
            return "已下载 \(completedCount)/\(totalCount) 集\(sizePart)"
        }
    }
}
