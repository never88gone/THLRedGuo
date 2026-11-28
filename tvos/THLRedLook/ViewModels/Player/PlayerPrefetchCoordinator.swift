import Foundation
import AVFoundation

@MainActor
final class PlayerPrefetchCoordinator {
    var preloadedEpisode: PreloadedEpisode?

    private let preloadingRepository: NativeRepository
    private var prefetchTask: Task<Void, Never>?
    private var prefetchSequence = 0
    private var prefetchAttempts = 0
    private var prefetchRetryAt = Date.distantPast
    private var targetIdentity = ""
    private var inFlightDramaId = ""
    private var inFlightEpisodeNumber = 0
    private var inFlightQuality = 0

    init(preloadingRepository: NativeRepository) {
        self.preloadingRepository = preloadingRepository
    }

    func cancel() {
        prefetchSequence += 1
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    func clearPreloaded(currentDecryptedURL: URL?) {
        cancel()
        if let preloaded = preloadedEpisode {
            releasePreloadedResources(preloaded, currentDecryptedURL: currentDecryptedURL)
            preloadedEpisode = nil
        }
    }

    func waitForInFlightIfMatching(dramaId: String, episodeIndex: Int, requestedQuality: Int) async -> Bool {
        guard let task = prefetchTask,
              inFlightDramaId == dramaId,
              inFlightEpisodeNumber == episodeIndex,
              inFlightQuality == requestedQuality else {
            return false
        }
        await task.value
        return true
    }

    func consumePreloaded(for episodeIndex: Int, dramaId: String = "", requestedQuality: Int = 0, currentDecryptedURL: URL?) -> PreloadedEpisode? {
        guard let preloaded = preloadedEpisode,
              preloaded.episodeIndex == episodeIndex,
              (dramaId.isEmpty || preloaded.dramaId.isEmpty || preloaded.dramaId == dramaId),
              preloaded.requestedQuality == requestedQuality,
              preloaded.plan.isReusable() else {
            return nil
        }
        preloadedEpisode = nil
        return preloaded
    }

    func prefetchNextEpisode(
        nextEpisodeNumber: Int,
        allEpisodes: [Episode],
        drama: Drama,
        requestedQuality: Int,
        playbackRate: Float = 1.0,
        generation: Int
    ) {
        let identity = "\(drama.id):\(nextEpisodeNumber):\(requestedQuality):\(generation)"
        if targetIdentity != identity {
            cancel()
            targetIdentity = identity
            prefetchAttempts = 0
            prefetchRetryAt = .distantPast
        }
        guard !(preloadedEpisode?.episodeIndex == nextEpisodeNumber && (preloadedEpisode?.dramaId.isEmpty ?? true || preloadedEpisode?.dramaId == drama.id)),
              prefetchTask == nil,
              prefetchAttempts < 2, Date() >= prefetchRetryAt else { return }

        prefetchAttempts += 1
        prefetchRetryAt = Date().addingTimeInterval(10)
        prefetchSequence += 1
        let sequence = prefetchSequence
        inFlightDramaId = drama.id
        inFlightEpisodeNumber = nextEpisodeNumber
        inFlightQuality = requestedQuality
        let targetEpisode = allEpisodes.first { $0.number == nextEpisodeNumber }
        let targetDrama = drama
        let preloadRepo = self.preloadingRepository
        let targetRate: Float = playbackRate > 0 ? playbackRate : 1.0

        prefetchTask = Task { [weak self] in
            var tempPlayer: AVPlayer?
            var tempDecryptedURL: URL?
            defer {
                if self?.prefetchSequence == sequence {
                    self?.prefetchTask = nil
                    self?.inFlightDramaId = ""
                    self?.inFlightEpisodeNumber = 0
                }
            }
            do {
                let resolvedPlan = try await preloadRepo.resolvePlayback(
                    drama: targetDrama,
                    episode: targetEpisode,
                    episodeIndex: nextEpisodeNumber,
                    quality: requestedQuality
                )
                guard !Task.isCancelled else { return }
                guard let scheme = URL(string: resolvedPlan.url)?.scheme, ["https", "http", "file"].contains(scheme) else { return }

                let prepared = try await PlaybackAssetFactory.prepare(resolvedPlan)
                tempDecryptedURL = prepared.decryptedURL
                let asset = prepared.asset
                let (isPlayable, _, _) = try await asset.load(.isPlayable, .tracks, .duration)
                guard isPlayable else {
                    throw NSError(domain: "PlaybackPrefetch", code: -1, userInfo: [NSLocalizedDescriptionKey: "下一集预加载尚未就绪"])
                }
                guard !Task.isCancelled else {
                    if let temp = tempDecryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: temp) }
                    return
                }
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 12

                let warmPlayer = AVPlayer(playerItem: item)
                warmPlayer.isMuted = true
                warmPlayer.volume = 0
                warmPlayer.automaticallyWaitsToMinimizeStalling = true
                tempPlayer = warmPlayer

                let warmedReady = await Self.warmUpPlayerBuffer(warmPlayer, item: item, playbackRate: targetRate)
                guard warmedReady, !Task.isCancelled else {
                    warmPlayer.pause()
                    warmPlayer.replaceCurrentItem(with: nil)
                    if let temp = tempDecryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: temp) }
                    return
                }

