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
    }
    this.showControls = true;
    this.controlsTimer = setTimeout(() => {
      if (this.isPlaying) {
        this.showControls = false;
      }
    }, 4500);
  }

  build() {
    Column() {
      // 视频播放视口（无论半屏还是全屏，均保持真实视频宽高比，居中黑条填充，严禁拉伸）
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
          .onClick(() => {
            this.showControls = !this.showControls;
            if (this.showControls) {
              this.resetControlsTimer();
            }
          })

        // 缓冲加载状态
        if (this.isBuffering) {
          Column({ space: 8 }) {
            LoadingProgress()
              .width(44)
              .height(44)
              .color(AppColors.hongguoRed)
            Text('正在加载短剧视频...')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
          }
        }

        // 播放控制浮层
        if (this.showControls) {
          Column() {
            // 顶部导航栏
            Row({ space: 10 }) {
              Button('< 返回')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
                .backgroundColor(Color.Transparent)
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
                Text(`第 ${this.currentEpisodeIndex} 集`)
                  .fontSize(11)
                  .fontColor(AppColors.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Blank()

              // 倍速切换
              Button(`${this.speed}x`)
                .fontSize(12)
                .fontColor(AppColors.textPrimary)
                .backgroundColor('rgba(255,255,255,0.18)')
                .borderRadius(14)
                .height(28)
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  this.cycleSpeed();
                })

              // 全屏切换按钮
              Button(this.isFullscreen ? '🗗' : '⛶')
                .fontSize(15)
                .fontColor(AppColors.textPrimary)
                .backgroundColor('rgba(255,255,255,0.18)')
                .borderRadius(14)
                .width(36)
                .height(28)
                .onClick(() => {
                  this.isFullscreen = !this.isFullscreen;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 38, bottom: 10 })
            .backgroundColor('rgba(0, 0, 0, 0.45)')

            Blank()

            // 中央播放/暂停悬浮大按钮
            Button(this.isPlaying ? '⏸' : '▶')
              .fontSize(28)
              .fontColor(AppColors.textPrimary)
              .backgroundColor('rgba(0, 0, 0, 0.55)')
              .width(60)
              .height(60)
              .borderRadius(30)
              .onClick(() => {
                this.togglePlayPause();
              })

            Blank()

            // 底部控制条 (进度与时间)
            Row({ space: 8 }) {
              Text(this.formatTime(this.currentPosition))
                .fontSize(11)
                .fontColor(AppColors.textPrimary)
                .width(42)

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
                  }
                })

              Text(this.formatTime(this.duration))
                .fontSize(11)
                .fontColor(AppColors.textSecondary)
                .width(42)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 12, top: 8 })
            .backgroundColor('rgba(0, 0, 0, 0.45)')
          }
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height(this.isFullscreen ? '100%' : 260)
      .backgroundColor(Color.Black)

      // 移动端半屏面板（选集、简介交互，对齐 Flutter PlayerMobilePanelView）
      if (!this.isFullscreen) {
        Column() {
          // Tab 切换：选集 / 简介
          Row() {
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

            Button(this.isFavorite ? '❤️ 已追剧' : '🤍 追剧')
              .fontSize(12)
              .fontColor(this.isFavorite ? AppColors.hongguoRed : AppColors.textPrimary)
              .backgroundColor(this.isFavorite ? 'rgba(255,36,66,0.15)' : AppColors.bgElevated)
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
            // 选集列表网格
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
            // 简介内容
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
