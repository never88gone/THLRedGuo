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
            if let dec = preloaded.decryptedURL, dec != currentDecryptedURL {
                CENCMP4Decryptor.shared.removePlaybackCache(at: dec)
            }
            preloadedEpisode = nil
        }
    }

    func consumePreloaded(for episodeIndex: Int, currentDecryptedURL: URL?) -> PreloadedEpisode? {
        guard let preloaded = preloadedEpisode, preloaded.episodeIndex == episodeIndex, preloaded.plan.isReusable() else {
            return nil
        }
        preloadedEpisode = nil
        return preloaded
    }

    func prefetchNextEpisode(
        currentEpisodeIndex: Int,
        allEpisodes: [Episode],
        drama: Drama,
        requestedQuality: Int,
        generation: Int
    ) {
        let nextIndex = currentEpisodeIndex + 1
        guard nextIndex <= allEpisodes.count else { return }
        guard preloadedEpisode?.episodeIndex != nextIndex, prefetchTask == nil,
              prefetchAttempts < 2, Date() >= prefetchRetryAt else { return }

        prefetchAttempts += 1
        prefetchRetryAt = Date().addingTimeInterval(10)
        prefetchSequence += 1
        let sequence = prefetchSequence
        let targetEpisode = allEpisodes.indices.contains(nextIndex - 1) ? allEpisodes[nextIndex - 1] : nil
        let targetDrama = drama
        let preloadRepo = self.preloadingRepository

        prefetchTask = Task { [weak self] in
            defer {
                if self?.prefetchSequence == sequence { self?.prefetchTask = nil }
            }
            do {
                let resolvedPlan = try await preloadRepo.resolvePlayback(
                    drama: targetDrama,
                    episode: targetEpisode,
                    episodeIndex: nextIndex,
                    quality: requestedQuality
                )
                guard !Task.isCancelled else { return }
                guard let scheme = URL(string: resolvedPlan.url)?.scheme, ["https", "http", "file"].contains(scheme) else { return }

                let prepared = try await PlaybackAssetFactory.prepare(resolvedPlan)
                let decryptedTempURL = prepared.decryptedURL
                let asset = prepared.asset
                guard try await asset.load(.isPlayable) else {
                    throw NSError(domain: "PlaybackPrefetch", code: -1, userInfo: [NSLocalizedDescriptionKey: "下一集预加载尚未就绪"])
                }
                guard !Task.isCancelled else {
                    if let temp = decryptedTempURL { CENCMP4Decryptor.shared.removePlaybackCache(at: temp) }
                    return
                }
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 3

                await MainActor.run {
                    guard let self, sequence == self.prefetchSequence, !Task.isCancelled else {
                        if let temp = decryptedTempURL {
                            CENCMP4Decryptor.shared.removePlaybackCache(at: temp)
                        }
                        return
                    }
                    if let old = self.preloadedEpisode, let oldDec = old.decryptedURL, oldDec != decryptedTempURL {
                        CENCMP4Decryptor.shared.removePlaybackCache(at: oldDec)
                    }
                    self.preloadedEpisode = PreloadedEpisode(
                        episodeIndex: nextIndex,
                        plan: resolvedPlan,
                        playerItem: item,
                        decryptedURL: decryptedTempURL
                    )
                    NSLog("🎬 [PlayerPrefetch] 成功提前加载并解密第%d集", nextIndex)
                }
            } catch {
                guard !Task.isCancelled, self?.prefetchSequence == sequence else { return }
                NSLog("[PlayerPrefetch] prefetch failed episode=%d attempt=%d code=%@", nextIndex, self?.prefetchAttempts ?? 0, (error as NSError).userInfo["diagnosticCode"] as? String ?? "PREFETCH_FAILED")
            }
        }
    }
}
