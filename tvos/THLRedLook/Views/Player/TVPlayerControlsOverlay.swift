import SwiftUI

/// 播放器浮层焦点枚举
public enum PlayerOverlayFocusTarget: Hashable {
    case back
    case danmaku
    case danmakuSettings
    case speed
    case quality
    case seekBackward
    case playPause
    case seekForward
    case prevEpisode
    case episodeDrawer
    case nextEpisode
    case previousDrama
    case nextDrama
    case favorite
    case detail
    case refreshFeed
}

public struct TVPlayerControlsOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    public var forceFocusPlayButton: Bool = false
    public var feedActions: TVVideoFeedActions?
    public let onDismiss: () -> Void

    @FocusState private var focusedControl: PlayerOverlayFocusTarget?

    public init(
        viewModel: PlayerViewModel,
        forceFocusPlayButton: Bool = false,
        feedActions: TVVideoFeedActions? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.forceFocusPlayButton = forceFocusPlayButton
        self.feedActions = feedActions
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack {
            // MARK: - 顶部信息与返回条
            HStack(spacing: 20) {
                overlayBarButton(
                    title: "返回",
                    icon: "chevron.left",
                    target: .back
                ) {
                    onDismiss()
                }
                .onMoveCommand { dir in
                    if dir == .down {
                        focusedControl = feedActions == nil ? .playPause : .nextDrama
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.drama.title)
                        .accessibilityIdentifier("player.title")
                        .font(.title3)
                        .bold()
                        .foregroundColor(TVTheme.textPrimary)
                    Text("第 \(viewModel.currentEpisodeIndex) 集 · \(PlaybackPlan.qualityLabel(viewModel.selectedQuality))")
                        .accessibilityIdentifier("player.episode")
                        .font(.subheadline)
                        .foregroundColor(TVTheme.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 56)
            .padding(.top, 42)

            if let feedActions {
                Text(feedActions.progressText)
                    .font(.system(size: 22))
                    .accessibilityIdentifier("feed.progress")
                HStack(spacing: 18) {
                    overlayBarButton(title: "上一部", icon: "arrow.up", target: .previousDrama, action: feedActions.onPrevious)
                        .disabled(!feedActions.canGoPrevious)
                        .opacity(feedActions.canGoPrevious ? 1 : 0.45)
                    overlayBarButton(title: "下一部", icon: "arrow.down", target: .nextDrama) {
                        Task { _ = await feedActions.onNext() }
                    }
                    .disabled(!feedActions.canGoNext)
                    .opacity(feedActions.canGoNext ? 1 : 0.45)
                    overlayBarButton(title: feedActions.isFavorite ? "已收藏" : "收藏", icon: "bookmark", target: .favorite, action: feedActions.onFavorite)
                    overlayBarButton(title: "剧集详情", icon: "info.circle", target: .detail) {
                        feedActions.onDetail(viewModel.drama)
                    }
                    overlayBarButton(title: "换一批", icon: "arrow.clockwise", target: .refreshFeed, action: feedActions.onRefresh)
                        .disabled(feedActions.isLoading)
                    Spacer()
                }
                .padding(.horizontal, 56)
                .padding(.top, 18)
                .onMoveCommand { direction in
                    if direction == .down { focusedControl = .playPause }
                    if direction == .up { focusedControl = .back }
                }
                Text(feedActions.errorMessage ?? "画面模式下按上下键切换短剧，点按显示控制")
                    .font(.system(size: 22))
                    .foregroundStyle(feedActions.errorMessage == nil ? .white.opacity(0.8) : .yellow)
                    .padding(.top, 12)
                    .lineLimit(2)
            }

            // 中间纯净视频画面，无大图标遮挡
            Spacer()

            // MARK: - 底部进度条与一体化操作栏
            VStack(spacing: 24) {
                // 进度条
                HStack(spacing: 16) {
                    Text(formatTime(viewModel.currentTime))
                        .accessibilityIdentifier("player.position")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.white)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.25))
                                .frame(height: 6)
                                .cornerRadius(3)

                            Rectangle()
                                .fill(Color.red)
                                .frame(
                                    width: viewModel.duration > 0
                                        ? geo.size.width * CGFloat(min(1.0, max(0, viewModel.currentTime / viewModel.duration)))
                                        : 0,
                                    height: 6
                                )
                                .cornerRadius(3)
                        }
                    }
                    .frame(height: 6)

                    Text(formatTime(viewModel.duration))
                        .accessibilityIdentifier("player.duration")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.white)
                }

                // 底部两层操作栏：第一层（主播放控制） + 第二层（播放设置与增强）
                VStack(spacing: 14) {
                    // MARK: - 第一层：播放与选集主控制栏
                    HStack(spacing: 14) {
                        // 1. 快退10秒
                        overlayBarButton(
                            title: "快退10秒",
                            icon: "gobackward.10",
                            target: .seekBackward
                        ) {
                            viewModel.seekBy(seconds: -10)
                        }
                        .onMoveCommand { dir in
                            switch dir {
                            case .up: focusedControl = feedActions == nil ? .back : .nextDrama
                            case .down: focusedControl = .speed
                            case .right: focusedControl = .playPause
                            default: break
                            }
                        }

                        // 2. 播放/暂停（高亮核心按钮）
                        overlayBarButton(
                            title: viewModel.wantsPlayback ? "暂停" : "播放",
                            icon: viewModel.wantsPlayback ? "pause.fill" : "play.fill",
                            target: .playPause,
                            isProminent: true
                        ) {
                            NSLog("🎬 [Overlay] 点击 播放/暂停 按钮")
                            viewModel.togglePlayPause()
                        }
                        .accessibilityLabel(viewModel.wantsPlayback ? "暂停" : "播放")
                        .onMoveCommand { dir in
                            switch dir {
                            case .up: focusedControl = feedActions == nil ? .back : .nextDrama
                            case .down: focusedControl = .speed
                            case .left: focusedControl = .seekBackward
                            case .right: focusedControl = .seekForward
                            default: break
                            }
                        }

                        // 3. 快进10秒
                        overlayBarButton(
                            title: "快进10秒",
                            icon: "goforward.10",
                            target: .seekForward
                        ) {
                            viewModel.seekBy(seconds: 10)
                        }
                        .onMoveCommand { dir in
                            switch dir {
                            case .up: focusedControl = feedActions == nil ? .back : .nextDrama
                            case .down:
                                if let plan = viewModel.plan, !plan.qualities.isEmpty {
                                    focusedControl = .quality
                                } else {
                                    focusedControl = .speed
                                }
                            case .left: focusedControl = .playPause
                            case .right:
                                if viewModel.currentEpisodeIndex > 1 {
                                    focusedControl = .prevEpisode
                                } else {
                                    focusedControl = .episodeDrawer
                                }
                            default: break
                            }
                        }

                        // 4. 上一集
                        overlayBarButton(
                            title: "上一集",
                            icon: "backward.end.fill",
                            target: .prevEpisode
                        ) {
                            Task { await viewModel.previousEpisode() }
                        }
                        .disabled(viewModel.currentEpisodeIndex <= 1)
                        .opacity(viewModel.currentEpisodeIndex <= 1 ? 0.5 : 1.0)
                        .onMoveCommand { dir in
                            switch dir {
                            case .up: focusedControl = feedActions == nil ? .back : .nextDrama
                            case .down:
                                if let plan = viewModel.plan, !plan.qualities.isEmpty {
                                    focusedControl = .quality
                                } else {
                                    focusedControl = .danmaku
                                }
                            case .left: focusedControl = .seekForward
                            case .right: focusedControl = .episodeDrawer
                            default: break
                            }
                        }

                        // 5. 选集列表
                        overlayBarButton(
                            title: "选集列表",
                            icon: "list.bullet",
                            target: .episodeDrawer
                        ) {
                            NSLog("🎬 [Overlay] 点击 选集列表 按钮")
                            viewModel.restoreFocusTarget = .episodeDrawer
                            viewModel.isEpisodeDrawerVisible = true
                        }
                        .onMoveCommand { dir in
                            switch dir {
                            case .up: focusedControl = feedActions == nil ? .back : .nextDrama
                            case .down: focusedControl = .danmaku
                            case .left:
                                if viewModel.currentEpisodeIndex > 1 {
                                    focusedControl = .prevEpisode
                                } else {
                                    focusedControl = .seekForward
                                }
                            case .right:
                                if viewModel.currentEpisodeIndex < viewModel.allEpisodes.count {
                                    focusedControl = .nextEpisode
                                } else {
                                    focusedControl = .speed
                                }
                            default: break
                            }
                        }

                        // 6. 下一集
                        overlayBarButton(
                            title: "下一集",
                            icon: "forward.end.fill",
                            target: .nextEpisode
                        ) {
                            Task { await viewModel.nextEpisode() }
                        }
                        .disabled(viewModel.currentEpisodeIndex >= viewModel.allEpisodes.count)
                        .opacity(viewModel.currentEpisodeIndex >= viewModel.allEpisodes.count ? 0.5 : 1.0)
                        .onMoveCommand { dir in
                            switch dir {
                            case .up: focusedControl = feedActions == nil ? .back : .nextDrama
                            case .down: focusedControl = .danmakuSettings
                            case .left: focusedControl = .episodeDrawer
                            case .right: focusedControl = .speed
                            default: break
                            }
                        }

                        Spacer()
                    }

                    // MARK: - 第二层：播放设置与观影增强栏
                    HStack(spacing: 14) {
                        // 7. 播放倍速
                        overlayBarButton(
                            title: "\(String(format: "%.1f", viewModel.playbackRate))x 倍速",
                            icon: "speedometer",
                            target: .speed
                        ) {
                            viewModel.restoreFocusTarget = .speed
                            viewModel.isSpeedSheetVisible = true
                        }
                        .onMoveCommand { dir in
                            switch dir {
                            case .up: focusedControl = .playPause
                            case .left:
                                if viewModel.currentEpisodeIndex < viewModel.allEpisodes.count {
                                    focusedControl = .nextEpisode
                                } else {
                                    focusedControl = .episodeDrawer
                                }
                            case .right:
                                if let plan = viewModel.plan, !plan.qualities.isEmpty {
                                    focusedControl = .quality
                                } else {
                                    focusedControl = .danmaku
                                }
                            default: break
                            }
                        }

                        // 8. 分辨率 / 清晰度
                        if let plan = viewModel.plan, !plan.qualities.isEmpty {
                            overlayBarButton(
                                title: PlaybackPlan.qualityLabel(viewModel.selectedQuality),
                                icon: "sparkles.tv",
                                target: .quality
                            ) {
                                let qs = plan.qualities
                                if let idx = qs.firstIndex(of: viewModel.selectedQuality) {
                                    let next = qs[(idx + 1) % qs.count]
                                    Task { await viewModel.changeQuality(next) }
                                }
                            }
                            .onMoveCommand { dir in
                                switch dir {
                                case .up: focusedControl = .seekForward
                                case .left: focusedControl = .speed
                                case .right: focusedControl = .danmaku
                                default: break
                                }
                            }
                        }

                        // 9. 弹幕快捷开关
                        overlayBarButton(
                            title: viewModel.danmakuEnabled ? "弹幕：开" : "弹幕：关",
                            icon: viewModel.danmakuEnabled ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right",
                            target: .danmaku,
                            isProminent: false
                        ) {
                            viewModel.toggleDanmaku()
                        }
                        .onMoveCommand { dir in
                            switch dir {
                            case .up: focusedControl = .episodeDrawer
                            case .left:
                                if let plan = viewModel.plan, !plan.qualities.isEmpty {
                                    focusedControl = .quality
                                } else {
                                    focusedControl = .speed
                                }
                            case .right: focusedControl = .danmakuSettings
                            default: break
                            }
                        }

                        // 10. 弹幕样式设置
                        overlayBarButton(
                            title: "弹幕样式",
                            icon: "slider.horizontal.3",
                            target: .danmakuSettings,
                            isProminent: false
                        ) {
                            viewModel.restoreFocusTarget = .danmakuSettings
                            viewModel.isDanmakuSettingsVisible = true
                        }
                        .onMoveCommand { dir in
                            switch dir {
                            case .up:
                                if viewModel.currentEpisodeIndex < viewModel.allEpisodes.count {
                                    focusedControl = .nextEpisode
                                } else {
                                    focusedControl = .episodeDrawer
                                }
                            case .left: focusedControl = .danmaku
                            default: break
                            }
                        }

                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 56)
            .padding(.bottom, 44)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.clear, Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onChange(of: focusedControl) { _, _ in viewModel.showControls() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let restore = viewModel.restoreFocusTarget {
                    focusedControl = restore
                    viewModel.restoreFocusTarget = nil
                } else {
                    focusedControl = .playPause
                }
            }
        }
    }

    // MARK: - 辅助组件：自适应焦点的条形按钮
    @ViewBuilder
    private func overlayBarButton(
        title: String,
        icon: String? = nil,
        target: PlayerOverlayFocusTarget,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = (focusedControl == target)
        Button(action: action) {
            HStack(spacing: 12) {
                if let ic = icon {
                    Image(systemName: ic)
                        .font(.system(size: 18, weight: .bold))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .padding(.horizontal, title.isEmpty ? 20 : 28)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isProminent ? (isFocused ? TVTheme.primaryHover : TVTheme.primary) : (isFocused ? TVTheme.surfaceFocused : TVTheme.surfaceCard))
            )
            .foregroundColor(TVTheme.textPrimary)
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 14)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($focusedControl, equals: target)
        .accessibilityIdentifier("player.\(target)")
        .focusEffectDisabled()
    }

    // MARK: - 辅助组件：自适应焦点的圆形核心按钮
    @ViewBuilder
    private func overlayCircleButton(
        icon: String,
        size: CGFloat,
        padding: CGFloat,
        target: PlayerOverlayFocusTarget,
        isProminent: Bool = false,
        forceFocused: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let effectiveFocused = (focusedControl == target) || forceFocused
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundColor(TVTheme.textPrimary)
                .padding(padding)
                .background(
                    Circle()
                        .fill(isProminent ? (effectiveFocused ? TVTheme.primaryHover : TVTheme.primary) : (effectiveFocused ? TVTheme.surfaceFocused : Color.black.opacity(0.85)))
                )
                .tvCircleFocus(isFocused: effectiveFocused)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($focusedControl, equals: target)
        .accessibilityIdentifier("player.\(target)")
        .accessibilityLabel(target == .playPause ? (viewModel.wantsPlayback ? "暂停" : "播放") : target == .seekForward ? "快进10秒" : "后退10秒")
        .focusEffectDisabled()
    }

    private func formatTime(_ sec: Double) -> String {
        guard !sec.isNaN && sec >= 0 else { return "00:00" }
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
