import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import hilog from '@ohos.hilog';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { DramaItem, DramaDetail, EpisodeInfo } from '../../models/Drama';
import { PlaybackState } from '../../models/Episode';
import { PlayerController } from '../../core/player/PlayerController';
import { CoreEngine } from '../../core/engine/CoreEngine';
import { LocalStore } from '../../core/store/LocalStore';

const TAG = 'VideoFeedPage';
const DOMAIN = 0x0000;

@Entry
@Component
export struct VideoFeedPage {
  @State feedItems: DramaItem[] = [];
  @State currentIndex: number = 0;
  @State isLoading: boolean = true;
  @State isBuffering: boolean = false;
  @State isPlaying: boolean = false;
  @State videoRatio: number = 9 / 16;
  @State progressMs: number = 0;
  @State durationMs: number = 0;
  @State favoritedMap: Record<string, boolean> = {};
  @State showPauseIcon: boolean = false;

  private swiperController: SwiperController = new SwiperController();
  private playerController: PlayerController = new PlayerController();
  private xComponentController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private currentPlayingDramaId: string = '';

  aboutToAppear(): void {
    this.initPlayer();
    this.loadFeed();
  }

  aboutToDisappear(): void {
    this.playerController.release();
  }

  initPlayer(): void {
    this.playerController.setListener((state: PlaybackState) => {
      this.isPlaying = state.isPlaying;
      this.isBuffering = state.isBuffering;
      this.progressMs = state.currentPosition;
      this.durationMs = state.duration;
      if (state.aspectRatio && state.aspectRatio > 0) {
        this.videoRatio = state.aspectRatio;
      }
    });
  }