                guard let self, sequence == self.prefetchSequence, !Task.isCancelled else {
                    warmPlayer.pause()
                    warmPlayer.replaceCurrentItem(with: nil)
                    if let temp = tempDecryptedURL {
                        CENCMP4Decryptor.shared.removePlaybackCache(at: temp)
                    }
                    return
                }
                if let old = self.preloadedEpisode {
                    self.releasePreloadedResources(old, currentDecryptedURL: tempDecryptedURL)
                }
                self.preloadedEpisode = PreloadedEpisode(
                    episodeIndex: nextEpisodeNumber,
                    dramaId: targetDrama.id,
                    requestedQuality: requestedQuality,
                    playbackRate: targetRate,
                    plan: resolvedPlan,
                    playerItem: item,
                    player: warmPlayer,
                    decryptedURL: tempDecryptedURL
                )
                tempPlayer = nil
                tempDecryptedURL = nil
                NSLog("🎬 [PlayerPrefetch] 成功提前缓冲并预热第%d集", nextEpisodeNumber)
            } catch {
                tempPlayer?.pause()
                tempPlayer?.replaceCurrentItem(with: nil)
                if let temp = tempDecryptedURL { CENCMP4Decryptor.shared.removePlaybackCache(at: temp) }
                guard !Task.isCancelled, self?.prefetchSequence == sequence else { return }
                NSLog("[PlayerPrefetch] prefetch failed episode=%d attempt=%d code=%@", nextEpisodeNumber, self?.prefetchAttempts ?? 0, (error as NSError).userInfo["diagnosticCode"] as? String ?? "PREFETCH_FAILED")
            }
        }
    }

    private func releasePreloadedResources(_ preloaded: PreloadedEpisode, currentDecryptedURL: URL?) {
        preloaded.player?.pause()
        preloaded.player?.replaceCurrentItem(with: nil)
        if let dec = preloaded.decryptedURL, dec != currentDecryptedURL {
            CENCMP4Decryptor.shared.removePlaybackCache(at: dec)
        }
    }

    private static func warmUpPlayerBuffer(_ player: AVPlayer, item: AVPlayerItem, playbackRate: Float) async -> Bool {
        let isLocal = (item.asset as? AVURLAsset)?.url.isFileURL ?? false
        let deadline = Date().addingTimeInterval(isLocal ? 3.0 : 8.0)
        while !Task.isCancelled && Date() < deadline {
            if item.status == .failed { return false }
            if item.status == .readyToPlay {
                if isLocal || item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull || item.bufferedSecondsAhead(from: .zero) >= 2.0 {
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard !Task.isCancelled, item.status == .readyToPlay else { return false }
        if player.status == .readyToPlay && player.rate == 0 && playbackRate > 0 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                player.preroll(atRate: playbackRate) { _ in
                    continuation.resume()
                }
            }
        }
        return !Task.isCancelled && item.status == .readyToPlay
    }
}
