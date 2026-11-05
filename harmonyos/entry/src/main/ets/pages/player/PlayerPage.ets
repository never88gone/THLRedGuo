import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import hilog from '@ohos.hilog';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { DramaDetail, EpisodeInfo } from '../../models/Drama';
import { PlaybackState } from '../../models/Episode';
import { PlayerController } from '../../core/player/PlayerController';
import { CoreEngine } from '../../core/engine/CoreEngine';
import { LocalStore } from '../../core/store/LocalStore';

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
  @State showControls: boolean = true;
  @State showEpisodeSheet: boolean = false;

  private playerController: PlayerController = new PlayerController();
  private xComponentController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private controlsTimer: number = -1;

  aboutToAppear(): void {
    try {
      hilog.info(0x0000, 'PlayerPage', 'PlayerPage aboutToAppear enter');
      const params = router.getParams() as Record<string, Object>;
      if (params) {
        this.dramaId = (params['dramaId'] as string) ?? '';
        this.dramaTitle = (params['dramaTitle'] as string) ?? '';
        this.currentEpisodeIndex = (params['episodeIndex'] as number) ?? 1;
        this.coverUrl = (params['coverUrl'] as string) ?? '';
        hilog.info(0x0000, 'PlayerPage', 'Params: dramaId=%{public}s, ep=%{public}d', this.dramaId, this.currentEpisodeIndex);
      }

      this.playerController.setListener((state: PlaybackState) => {
        this.isPlaying = state.isPlaying;
        this.isBuffering = state.isBuffering;
        this.currentPosition = state.currentPosition;
        this.duration = state.duration;
        this.speed = state.speed;

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
      this.resetControlsTimer();
    } catch (e) {
      hilog.error(0x0000, 'PlayerPage', 'aboutToAppear error: %{public}s', JSON.stringify(e));
    }
  }

  aboutToDisappear(): void {
    if (this.controlsTimer !== -1) {
      clearTimeout(this.controlsTimer);
    }
    this.playerController.release();
  }

  async loadDetail(): Promise<void> {
    if (this.dramaId) {
      this.detail = await CoreEngine.getInstance().getDramaDetail(this.dramaId);
      if (this.detail && !this.coverUrl) {
        this.coverUrl = this.detail.coverUrl;
      }
    }
  }

  async startPlayback(epIndex: number): Promise<void> {
    this.currentEpisodeIndex = epIndex;
    this.isBuffering = true;

    try {
      if (!this.detail) {
        await this.loadDetail();
      }

      const targetEp = this.detail?.episodes.find(e => e.index === epIndex);
      if (!targetEp) {
        promptAction.showToast({ message: '未找到选集资源' });
        this.isBuffering = false;
        return;
      }

      const playResult = await CoreEngine.getInstance().resolvePlayback(targetEp.flag ?? 'hongguo', targetEp.rawUrl);
      if (playResult && playResult.url) {
        await this.playerController.loadMedia(this.dramaId, this.dramaTitle, epIndex, playResult);
      } else {
        promptAction.showToast({ message: '视频源解析失败，正在重试...' });
        this.isBuffering = false;
      }
    } catch (e) {
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
    Stack({ alignContent: Alignment.Center }) {
      // 视频底层渲染组件
      XComponent({
        id: 'playerSurface',
        type: 'surface',
        controller: this.xComponentController
      })
        .onLoad(() => {
          try {
            this.surfaceId = this.xComponentController.getXComponentSurfaceId();
            hilog.info(0x0000, 'PlayerPage', 'XComponent onLoad, surfaceId: %{public}s', this.surfaceId);
            this.playerController.setSurfaceId(this.surfaceId);
            this.startPlayback(this.currentEpisodeIndex);
          } catch (e) {
            hilog.error(0x0000, 'PlayerPage', 'XComponent onLoad error: %{public}s', JSON.stringify(e));
          }
        })
        .width('100%')
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
            .width(48)
            .height(48)
            .color(AppColors.hongguoRed)
          Text('正在加载短剧视频...')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
      }

      // 控制面板覆盖层
      if (this.showControls) {
        Column() {
          // 顶部导航与剧名
          Row({ space: 10 }) {
            Button('< 返回')
              .fontSize(14)
              .fontColor(AppColors.textPrimary)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                router.back();
              })

            Column({ space: 2 }) {
              Text(this.dramaTitle || '播放中')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.textPrimary)
                .maxLines(1)
              Text(`第 ${this.currentEpisodeIndex} 集`)
                .fontSize(11)
                .fontColor(AppColors.textMuted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Blank()

            Button(`${this.speed}x`)
              .fontSize(12)
              .fontColor(AppColors.textPrimary)
              .backgroundColor('rgba(255,255,255,0.15)')
              .borderRadius(14)
              .height(28)
              .onClick(() => {
                this.cycleSpeed();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 38, bottom: 12 })
          .backgroundColor('rgba(0, 0, 0, 0.4)')

          Blank()

          // 中央播放/暂停悬浮大按钮
          Button(this.isPlaying ? '⏸' : '▶')
            .fontSize(28)
            .fontColor(AppColors.textPrimary)
            .backgroundColor('rgba(0, 0, 0, 0.5)')
            .width(64)
            .height(64)
            .borderRadius(32)
            .onClick(() => {
              this.togglePlayPause();
            })

          Blank()

          // 底部控制栏（进度条、时长、选集）
          Column({ space: 6 }) {
            Row({ space: 10 }) {
              Text(this.formatTime(this.currentPosition))
                .fontSize(11)
                .fontColor(AppColors.textSecondary)

              Slider({
                value: this.currentPosition,
                min: 0,
                max: Math.max(this.duration, 1),
                step: 1000,
                style: SliderStyle.OutSet
              })
                .blockColor(AppColors.hongguoRed)
                .trackColor('rgba(255,255,255,0.2)')
                .selectedColor(AppColors.hongguoRed)
                .layoutWeight(1)
                .onChange((value: number, mode: SliderChangeMode) => {
                  if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    this.playerController.seek(value);
                    this.resetControlsTimer();
                  }
                })

              Text(this.formatTime(this.duration))
                .fontSize(11)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')

            Row() {
              Blank()

              Button('选集')
                .fontSize(12)
                .fontColor(AppColors.textPrimary)
                .backgroundColor('rgba(255,255,255,0.15)')
                .borderRadius(14)
                .height(28)
                .onClick(() => {
                  this.showEpisodeSheet = true;
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20, top: 10 })
          .backgroundColor('rgba(0, 0, 0, 0.55)')
        }
        .width('100%')
        .height('100%')
      }

      // 底部选集抽屉
      if (this.showEpisodeSheet && this.detail) {
        Column() {
          Blank()
            .onClick(() => {
              this.showEpisodeSheet = false;
            })

          Column({ space: 12 }) {
            Row() {
              Text(`选集 (共 ${this.detail.episodes.length} 集)`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.textPrimary)

              Blank()

              Button('关闭')
                .fontSize(12)
                .fontColor(AppColors.textSecondary)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.showEpisodeSheet = false;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12 })

            Grid() {
              ForEach(this.detail.episodes, (ep: EpisodeInfo) => {
                GridItem() {
                  Button(`${ep.index}`)
                    .width('100%')
                    .height(40)
                    .fontSize(13)
                    .fontColor(ep.index === this.currentEpisodeIndex ? Color.White : AppColors.textPrimary)
                    .backgroundColor(ep.index === this.currentEpisodeIndex ? AppColors.hongguoRed : AppColors.bgCard)
                    .borderRadius(AppDimensions.radiusSm)
                    .onClick(() => {
                      this.showEpisodeSheet = false;
                      this.startPlayback(ep.index);
                    })
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
            .columnsGap(8)
            .rowsGap(8)
            .width('100%')
            .height(240)
            .padding({ left: 16, right: 16, bottom: 20 })
          }
          .width('100%')
          .backgroundColor(AppColors.bgCard)
          .borderRadius({ topLeft: 16, topRight: 16 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.4)')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
