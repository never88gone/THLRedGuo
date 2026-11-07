import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import hilog from '@ohos.hilog';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { DramaDetail, EpisodeInfo, DramaItem } from '../../models/Drama';
import { PlaybackState } from '../../models/Episode';
import { PlayerController } from '../../core/player/PlayerController';
import { CoreEngine } from '../../core/engine/CoreEngine';
import { LocalStore } from '../../core/store/LocalStore';

const TAG = 'PlayerPage';
const DOMAIN = 0x0000;

@Entry
@Component
struct PlayerPage {
  @State dramaId: string = '';
  @State dramaTitle: string = '';
  @State coverUrl: string = '';
  @State currentEpisodeIndex: number = 1;
  @State detail: DramaDetail | null = null;

  @State isPlaying: boolean = false;
  @State isBuffering: boolean = true;
  @State currentPosition: number = 0;
  @State duration: number = 0;
  @State speed: number = 1.0;
  @State videoRatio: number = 9 / 16;
  @State showControls: boolean = true;
  @State isFullscreen: boolean = false;
  @State currentTab: number = 0; // 0: 选集, 1: 简介
  @State isFavorite: boolean = false;

  private playerController: PlayerController = new PlayerController();
  private xComponentController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private controlsTimer: number = -1;

  aboutToAppear(): void {
    try {
      hilog.info(DOMAIN, TAG, 'PlayerPage aboutToAppear enter');
      const params = router.getParams() as Record<string, Object>;
      if (params) {
        this.dramaId = (params['dramaId'] as string) ?? '';
        this.dramaTitle = (params['dramaTitle'] as string) ?? '';
        this.currentEpisodeIndex = (params['episodeIndex'] as number) ?? 1;
        this.coverUrl = (params['coverUrl'] as string) ?? '';
        hilog.info(DOMAIN, TAG, 'Params: dramaId=%{public}s, ep=%{public}d', this.dramaId, this.currentEpisodeIndex);
      }

      this.playerController.setListener((state: PlaybackState) => {
        this.isPlaying = state.isPlaying;
        this.isBuffering = state.isBuffering;
        this.currentPosition = state.currentPosition;
        this.duration = state.duration;
        this.speed = state.speed;
        if (state.aspectRatio && state.aspectRatio > 0) {
          this.videoRatio = state.aspectRatio;
        }

        // 自动保存历史进度
        if (this.dramaId && state.duration > 0 && Math.floor(state.currentPosition / 1000) % 5 === 0) {
          LocalStore.getInstance().saveHistory({
            dramaId: this.dramaId,
            dramaTitle: this.dramaTitle,
            coverUrl: this.coverUrl || (this.detail?.coverUrl ?? ''),
            episodeIndex: this.currentEpisodeIndex,
            positionMs: state.currentPosition,
            durationMs: state.duration,
            updatedAt: Date.now()
          });
        }
      });

      this.playerController.setOnCompleted(() => {
        hilog.info(DOMAIN, TAG, 'Playback finished, auto-advancing to next episode');
        this.playNextEpisode();
      });

      this.loadDetail();
      this.checkFavorite();
      this.resetControlsTimer();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'aboutToAppear error: %{public}s', JSON.stringify(e));
    }
  }

  aboutToDisappear(): void {
    if (this.controlsTimer !== -1) {
      clearTimeout(this.controlsTimer);
      this.controlsTimer = -1;
    }
    this.playerController.release();
  }

  async checkFavorite(): Promise<void> {
    if (this.dramaId) {
      this.isFavorite = await LocalStore.getInstance().isFavorite(this.dramaId);
    }
  }

  async toggleFavorite(): Promise<void> {
    if (!this.dramaId) return;
    const dramaItem: DramaItem = {
      id: this.dramaId,
      title: this.dramaTitle,
      coverUrl: this.coverUrl,
      remarks: this.detail?.remarks ?? '',
      intro: this.detail?.intro ?? '',
      episodeCount: this.detail?.episodeCount ?? 0,
      source: 'hongguo'
    };
    this.isFavorite = await LocalStore.getInstance().toggleFavorite(dramaItem);
    promptAction.showToast({
      message: this.isFavorite ? '已加入追剧列表' : '已取消追剧'
    });
  }

  async loadDetail(): Promise<void> {
    if (this.dramaId) {
      this.detail = await CoreEngine.getInstance().getDramaDetail(this.dramaId);
      if (this.detail) {
        if (!this.coverUrl) {
          this.coverUrl = this.detail.coverUrl;
        }
        if (!this.dramaTitle) {
          this.dramaTitle = this.detail.title;
        }
      }
    }
  }

  async startPlayback(epIndex: number): Promise<void> {
    this.currentEpisodeIndex = epIndex;
    this.isBuffering = true;

    try {
      if (!this.detail || this.detail.episodes.length === 0) {
        await this.loadDetail();
      }

      const targetEp = this.detail?.episodes.find(e => e.index === epIndex);
      if (!targetEp) {
        hilog.warn(DOMAIN, TAG, 'No episode found for index %{public}d in drama %{public}s', epIndex, this.dramaId);
        promptAction.showToast({ message: '未找到选集资源' });
        this.isBuffering = false;
        return;
      }

      hilog.info(DOMAIN, TAG, 'Resolving playback for ep %{public}d: %{public}s', epIndex, targetEp.rawUrl);
      const playResult = await CoreEngine.getInstance().resolvePlayback(targetEp.flag ?? 'hongguo', targetEp.rawUrl);
      if (playResult && playResult.url) {
        await this.playerController.loadMedia(this.dramaId, this.dramaTitle, epIndex, playResult);
      } else {
        hilog.warn(DOMAIN, TAG, 'Playback resolution failed for ep %{public}d', epIndex);
        promptAction.showToast({ message: '视频源解析暂无直链，正在重试...' });
        this.isBuffering = false;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'startPlayback error: %{public}s', JSON.stringify(e));
      promptAction.showToast({ message: '播放异常: ' + JSON.stringify(e) });
      this.isBuffering = false;
    }
  }

  playPreviousEpisode(): void {
    if (this.currentEpisodeIndex > 1) {
      this.startPlayback(this.currentEpisodeIndex - 1);
    } else {
      promptAction.showToast({ message: '已经是第一集了' });
    }
  }

  playNextEpisode(): void {
    const total = this.detail?.episodes.length ?? 0;
    if (total > 0 && this.currentEpisodeIndex < total) {
      this.startPlayback(this.currentEpisodeIndex + 1);
    } else {
      promptAction.showToast({ message: '已经是最后一集了' });
    }
  }

  togglePlayPause(): void {
    if (this.isPlaying) {
      this.playerController.pause();
    } else {
      this.playerController.play();
    }
    this.resetControlsTimer();
  }

  cycleSpeed(): void {
    const speeds = [1.0, 1.25, 1.5, 2.0];
    const currentIndex = speeds.indexOf(this.speed);
    const nextSpeed = speeds[(currentIndex + 1) % speeds.length];
    this.playerController.setSpeed(nextSpeed);
    promptAction.showToast({ message: `倍速切换为: ${nextSpeed}x` });
    this.resetControlsTimer();
  }

  formatTime(ms: number): string {
    const totalSeconds = Math.max(0, Math.floor(ms / 1000));
    const m = Math.floor(totalSeconds / 60);
    const s = totalSeconds % 60;
    const mm = m < 10 ? `0${m}` : `${m}`;
    const ss = s < 10 ? `0${s}` : `${s}`;
    return `${mm}:${ss}`;
  }

  resetControlsTimer(): void {
    if (this.controlsTimer !== -1) {
      clearTimeout(this.controlsTimer);
      this.controlsTimer = -1;
    }
    this.showControls = true;
    this.controlsTimer = setTimeout(() => {
      if (this.isPlaying && !this.isBuffering) {
        this.showControls = false;
      }
    }, 3500);
  }

  build() {
    Column() {
      // 1. 视频播放视口（无论半屏还是全屏，均保持真实视频宽高比，居中黑条填充，严禁拉伸）
      Stack({ alignContent: Alignment.Center }) {
        // 黑色底层背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)

        // 视频渲染表面：通过 aspectRatio 居中约束比例，绝不拉伸
        XComponent({
          id: 'playerSurface',
          type: 'surface',
          controller: this.xComponentController
        })
          .onLoad(() => {
            try {
              this.surfaceId = this.xComponentController.getXComponentSurfaceId();
              hilog.info(DOMAIN, TAG, 'XComponent onLoad, surfaceId: %{public}s', this.surfaceId);
              this.playerController.setSurfaceId(this.surfaceId);
              this.startPlayback(this.currentEpisodeIndex);
            } catch (e) {
              hilog.error(DOMAIN, TAG, 'XComponent onLoad error: %{public}s', JSON.stringify(e));
            }
          })
          .aspectRatio(this.videoRatio > 0 ? this.videoRatio : 9 / 16)
          .height('100%')
          .backgroundColor(Color.Black)

        // 触摸透明覆盖层：点击切换控制栏显隐
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showControls = !this.showControls;
            if (this.showControls) {
              this.resetControlsTimer();
            }
          })

        // 缓冲加载状态（加载时仅显示转圈与文字，绝不遮挡中央播放图标）
        if (this.isBuffering) {
          Column({ space: 8 }) {
            LoadingProgress()
              .width(42)
              .height(42)
              .color(AppColors.hongguoRed)
            Text('正在加载短剧视频...')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
          }
          .hitTestBehavior(HitTestMode.None)
        }

        // 播放控制浮层 (对齐 Flutter PlayerControls, PlayerTopBarView, PlayerCenterView, PlayerBottomBarView)
        if (this.showControls) {
          Column() {
            // A. 顶部导航栏 (PlayerTopBarView: 左侧半透明圆形返回按钮 + 剧集标题)
            Row({ space: 10 }) {
              Button({ type: ButtonType.Circle }) {
                Image($r('app.media.ic_arrow_back'))
                  .width(20)
                  .height(20)
                  .fillColor(Color.White)
              }
              .backgroundColor('rgba(0, 0, 0, 0.45)')
              .border({ width: 0.8, color: 'rgba(255, 255, 255, 0.2)' })
              .width(36)
              .height(36)
              .onClick(() => {
                if (this.isFullscreen) {
                  this.isFullscreen = false;
                } else {
                  router.back();
                }
              })

              Column({ space: 2 }) {
                Text(this.dramaTitle || '正在播放')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(`第 ${this.currentEpisodeIndex} 集`)
                  .fontSize(11)
                  .fontColor(AppColors.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 38, bottom: 8 })
            .backgroundColor('rgba(0, 0, 0, 0.45)')

            Blank()

            // B. 居中操作区 (PlayerCenterView: 上一集 + 播放/暂停 + 下一集，仅在非缓冲时显示)
            if (!this.isBuffering) {
              Row({ space: 28 }) {
                // 上一集
                Button({ type: ButtonType.Circle }) {
                  Image($r('app.media.ic_skip_previous'))
                    .width(24)
                    .height(24)
                    .fillColor(Color.White)
                }
                .backgroundColor('rgba(0, 0, 0, 0.45)')
                .border({ width: 0.8, color: 'rgba(255, 255, 255, 0.2)' })
                .width(44)
                .height(44)
                .onClick(() => {
                  this.playPreviousEpisode();
                  this.resetControlsTimer();
                })

                // 中央大播放/暂停按键
                Button({ type: ButtonType.Circle }) {
                  Image(this.isPlaying ? $r('app.media.ic_pause') : $r('app.media.ic_play_arrow'))
                    .width(32)
                    .height(32)
                    .fillColor(Color.White)
                }
                .backgroundColor('rgba(25, 28, 40, 0.75)')
                .border({ width: 1.2, color: 'rgba(255, 255, 255, 0.35)' })
                .width(58)
                .height(58)
                .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.5)' })
                .onClick(() => {
                  this.togglePlayPause();
                  this.resetControlsTimer();
                })

                // 下一集
                Button({ type: ButtonType.Circle }) {
                  Image($r('app.media.ic_skip_next'))
                    .width(24)
                    .height(24)
                    .fillColor(Color.White)
                }
                .backgroundColor('rgba(0, 0, 0, 0.45)')
                .border({ width: 0.8, color: 'rgba(255, 255, 255, 0.2)' })
                .width(44)
                .height(44)
                .onClick(() => {
                  this.playNextEpisode();
                  this.resetControlsTimer();
                })
              }
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
            }

            Blank()

            // C. 底部工具栏与进度条 (PlayerBottomBarView: 右侧清晰工具栏 + 进度滑块)
            Column({ space: 4 }) {
              // 工具栏行：倍速 + 全屏按钮（放在右侧工具区，彻底避免顶部被挤爆截断）
              Row({ space: 10 }) {
                Blank()

                // 倍速切换胶囊
                Button(`${this.speed}x`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .backgroundColor('rgba(0, 0, 0, 0.45)')
                  .border({ width: 0.8, color: 'rgba(255, 255, 255, 0.2)' })
                  .height(30)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(15)
                  .onClick(() => {
                    this.cycleSpeed();
                  })

                // 全屏切换按钮：标准矢量图标，绝不截断
                Button({ type: ButtonType.Circle }) {
                  Image(this.isFullscreen ? $r('app.media.ic_fullscreen_exit') : $r('app.media.ic_fullscreen'))
                    .width(20)
                    .height(20)
                    .fillColor(Color.White)
                }
                .backgroundColor('rgba(0, 0, 0, 0.45)')
                .border({ width: 0.8, color: 'rgba(255, 255, 255, 0.2)' })
                .width(34)
                .height(34)
                .onClick(() => {
                  this.isFullscreen = !this.isFullscreen;
                  this.resetControlsTimer();
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16 })

              // 进度时间行
              Row({ space: 8 }) {
                Text(this.formatTime(this.currentPosition))
                  .fontSize(11)
                  .fontColor(AppColors.textPrimary)
                  .width(40)
                  .textAlign(TextAlign.End)

                Slider({
                  value: this.currentPosition,
                  min: 0,
                  max: Math.max(1, this.duration),
                  style: SliderStyle.OutSet
                })
                  .blockColor(AppColors.hongguoRed)
                  .trackColor('rgba(255, 255, 255, 0.25)')
                  .selectedColor(AppColors.hongguoRed)
                  .layoutWeight(1)
                  .onChange((value: number, mode: SliderChangeMode) => {
                    if (mode === SliderChangeMode.End) {
                      this.playerController.seek(value);
                      this.resetControlsTimer();
                    }
                  })

                Text(this.formatTime(this.duration))
                  .fontSize(11)
                  .fontColor(AppColors.textSecondary)
                  .width(40)
              }
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 8 })
            }
            .width('100%')
            .backgroundColor('rgba(0, 0, 0, 0.45)')
          }
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height(this.isFullscreen ? '100%' : 260)
      .backgroundColor(Color.Black)

      // 2. 移动端半屏面板（选集、简介交互，严谨对齐 Flutter PlayerMobilePanelView）
      if (!this.isFullscreen) {
        Column() {
          // Tab 切换导航条：选集 / 简介 / 右侧追剧按钮
          Row() {
            // Tab 0: 选集
            Column() {
              Text(`选集${this.detail?.episodeCount ? ` (共${this.detail.episodeCount}集)` : ''}`)
                .fontSize(14)
                .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.currentTab === 0 ? AppColors.textPrimary : AppColors.textSecondary)
              if (this.currentTab === 0) {
                Column()
                  .width(24)
                  .height(3)
                  .backgroundColor(AppColors.hongguoRed)
                  .borderRadius(1.5)
                  .margin({ top: 4 })
              }
            }
            .layoutWeight(1)
            .onClick(() => {
              this.currentTab = 0;
            })

            // Tab 1: 简介
            Column() {
              Text('简介')
                .fontSize(14)
                .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.currentTab === 1 ? AppColors.textPrimary : AppColors.textSecondary)
              if (this.currentTab === 1) {
                Column()
                  .width(24)
                  .height(3)
                  .backgroundColor(AppColors.hongguoRed)
                  .borderRadius(1.5)
                  .margin({ top: 4 })
              }
            }
            .layoutWeight(1)
            .onClick(() => {
              this.currentTab = 1;
            })

            // 追剧状态按钮
            Button(this.isFavorite ? '❤️ 已追剧' : '🤍 追剧')
              .fontSize(12)
              .fontColor(this.isFavorite ? AppColors.hongguoRed : AppColors.textPrimary)
              .backgroundColor(this.isFavorite ? 'rgba(255, 36, 66, 0.15)' : AppColors.bgElevated)
              .height(30)
              .borderRadius(15)
              .padding({ left: 12, right: 12 })
              .onClick(() => {
                this.toggleFavorite();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 8 })
          .backgroundColor(AppColors.bgDark)

          // 内容区
          if (this.currentTab === 0) {
            // 选集列表网格 (5列网格，当前播放集高亮为红果红 #FF2442)
            if (this.detail && this.detail.episodes.length > 0) {
              Grid() {
                ForEach(this.detail.episodes, (ep: EpisodeInfo) => {
                  GridItem() {
                    Button(`${ep.index}`)
                      .fontSize(13)
                      .fontWeight(this.currentEpisodeIndex === ep.index ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(this.currentEpisodeIndex === ep.index ? Color.White : AppColors.textPrimary)
                      .backgroundColor(this.currentEpisodeIndex === ep.index ? AppColors.hongguoRed : AppColors.bgCard)
                      .width('100%')
                      .height(44)
                      .borderRadius(AppDimensions.radiusSm)
                      .onClick(() => {
                        this.startPlayback(ep.index);
                      })
                  }
                })
              }
              .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
              .columnsGap(8)
              .rowsGap(8)
              .padding({ left: 16, right: 16, top: 8, bottom: 16 })
              .layoutWeight(1)
            } else {
              Column() {
                Text('正在获取短剧分集列表...')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            }
          } else {
            // 简介内容 (海报缩略图、多维元信息、剧情简介全文)
            Scroll() {
              Column({ space: 14 }) {
                Row({ space: 12 }) {
                  Image(this.coverUrl)
                    .width(72)
                    .height(96)
                    .borderRadius(AppDimensions.radiusSm)
                    .objectFit(ImageFit.Cover)
                    .backgroundColor(AppColors.bgCard)

                  Column({ space: 6 }) {
                    Text(this.dramaTitle)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(AppColors.textPrimary)
                    Text(this.detail?.remarks || '连载中')
                      .fontSize(12)
                      .fontColor(AppColors.hongguoGold)
                    Text(`共 ${this.detail?.episodeCount || 0} 集`)
                      .fontSize(12)
                      .fontColor(AppColors.textSecondary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }

                Text('剧情简介')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.textPrimary)

                Text(this.detail?.intro || '暂无详细简介。')
                  .fontSize(13)
                  .fontColor(AppColors.textSecondary)
                  .lineHeight(20)
              }
              .padding(16)
              .alignItems(HorizontalAlign.Start)
            }
            .layoutWeight(1)
            .width('100%')
          }
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(AppColors.bgDark)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
