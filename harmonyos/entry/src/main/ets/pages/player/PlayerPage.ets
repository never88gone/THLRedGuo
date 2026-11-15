import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import hilog from '@ohos.hilog';
import { AppColors } from '../../common/AppColors';
import { DramaDetail, DramaItem } from '../../models/Drama';
import { PlaybackState } from '../../models/Episode';
import { PlayerController } from '../../core/player/PlayerController';
import { CoreEngine } from '../../core/engine/CoreEngine';
import { LocalStore } from '../../core/store/LocalStore';
import { PlayerControlsView } from './components/PlayerControlsView';
import { PlayerMobilePanelView } from './components/PlayerMobilePanelView';

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
      // 1. 视频播放视口
      Stack({ alignContent: Alignment.Center }) {
        // 黑色底层背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppColors.black)

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
          .backgroundColor(AppColors.black)

        // 触摸透明覆盖层：点击切换控制栏显隐
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppColors.transparent)
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
              .width(42)
              .height(42)
              .color(AppColors.hongguoRed)
            Text('正在加载短剧视频...')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
          }
          .hitTestBehavior(HitTestMode.None)
        }

        // 播放控制浮层
        if (this.showControls) {
          PlayerControlsView({
            dramaTitle: this.dramaTitle,
            currentEpisodeIndex: this.currentEpisodeIndex,
            isPlaying: this.isPlaying,
            isBuffering: this.isBuffering,
            isFullscreen: this.isFullscreen,
            speed: this.speed,
            currentPosition: this.currentPosition,
            duration: this.duration,
            onBack: () => {
              if (this.isFullscreen) {
                this.isFullscreen = false;
              } else {
                router.back();
              }
            },
            onPrevious: () => {
              this.playPreviousEpisode();
              this.resetControlsTimer();
            },
            onTogglePlay: () => {
              this.togglePlayPause();
              this.resetControlsTimer();
            },
            onNext: () => {
              this.playNextEpisode();
              this.resetControlsTimer();
            },
            onCycleSpeed: () => {
              this.cycleSpeed();
            },
            onToggleFullscreen: () => {
              this.isFullscreen = !this.isFullscreen;
              this.resetControlsTimer();
            },
            onSeek: (value: number) => {
              this.playerController.seek(value);
              this.resetControlsTimer();
            }
          })
        }
      }
      .width('100%')
      .height(this.isFullscreen ? '100%' : 260)
      .backgroundColor(AppColors.black)

      // 2. 移动端半屏面板
      if (!this.isFullscreen) {
        PlayerMobilePanelView({
          currentTab: this.currentTab,
          isFavorite: this.isFavorite,
          currentEpisodeIndex: this.currentEpisodeIndex,
          detail: this.detail,
          coverUrl: this.coverUrl,
          dramaTitle: this.dramaTitle,
          onTabChange: (tab: number) => {
            this.currentTab = tab;
          },
          onToggleFavorite: () => {
            this.toggleFavorite();
          },
          onSelectEpisode: (epIndex: number) => {
            this.startPlayback(epIndex);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