  async loadFeed(): Promise<void> {
    this.isLoading = true;
    try {
      this.feedItems = await CoreEngine.getInstance().getFeedDramas(1);
      for (const item of this.feedItems) {
        const fav = await LocalStore.getInstance().isFavorite(item.id);
        this.favoritedMap[item.id] = fav;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadFeed error: %{public}s', JSON.stringify(e));
    }
    this.isLoading = false;
    if (this.surfaceId && this.feedItems.length > 0) {
      this.playItemAtIndex(this.currentIndex);
    }
  }

  async playItemAtIndex(index: number): Promise<void> {
    if (index < 0 || index >= this.feedItems.length) return;
    const drama = this.feedItems[index];
    if (this.currentPlayingDramaId === drama.id && this.isPlaying) {
      return;
    }
    this.currentPlayingDramaId = drama.id;
    this.isBuffering = true;
    this.showPauseIcon = false;

    try {
      hilog.info(DOMAIN, TAG, 'Auto playing feed drama: %{public}s (%{public}s)', drama.title, drama.id);
      const detail: DramaDetail | null = await CoreEngine.getInstance().getDramaDetail(drama.id);
      if (!detail || detail.episodes.length === 0) {
        this.isBuffering = false;
        return;
      }
      const targetEp = detail.episodes[0];
      const playResult = await CoreEngine.getInstance().resolvePlayback(targetEp.flag ?? 'hongguo', targetEp.rawUrl);
      if (playResult && playResult.url) {
        await this.playerController.loadMedia(drama.id, drama.title, 1, playResult);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'playItemAtIndex error: %{public}s', JSON.stringify(e));
      this.isBuffering = false;
    }
  }

  onSwiperChange(index: number): void {
    this.currentIndex = index;
    this.playItemAtIndex(index);
  }

  togglePlayPause(): void {
    if (this.isPlaying) {
      this.playerController.pause();
      this.showPauseIcon = true;
    } else {
      this.playerController.play();
      this.showPauseIcon = false;
    }
  }

  async toggleFavorite(drama: DramaItem): Promise<void> {
    const nextState = await LocalStore.getInstance().toggleFavorite(drama);
    this.favoritedMap[drama.id] = nextState;
    promptAction.showToast({
      message: nextState ? '已加入追剧列表' : '已取消追剧'
    });
  }

  openDramaDetail(drama: DramaItem): void {
    this.playerController.pause();
    router.pushUrl({
      url: 'pages/detail/DramaDetailPage',
      params: {
        dramaId: drama.id,
        dramaTitle: drama.title,
        coverUrl: drama.coverUrl
      }
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isLoading && this.feedItems.length === 0) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(AppColors.hongguoRed)
          Text('正在加载精选短剧视频...')
            .fontSize(13)
            .fontColor(AppColors.textSecondary)
        }
        .justifyContent(FlexAlign.Center)
      } else {
        // 核心：全屏原生垂直滑动 Swiper，直接播放视频
        Swiper(this.swiperController) {
          ForEach(this.feedItems, (drama: DramaItem, index: number) => {
            Stack({ alignContent: Alignment.Center }) {
              // 黑色底衬，防拉伸居中容器
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor(Color.Black)

              if (this.currentIndex === index) {
                // 当前活动项：真实 XComponent 视频渲染组件（防拉伸，保持比例居中）
                Stack({ alignContent: Alignment.Center }) {
                  XComponent({
                    id: 'feedPlayerSurface',
                    type: 'surface',
                    controller: this.xComponentController
                  })
                    .onLoad(() => {
                      this.surfaceId = this.xComponentController.getXComponentSurfaceId();
                      hilog.info(DOMAIN, TAG, 'XComponent loaded, surfaceId: %{public}s', this.surfaceId);
                      this.playerController.setSurfaceId(this.surfaceId);
                      this.playItemAtIndex(this.currentIndex);
                    })
                    .aspectRatio(this.videoRatio > 0 ? this.videoRatio : 9 / 16)
                    .width('100%')
                    .backgroundColor(Color.Black)
                }
                .width('100%')
                .height('100%')
                .onClick(() => {
                  this.togglePlayPause();
                })
              } else {
                // 非活动项：显示原比例封面占位
                Stack({ alignContent: Alignment.Center }) {
                  Image(drama.coverUrl)
                    .aspectRatio(9 / 16)
                    .width('100%')
                    .objectFit(ImageFit.Contain)
                }
                .width('100%')
                .height('100%')
              }

              // 缓冲加载状态指示
              if (this.currentIndex === index && this.isBuffering) {
                LoadingProgress()
                  .width(44)
                  .height(44)
                  .color(AppColors.hongguoRed)
              }

              // 暂停居中大图标
              if (this.currentIndex === index && this.showPauseIcon) {
                Button('▶')
                  .fontSize(32)
                  .fontColor(Color.White)
                  .backgroundColor('rgba(0,0,0,0.5)')
                  .width(64)
                  .height(64)
                  .borderRadius(32)
                  .onClick(() => {
                    this.togglePlayPause();
                  })
              }

              // 顶部精选推荐与上滑换剧提示
              Column() {
                Row() {
                  Text('推荐')
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)

                  Blank()

                  Text('上滑换剧')
                    .fontSize(12)
                    .fontColor('rgba(255,255,255,0.7)')
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 38, bottom: 8 })

                Blank()

                // 底部剧名、选集与查看全集覆盖层 (对齐 Flutter 推荐流)
                Row() {
                  Column({ space: 6 }) {
                    Text(drama.title)
                      .fontSize(17)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(drama.remarks ? `第 1 集 · ${drama.remarks}` : '第 1 集')
                      .fontSize(13)
                      .fontColor('rgba(255,255,255,0.85)')

                    Button('查看全集 >')
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                      .backgroundColor('rgba(255, 255, 255, 0.22)')
                      .borderRadius(14)
                      .height(28)
                      .padding({ left: 12, right: 12 })
                      .margin({ top: 4 })
                      .onClick(() => {
                        this.openDramaDetail(drama);
                      })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  // 右侧追剧浮动大图标
                  Column({ space: 16 }) {
                    Column({ space: 4 }) {
                      Button(this.favoritedMap[drama.id] ? '❤️' : '🤍')
                        .fontSize(22)
                        .backgroundColor('rgba(0,0,0,0.45)')
                        .width(46)
                        .height(46)
                        .borderRadius(23)
                        .onClick(() => {
                          this.toggleFavorite(drama);
                        })

                      Text(this.favoritedMap[drama.id] ? '已追' : '追剧')
                        .fontSize(11)
                        .fontColor(Color.White)
                    }

                    Column({ space: 4 }) {
                      Button('📑')
                        .fontSize(20)
                        .backgroundColor('rgba(0,0,0,0.45)')
                        .width(46)
                        .height(46)
                        .borderRadius(23)
                        .onClick(() => {
                          this.openDramaDetail(drama);
                        })

                      Text('全集')
                        .fontSize(11)
                        .fontColor(Color.White)
                    }
                  }
                  .alignItems(HorizontalAlign.Center)
                  .padding({ left: 12 })
                }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 20 })

                // 底部纤细播放进度条
                if (this.durationMs > 0) {
                  Progress({
                    value: this.progressMs,
                    total: this.durationMs,
                    type: ProgressType.Linear
                  })
                    .color(AppColors.hongguoRed)
                    .backgroundColor('rgba(255,255,255,0.2)')
                    .width('100%')
                    .height(2)
                }
              }
              .width('100%')
              .height('100%')
              .hitTestBehavior(HitTestMode.Transparent)
            }
            .width('100%')
            .height('100%')
          })
        }
        .vertical(true)
        .indicator(false)
        .loop(false)
        .width('100%')
        .height('100%')
        .onChange((index: number) => {
          this.onSwiperChange(index);
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
