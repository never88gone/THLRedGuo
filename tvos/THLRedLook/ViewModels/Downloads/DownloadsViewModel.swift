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

    public func pauseJob(_ id: String) {
        downloadService.pauseJob(id: id)
    }

    public func resumeJob(_ id: String) {
        downloadService.startJob(id: id)
    }

    public func deleteJob(_ id: String) {
        downloadService.deleteJob(id: id)
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
