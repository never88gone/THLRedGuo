import SwiftUI

// MARK: - TVPlayerView 手势与切集扩展（拆分以保持单文件行数 < 500 行）
extension TVPlayerView {
    internal var playbackAccessibilityValue: String {
        let position = viewModel.currentTime.isFinite
            ? String(format: "%.0f", max(0, viewModel.currentTime.rounded(.down))) : "0"
        let state: String
        if viewModel.isPlaying {
            state = "播放中"
        } else if !viewModel.wantsPlayback {
            state = "已暂停"
        } else if viewModel.isLoading || viewModel.isBuffering {
            state = "加载中"
        } else {
            state = "已暂停"
        }
        return "\(viewModel.drama.title) · 第 \(viewModel.currentEpisodeIndex) 集 · 已播放 \(position) 秒 · \(state)"
    }

    internal var playerFeedActions: TVVideoFeedActions? {
        guard let feedActions else { return nil }
        return TVVideoFeedActions(
            progressText: feedActions.progressText,
            canGoPrevious: feedActions.canGoPrevious && !isSwitchingFeed,
            canGoNext: feedActions.canGoNext && !isSwitchingFeed,
            isLoading: feedActions.isLoading || isSwitchingFeed,
            isFavorite: feedActions.isFavorite,
            errorMessage: feedActions.errorMessage,
            onPrevious: { feedActions.onPrevious() },
            onNext: { await nextFeedDrama() },
            onFavorite: feedActions.onFavorite,
            onDetail: { drama in viewModel.onDisappear(); feedActions.onDetail(drama) },
            onRefresh: { viewModel.onDisappear(); feedActions.onRefresh() }
        )
    }

    internal func handlePictureMoveCommand(_ direction: MoveCommandDirection) {
        guard isInteractive, !isSwitchingFeed,
              !viewModel.isControlsVisible, !viewModel.isEpisodeDrawerVisible,
              !viewModel.isDanmakuSettingsVisible, !viewModel.isSpeedSheetVisible && !viewModel.isQualitySheetVisible else { return }
        switch direction {
        case .left:
            handleQuickSeek(by: -10)
        case .right:
            handleQuickSeek(by: 10)
        case .up:
            if let feedActions {
                if feedActions.canGoPrevious { feedActions.onPrevious() }
            } else {
                handlePreviousEpisode()
            }
        case .down:
            if feedActions != nil {
                Task { _ = await nextFeedDrama() }
            } else {
                handleNextEpisode()
            }
        default:
            break
        }
    }

    internal func handlePreviousEpisode() {
        guard viewModel.currentEpisodeIndex > 1 else {
            viewModel.showToast("已经是第 1 集")
            return
        }
        viewModel.showToast("正在切换至第 \(viewModel.currentEpisodeIndex - 1) 集")
        Task { await viewModel.previousEpisode() }
    }

    internal func handleNextEpisode() {
        guard viewModel.currentEpisodeIndex < viewModel.allEpisodes.count else {
            viewModel.showToast("已经是最后一集")
            return
        }
        viewModel.showToast("正在切换至第 \(viewModel.currentEpisodeIndex + 1) 集")
        Task { await viewModel.nextEpisode() }
    }

    internal func onRemoteMenuPressed() {
        let now = Date().timeIntervalSince1970
        guard now - lastExitTime > 0.35 else { return }
        lastExitTime = now

        if viewModel.isDanmakuSettingsVisible {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.isDanmakuSettingsVisible = false }
            viewModel.showControls()
        } else if viewModel.isQualitySheetVisible {
            viewModel.restoreFocusTarget = .quality
            viewModel.isQualitySheetVisible = false
            viewModel.showControls()
        } else if viewModel.isSpeedSheetVisible {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.isSpeedSheetVisible = false }
            viewModel.showControls()
        } else if viewModel.isCommentDrawerVisible {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.isCommentDrawerVisible = false }
            viewModel.showControls()
        } else if viewModel.isEpisodeDrawerVisible {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.isEpisodeDrawerVisible = false }
            viewModel.showControls()
        } else if viewModel.isControlsVisible {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.hideControls() }
        } else {
            handleExit()
        }
    }

    internal func nextFeedDrama() async -> Bool {
        guard let feedActions, feedActions.canGoNext, !isSwitchingFeed else { return false }
        isSwitchingFeed = true
        let changed = await feedActions.onNext()
        isSwitchingFeed = false
        if !changed && isPlayerPresented {
            viewModel.setSceneActive(scenePhase == .active)
            viewModel.showControls()
        }
        return changed
    }

    internal func handleExit() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            viewModel.onDisappear()
            presentationMode.wrappedValue.dismiss()
        }
    }

    internal func handleQuickSeek(by delta: Double) {
        let base = showQuickSeekIndicator ? quickSeekTarget : viewModel.currentTime
        let maxLimit = viewModel.duration > 0 ? viewModel.duration : 10000.0
        let newTarget = max(0, min(base + delta, maxLimit))
        let totalDelta = newTarget - viewModel.currentTime

        quickSeekTarget = newTarget
        quickSeekDelta = totalDelta
        withAnimation(.easeOut(duration: 0.15)) { showQuickSeekIndicator = true }
        viewModel.seekTo(target: newTarget)

        quickSeekHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) { showQuickSeekIndicator = false }
        }
        quickSeekHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: workItem)
    }

    internal func handlePanBegan() {
        guard !viewModel.isControlsVisible && !viewModel.isEpisodeDrawerVisible else { return }
        initialScrubPosition = viewModel.currentTime
        quickSeekTarget = viewModel.currentTime
        quickSeekDelta = 0
        isScrubbing = true
        quickSeekHideWorkItem?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { showQuickSeekIndicator = true }
    }

    internal func handlePanChanged(translationX: CGFloat) {
        guard isScrubbing, viewModel.duration > 0 else { return }
        let deltaSeconds = Double(translationX) * 0.18
        let target = max(0, min(initialScrubPosition + deltaSeconds, viewModel.duration))
        quickSeekTarget = target
        quickSeekDelta = target - initialScrubPosition
    }

    internal func handlePanEnded() {
        guard isScrubbing else { return }
        isScrubbing = false
        viewModel.seekTo(target: quickSeekTarget)

        quickSeekHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) { showQuickSeekIndicator = false }
        }
        quickSeekHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: workItem)
    }
}
