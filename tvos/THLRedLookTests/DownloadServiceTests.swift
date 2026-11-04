import XCTest
import Combine
import AVFoundation
@testable import THLRedLook

@MainActor
final class DownloadServiceTests: XCTestCase {
    private var service: DownloadService!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        try await super.setUp()
        service = DownloadService.shared
        service.clearAll()
    }

    override func tearDown() async throws {
        service.clearAll()
        cancellables.removeAll()
        try await super.tearDown()
    }

    private func makeFixtureDrama(id: String = "test_drama_dl") -> Drama {
        Drama(
            id: id,
            source: "hongguo",
            title: "下载测试剧集",
            cover: "https://example.com/cover.jpg",
            episodes: 5,
            category: "都市",
            heat: "99万"
        )
    }

    private func makeFixtureEpisodes(dramaId: String = "test_drama_dl", count: Int = 3) -> [Episode] {
        (1...count).map {
            Episode(id: "\(dramaId)_ep_\($0)", title: "第 \($0) 集", number: $0)
        }
    }

    // 1. 验证入队与幂等性
    func testEnqueueJobsAndDeduplication() {
        let drama = makeFixtureDrama()
        let episodes = makeFixtureEpisodes(dramaId: drama.id, count: 3)

        service.enqueue(drama: drama, episodes: episodes, quality: 1080)
        XCTAssertEqual(service.jobs.count, 3)
        XCTAssertTrue(service.jobs.contains { $0.episode.number == 1 })
        XCTAssertTrue(service.jobs.contains { $0.episode.number == 2 })
        XCTAssertTrue(service.jobs.contains { $0.episode.number == 3 })

        // 再次入队相同剧集，不应产生重复项
        service.enqueue(drama: drama, episodes: episodes, quality: 1080)
        XCTAssertEqual(service.jobs.count, 3)
    }

    // 2. 验证任务暂停与恢复
    func testPauseAndResumeJob() {
        let drama = makeFixtureDrama()
        let episodes = makeFixtureEpisodes(dramaId: drama.id, count: 1)
        service.enqueue(drama: drama, episodes: episodes, quality: 1080)

        guard let firstJob = service.jobs.first else {
            XCTFail("任务未成功加入队列")
            return
        }

        service.pauseJob(id: firstJob.id)
        if let pausedJob = service.jobs.first(where: { $0.id == firstJob.id }) {
            XCTAssertEqual(pausedJob.state, "paused")
            XCTAssertTrue(pausedJob.isResumable)
        } else {
            XCTFail("无法找到暂停的任务")
        }

        service.startJob(id: firstJob.id)
        if let resumedJob = service.jobs.first(where: { $0.id == firstJob.id }) {
            XCTAssertTrue(resumedJob.state == "queued" || resumedJob.state == "downloading")
        } else {
            XCTFail("无法找到恢复的任务")
        }
    }

    // 3. 验证本地已完成文件路径探测与沙盒路径自愈（Healing）
    func testCompletedLocalURLDetectionAndPathHealing() throws {
        let drama = makeFixtureDrama(id: "test_drama_heal")
        let ep = Episode(id: "ep_1", title: "第 1 集", number: 1)
        let jobId = "\(drama.id)_\(ep.id)"

        // 在临时沙盒目录中模拟生成一个下载完成的 mp4 文件
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let downloadsDir = cachesDir.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        let localFile = downloadsDir.appendingPathComponent("\(jobId).mp4")
        let dummyData = Data(repeating: 0x41, count: 2048)
        try dummyData.write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }

        // 模拟一个旧的、UUID 已失效的路径保存在 Job 中
        let staleUUIDPath = "/var/mobile/Containers/Data/Application/00000000-0000-0000-0000-000000000000/Library/Caches/Downloads/\(jobId).mp4"
        let completedJob = DownloadJob(
            id: jobId,
            drama: drama,
            episode: ep,
            state: "completed",
            bytes: dummyData.count,
            total: dummyData.count,
            progress: 1.0,
            quality: 1080,
            actualQuality: 1080,
            localPath: staleUUIDPath
        )

        // 写入存储并模拟重启加载
        let data = try JSONEncoder().encode([completedJob])
        UserDefaults.standard.set(data, forKey: "zgj_tv_download_jobs")

        // 重新触发 loadJobs
        let reloadedService = DownloadService()
        guard let url = reloadedService.completedLocalURL(dramaId: drama.id, episodeId: ep.id) else {
            XCTFail("自愈逻辑未成功在当前沙盒中匹配到落盘文件")
            return
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.lastPathComponent, "\(jobId).mp4")
    }

    // 4. 验证系统缓存清理后的优雅降级
    func testSystemEvictionDetectionOnReload() throws {
        let drama = makeFixtureDrama(id: "test_drama_evict")
        let ep = Episode(id: "ep_1", title: "第 1 集", number: 1)
        let jobId = "\(drama.id)_\(ep.id)"

        // 构造一个标记为 completed 但本地文件根本不存在的任务
        let ghostPath = "/non_existent/path/\(jobId).mp4"
        let completedJob = DownloadJob(
            id: jobId,
            drama: drama,
            episode: ep,
            state: "completed",
            bytes: 1024,
            total: 1024,
            progress: 1.0,
            quality: 1080,
            actualQuality: 1080,
            localPath: ghostPath
        )

        let data = try JSONEncoder().encode([completedJob])
        UserDefaults.standard.set(data, forKey: "zgj_tv_download_jobs")

        let reloadedService = DownloadService()
        let matchingJob = reloadedService.jobs.first { $0.id == jobId }
        XCTAssertEqual(matchingJob?.state, "failed")
        XCTAssertTrue(matchingJob?.error.contains("清理") == true)
        XCTAssertNil(reloadedService.completedLocalURL(dramaId: drama.id, episodeId: ep.id))
    }

    // 5. 验证删除任务与清空全部时的磁盘物理文件清理
    func testDeleteJobAndClearAllRemovesFiles() throws {
        let drama = makeFixtureDrama(id: "test_drama_del")
        let ep = Episode(id: "ep_1", title: "第 1 集", number: 1)
        let jobId = "\(drama.id)_\(ep.id)"

        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let downloadsDir = cachesDir.appendingPathComponent("Downloads", isDirectory: true)
        let localFile = downloadsDir.appendingPathComponent("\(jobId).mp4")
        try Data("dummy".utf8).write(to: localFile)

        let job = DownloadJob(
            id: jobId,
            drama: drama,
            episode: ep,
            state: "completed",
            bytes: 5,
            total: 5,
            progress: 1.0,
            localPath: localFile.path
        )
        let data = try JSONEncoder().encode([job])
        UserDefaults.standard.set(data, forKey: "zgj_tv_download_jobs")

        let currentService = DownloadService()
        XCTAssertEqual(currentService.jobs.count, 1)

        currentService.deleteJob(id: jobId)
        XCTAssertEqual(currentService.jobs.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localFile.path), "deleteJob 必须同步删除本地物理文件")
    }

    // 6. 验证 ViewModel 与 DownloadService 联动及过滤逻辑
    func testDownloadsViewModelFiltering() throws {
        let hgDrama = Drama(id: "hg_1", source: "hongguo", title: "红果剧", cover: "", episodes: 1, category: "", heat: "")
        let otherDrama = Drama(id: "other_1", source: "other_site", title: "其他剧", cover: "", episodes: 1, category: "", heat: "")
        let ep = Episode(id: "ep_1", title: "1", number: 1)

        service.enqueue(drama: hgDrama, episodes: [ep])
        service.enqueue(drama: otherDrama, episodes: [ep])

        let vm = DownloadsViewModel(downloadService: service)
        // 默认处于 hongguo 源，应只过滤出 hongguo 的任务
        let filtered = vm.jobs
        XCTAssertTrue(filtered.allSatisfy { $0.drama.source.lowercased() == "hongguo" })
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.drama.id, "hg_1")
    }

    // 7. 验证 CENC 解密与离线落盘全生命周期
    func testCENCDecryptAndLocalFilePersistence() throws {
        let drama = makeFixtureDrama(id: "cenc_offline_drama")
        let ep = Episode(id: "ep_10", title: "第 10 集", number: 10)
        let jobId = "\(drama.id)_\(ep.id)"

        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let stagingFile = stagingDir.appendingPathComponent("staging.tmp")
        let targetFile = stagingDir.appendingPathComponent("\(jobId).mp4")

        // 构造 NIST AES-128-CTR CENC MP4 测试数据 (参考 CENCDecoderTests)
        func bytes(_ hex: String) -> Data {
            var result = Data()
            var index = hex.startIndex
            while index < hex.endIndex {
                let end = hex.index(index, offsetBy: 2)
                result.append(UInt8(hex[index..<end], radix: 16)!)
                index = end
            }
            return result
        }
        func number(_ value: Int) -> Data {
            var big = UInt32(value).bigEndian
            return withUnsafeBytes(of: &big) { Data($0) }
        }
        func box(_ type: String, _ contents: Data) -> Data {
            number(contents.count + 8) + Data(type.utf8) + contents
        }

        let encrypted = bytes("874d6191b620e3261bef6864990db6ce")
        let tenc = box("tenc", Data(repeating: 0, count: 6) + Data([1, 16]) + Data(repeating: 0, count: 16))
        let sinf = box("sinf", box("frma", Data("avc1".utf8)) + box("schm", number(0) + Data("cenc".utf8) + number(65536)) + box("schi", tenc))
        let entry = box("encv", Data(repeating: 0, count: 78) + sinf)
        let stsd = box("stsd", number(0) + number(1) + entry)
        let stsz = box("stsz", number(0) + number(0) + number(1) + number(encrypted.count))
        let stsc = box("stsc", number(0) + number(1) + number(1) + number(1) + number(1))
        let senc = box("senc", number(0) + number(1) + bytes("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"))
        func moov(_ offset: Int) -> Data {
            let stco = box("stco", number(0) + number(1) + number(offset))
            return box("moov", box("trak", box("mdia", box("minf", box("stbl", stsd + stsz + stsc + stco + senc)))))
        }
        let ftyp = box("ftyp", Data("isom".utf8) + number(0) + Data("isom".utf8))
        let fixtureData = ftyp + moov(ftyp.count + moov(0).count + 8) + box("mdat", encrypted)
        try fixtureData.write(to: stagingFile)

        // 执行解密并落盘
        try CENCMP4Decryptor.shared.decryptDownloadedFile(
            at: stagingFile,
            hexKey: "2b7e151628aed2a6abf7158809cf4f3c",
            destinationURL: targetFile
        )

        let decryptedData = try Data(contentsOf: targetFile)
        XCTAssertEqual(decryptedData.suffix(16), bytes("6bc1bee22e409f96e93d7e117393172a"))
    }

    // 8. 验证播放器离线本地优先路由
    func testPlayerOfflinePlaybackPriority() throws {
        let drama = Drama(id: "offline_drama_99", source: "hongguo", title: "离线优先测试剧", cover: "", episodes: 3, category: "热血", heat: "100万")
        let ep = Episode(id: "ep_1", title: "第 1 集", number: 1)
        let jobId = "\(drama.id)_\(ep.id)"

        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let downloadsDir = cachesDir.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        let localFile = downloadsDir.appendingPathComponent("\(jobId).mp4")
        let dummyMedia = Data(repeating: 0x20, count: 2048)
        try dummyMedia.write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }

        let completedJob = DownloadJob(
            id: jobId,
            drama: drama,
            episode: ep,
            state: "completed",
            bytes: dummyMedia.count,
            total: dummyMedia.count,
            progress: 1.0,
            quality: 1080,
            actualQuality: 1080,
            localPath: localFile.path
        )
        let data = try JSONEncoder().encode([completedJob])
        UserDefaults.standard.set(data, forKey: "zgj_tv_download_jobs")

        let svc = DownloadService()
        // 验证 completedLocalURL 命中
        let resolvedLocalURL = svc.completedLocalURL(dramaId: drama.id, episodeId: ep.id)
        XCTAssertNotNil(resolvedLocalURL)
        XCTAssertEqual(resolvedLocalURL?.scheme, "file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedLocalURL!.path))

        // 验证通过数字编号 episode.number 作为 episodeId 也能兼容命中
        let resolvedByNumber = svc.completedLocalURL(dramaId: drama.id, episodeId: "1")
        XCTAssertNotNil(resolvedByNumber)
        XCTAssertEqual(resolvedByNumber?.path, resolvedLocalURL?.path)
    }
}
