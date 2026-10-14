import Foundation
import Combine

public final class DownloadService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = DownloadService()

    @Published public private(set) var jobs: [DownloadJob] = []

    private var session: URLSession!
    private var taskMap: [String: URLSessionDownloadTask] = [:]
    private var resolvingTasks: [String: Task<Void, Never>] = [:]
    private var jobDecryptionKeys: [String: String] = [:]
    private let storageKey = "zgj_tv_download_jobs"
    private let maxConcurrentDownloads = 2
    private var lastProgressUpdateTime: [String: Date] = [:]

    private var downloadsDirectory: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Downloads", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    override public init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        config.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        loadJobs()
        // 自动恢复之前等待或中断的任务
        scheduleNext()
    }

    private func loadJobs() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let list = try? JSONDecoder().decode([DownloadJob].self, from: data) {
            self.jobs = list.map { job in
                var j = job
                if j.state == "downloading" {
                    j.state = "queued"
                }
                if j.error == "tvOS 设备端暂不支持离线下载" || j.error.contains("未能打开文件") {
                    j.state = "queued"
                    j.error = ""
                }
                return j
            }
        }
    }

    private func saveJobs() {
        if let data = try? JSONEncoder().encode(jobs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// 检查指定短剧集是否已有本地离线文件
    public func completedLocalURL(dramaId: String, episodeId: String) -> URL? {
        guard let job = jobs.first(where: {
            $0.drama.id == dramaId &&
            ($0.episode.id == episodeId || "\($0.episode.number)" == episodeId) &&
            $0.isCompleted
        }), let path = job.localPath else {
            return nil
        }
        if FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    public func enqueue(drama: Drama, episodes: [Episode], quality: Int = 1080) {
        var didAdd = false
        for ep in episodes {
            let jobId = "\(drama.id)_\(ep.id)"
            if let index = jobs.firstIndex(where: { $0.id == jobId }) {
                if jobs[index].state == "failed" || jobs[index].state == "paused" {
                    jobs[index].state = "queued"
                    jobs[index].error = ""
                    didAdd = true
                }
                continue
            }

            let job = DownloadJob(
                id: jobId,
                drama: drama,
                episode: ep,
                state: "queued",
                quality: quality,
                actualQuality: quality
            )
            jobs.append(job)
            didAdd = true
        }
        if didAdd {
            saveJobs()
            scheduleNext()
        }
    }

    public func startJob(id: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = "queued"
        jobs[index].error = ""
        saveJobs()
        scheduleNext()
    }

    public func pauseJob(id: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        resolvingTasks[id]?.cancel()
        resolvingTasks.removeValue(forKey: id)
        taskMap[id]?.cancel()
        taskMap.removeValue(forKey: id)
        jobs[index].state = "paused"
        saveJobs()
        scheduleNext()
    }

    public func deleteJob(id: String) {
        pauseJob(id: id)
        if let job = jobs.first(where: { $0.id == id }), let path = job.localPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        jobs.removeAll { $0.id == id }
        saveJobs()
        scheduleNext()
    }

    public func resumeAll() {
        for i in jobs.indices {
            if jobs[i].state == "failed" || jobs[i].state == "paused" {
                jobs[i].state = "queued"
                jobs[i].error = ""
            }
        }
        saveJobs()
        scheduleNext()
    }

    public func clearAll() {
        for job in jobs {
            if let path = job.localPath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        taskMap.values.forEach { $0.cancel() }
        taskMap.removeAll()
        resolvingTasks.values.forEach { $0.cancel() }
        resolvingTasks.removeAll()
        jobs.removeAll()
        saveJobs()
    }

    private func scheduleNext() {
        let activeCount = jobs.filter { $0.state == "downloading" }.count
        guard activeCount < maxConcurrentDownloads else { return }

        guard let nextJob = jobs.first(where: { $0.state == "queued" }) else { return }
        guard let index = jobs.firstIndex(where: { $0.id == nextJob.id }) else { return }

        jobs[index].state = "downloading"
        jobs[index].error = ""
        saveJobs()

        let jobId = nextJob.id
        let drama = nextJob.drama
        let episode = nextJob.episode
        let quality = nextJob.quality

        let task = Task { [weak self] in
            guard let self = self else { return }
            do {
                NSLog("📥 [DownloadService] 开始解析分集播放地址: %@ - %@", drama.title, episode.displayTitle)
                let plan = try await NativeRepository.shared.resolvePlayback(
                    drama: drama,
                    episode: episode,
                    episodeIndex: episode.number,
                    quality: quality
                )

                if Task.isCancelled { return }

                guard let remoteURL = URL(string: plan.url) else {
                    throw NSError(domain: "DownloadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效视频地址: \(plan.url)"])
                }

                await MainActor.run {
                    guard let currentIndex = self.jobs.firstIndex(where: { $0.id == jobId }),
                          self.jobs[currentIndex].state == "downloading" else {
                        return
                    }

                    self.jobDecryptionKeys[jobId] = plan.decryptionKey

                    var request = URLRequest(url: remoteURL)
                    request.timeoutInterval = 60
                    for (k, v) in plan.headers {
                        request.setValue(v, forHTTPHeaderField: k)
                    }

                    let downloadTask = self.session.downloadTask(with: request)
                    downloadTask.taskDescription = jobId
                    self.taskMap[jobId] = downloadTask
                    downloadTask.resume()
                    NSLog("📥 [DownloadService] 启动下载任务: jobId=%@, remoteURL=%@", jobId, remoteURL.absoluteString)
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let currentIndex = self.jobs.firstIndex(where: { $0.id == jobId }) else { return }
                    self.jobs[currentIndex].state = "failed"
                    self.jobs[currentIndex].error = error.localizedDescription
                    self.saveJobs()
                    NSLog("❌ [DownloadService] 任务解析失败: jobId=%@, error=%@", jobId, error.localizedDescription)
                    self.scheduleNext()
                }
            }
        }
        resolvingTasks[jobId] = task
    }

    // MARK: - URLSessionDownloadDelegate
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription,
              let index = jobs.firstIndex(where: { $0.id == id }) else { return }

        let now = Date()
        if let last = lastProgressUpdateTime[id], now.timeIntervalSince(last) < 0.25, totalBytesWritten < totalBytesExpectedToWrite {
            return
        }
        lastProgressUpdateTime[id] = now

        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        jobs[index].bytes = Int(totalBytesWritten)
        jobs[index].total = Int(totalBytesExpectedToWrite)
        jobs[index].progress = min(1.0, max(0.0, progress))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription,
              let index = jobs.firstIndex(where: { $0.id == id }) else { return }

        taskMap.removeValue(forKey: id)
        let hexKey = jobDecryptionKeys.removeValue(forKey: id) ?? ""
        let targetURL = downloadsDirectory.appendingPathComponent("\(id).mp4")

        // 关键：在代理回调返回前，必须立即同步将系统临时文件转移到我们沙盒内部的暂存文件
        let stagingURL = downloadsDirectory.appendingPathComponent("\(id)_staging.tmp")
        try? FileManager.default.removeItem(at: stagingURL)
        do {
            try FileManager.default.moveItem(at: location, to: stagingURL)
        } catch {
            jobs[index].state = "failed"
            jobs[index].error = "暂存下载文件失败: \(error.localizedDescription)"
            saveJobs()
            scheduleNext()
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            defer {
                try? FileManager.default.removeItem(at: stagingURL)
            }
            do {
                NSLog("📥 [DownloadService] 暂存成功，开始落盘与解密: id=%@, hexKey='%@'", id, hexKey)
                try CENCMP4Decryptor.shared.decryptDownloadedFile(at: stagingURL, hexKey: hexKey, destinationURL: targetURL)

                let fileAttrs = try FileManager.default.attributesOfItem(atPath: targetURL.path)
                let fileSize = (fileAttrs[.size] as? Int) ?? 0
                guard fileSize > 1024 else {
                    throw NSError(domain: "DownloadService", code: -2, userInfo: [NSLocalizedDescriptionKey: "下载文件校验失败 (大小仅 \(fileSize) 字节)"])
                }

                await MainActor.run {
                    guard let currIdx = self.jobs.firstIndex(where: { $0.id == id }) else { return }
                    self.jobs[currIdx].localPath = targetURL.path
                    self.jobs[currIdx].bytes = fileSize
                    self.jobs[currIdx].total = fileSize
                    self.jobs[currIdx].progress = 1.0
                    self.jobs[currIdx].state = "completed"
                    self.jobs[currIdx].error = ""
                    self.saveJobs()
                    NSLog("✅ [DownloadService] 离线任务已成功归档: id=%@, path=%@, size=%d 字节", id, targetURL.path, fileSize)
                    self.scheduleNext()
                }
            } catch {
                await MainActor.run {
                    guard let currIdx = self.jobs.firstIndex(where: { $0.id == id }) else { return }
                    self.jobs[currIdx].state = "failed"
                    self.jobs[currIdx].error = "解密/保存失败: \(error.localizedDescription)"
                    self.saveJobs()
                    NSLog("❌ [DownloadService] 离线文件落盘失败: id=%@, error=%@", id, error.localizedDescription)
                    self.scheduleNext()
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        taskMap.removeValue(forKey: id)
        jobDecryptionKeys.removeValue(forKey: id)

        guard let err = error else { return }
        if (err as NSError).code == NSURLErrorCancelled {
            return
        }

        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = "failed"
        jobs[index].error = err.localizedDescription
        saveJobs()
        NSLog("❌ [DownloadService] 下载传输异常: id=%@, error=%@", id, err.localizedDescription)
        scheduleNext()
    }
}
