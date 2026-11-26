import Foundation
import Combine

@MainActor
public final class DownloadsViewModel: ObservableObject {
    private let downloadService: DownloadService
    private var cancellables = Set<AnyCancellable>()

    public init(downloadService: DownloadService = .shared) {
        self.downloadService = downloadService
        downloadService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var currentSource: String {
        let src = !JSSourceService.shared.activeSourceId.isEmpty ? JSSourceService.shared.activeSourceId : LocalStore.shared.currentSourceId
        return src.isEmpty ? "hongguo" : src
    }

    public var jobs: [DownloadJob] {
        let target = currentSource.lowercased()
        return downloadService.jobs.filter {
            $0.drama.source.isEmpty || $0.drama.source.lowercased() == target
        }
    }

    public var dramaGroups: [DramaDownloadGroup] {
        let currentJobs = jobs
        var grouped: [String: (drama: Drama, jobs: [DownloadJob], latestCreated: Int64)] = [:]
        for job in currentJobs {
            if let existing = grouped[job.drama.id] {
                grouped[job.drama.id] = (
                    drama: existing.drama,
                    jobs: existing.jobs + [job],
                    latestCreated: max(existing.latestCreated, job.created)
                )
            } else {
                grouped[job.drama.id] = (
                    drama: job.drama,
                    jobs: [job],
                    latestCreated: job.created
                )
            }
        }
        return grouped.values
            .sorted { $0.latestCreated > $1.latestCreated }
            .map { DramaDownloadGroup(drama: $0.drama, jobs: $0.jobs) }
    }

    public func pauseJob(_ id: String) {
        downloadService.pauseJob(id: id)
    }

    public func resumeJob(_ id: String) {
        downloadService.startJob(id: id)
    }

    public func deleteJob(_ id: String) {
        downloadService.deleteJob(id: id)
    }

    public func pauseDrama(_ dramaId: String) {
        let targets = jobs.filter { $0.drama.id == dramaId && $0.isActive }
        for job in targets {
            downloadService.pauseJob(id: job.id)
        }
    }

    public func resumeDrama(_ dramaId: String) {
        let targets = jobs.filter { $0.drama.id == dramaId && $0.isResumable }
        for job in targets {
            downloadService.startJob(id: job.id)
        }
    }

    public func deleteDrama(_ dramaId: String) {
        let targets = jobs.filter { $0.drama.id == dramaId }
        for job in targets {
            downloadService.deleteJob(id: job.id)
        }
    }

    public func resumeAll() {
        downloadService.resumeAll()
    }

    public func clearAll() {
        let currentJobs = jobs
        for job in currentJobs {
            downloadService.deleteJob(id: job.id)
        }
    }
}
