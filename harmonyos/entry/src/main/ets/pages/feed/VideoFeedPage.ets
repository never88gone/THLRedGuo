import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import hilog from '@ohos.hilog';
import { AppColors } from '../../common/AppColors';
import { DramaItem, DramaDetail } from '../../models/Drama';
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
  @State isLoadingMore: boolean = false;
  @State hasMore: boolean = true;
  @State isBuffering: boolean = false;
  @State isPlaying: boolean = false;
  @State videoRatio: number = 9 / 16;
  @State progressMs: number = 0;
  @State durationMs: number = 0;
  @State favoritedMap: Record<string, boolean> = {};
  @State showPauseIcon: boolean = false;
  @State danmakuEnabled: boolean = true;

  private swiperController: SwiperController = new SwiperController();
  private playerController: PlayerController = new PlayerController();
  private xComponentController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private currentPlayingDramaId: string = '';
  private feedPage: number = 1;

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

    this.playerController.setOnCompleted(() => {
      this.playNextVideo();
    });
  }

  async loadFeed(): Promise<void> {
    this.isLoading = true;
    this.feedPage = 1;
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

  async loadMoreFeed(): Promise<void> {
    if (this.isLoadingMore || !this.hasMore) return;
    this.isLoadingMore = true;
    try {
      this.feedPage += 1;
      const newItems = await CoreEngine.getInstance().getFeedDramas(this.feedPage);
      if (newItems && newItems.length > 0) {
        for (const item of newItems) {
          const fav = await LocalStore.getInstance().isFavorite(item.id);
          this.favoritedMap[item.id] = fav;
        }
        this.feedItems.push(...newItems);
        if (this.currentIndex + 1 < this.feedItems.length) {
          this.swiperController.showNext();
        }
      } else {
        this.hasMore = false;
        if (this.feedItems.length > 0) {
          this.currentIndex = 0;
          this.swiperController.changeIndex(0, true);
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadMoreFeed error: %{public}s', JSON.stringify(e));
    } finally {
      this.isLoadingMore = false;
    }
  }

  playNextVideo(): void {
    hilog.info(DOMAIN, TAG, 'Video playback completed in feed. currentIndex: %{public}d, total: %{public}d', this.currentIndex, this.feedItems.length);
    const nextIndex = this.currentIndex + 1;
    if (nextIndex < this.feedItems.length) {
      this.swiperController.showNext();
      setTimeout(() => {
        if (this.currentIndex !== nextIndex) {
          this.currentIndex = nextIndex;
          this.playItemAtIndex(nextIndex);
        }
      }, 350);
    } else {
      this.loadMoreFeed();
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
    this.progressMs = 0;
    this.durationMs = 0;

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
    if (index >= this.feedItems.length - 2 && !this.isLoadingMore && this.hasMore) {
      this.loadMoreFeed();
    }
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
        Swiper(this.swiperController) {
          ForEach(this.feedItems, (drama: DramaItem, index: number) => {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor(AppColors.black)

              if (this.currentIndex === index) {
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
                    .backgroundColor(AppColors.black)
                }
                .width('100%')
                .height('100%')
                .onClick(() => {
                  this.togglePlayPause();
                })
              } else {
                Stack({ alignContent: Alignment.Center }) {
                  Image(drama.coverUrl)
                    .aspectRatio(9 / 16)
                    .width('100%')
                    .objectFit(ImageFit.Contain)
                }
                .width('100%')
                .height('100%')
              }

              if (this.currentIndex === index && this.isBuffering) {
                LoadingProgress()
                  .width(44)
                  .height(44)
                  .color(AppColors.hongguoRed)
              }

              if (this.currentIndex === index && this.showPauseIcon) {
                Button('▶')
                  .fontSize(32)
                  .fontColor(AppColors.white)
                  .backgroundColor(AppColors.maskDark50)
                  .width(64)
                  .height(64)
                  .borderRadius(32)
                  .onClick(() => {
                    this.togglePlayPause();
                  })
              }

              Stack({ alignContent: Alignment.Bottom }) {
                Column()
                  .width('100%')
                  .height(320)
                  .linearGradient({
                    direction: GradientDirection.Bottom,
                    colors: [[AppColors.transparent, 0.0], [AppColors.maskDark80, 1.0]]
                  })
                  .hitTestBehavior(HitTestMode.None)

                Column() {
                  Row() {
                    Text('推荐')
                      .fontSize(20)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(AppColors.white)

                    Blank()

                    Text('上滑换剧')
                      .fontSize(12)
                      .fontColor(AppColors.whiteAlpha70)
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 38, bottom: 8 })

                  Blank()

                  Row() {
                    Column({ space: 8 }) {
                      Text(drama.title)
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(AppColors.white)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })

                      Row({ space: 6 }) {
                        Image($r('app.media.ic_play_circle_outline'))
                          .width(18)
                          .height(18)
                          .fillColor(AppColors.white)
                        Text(drama.remarks ? `第 1 集 · ${drama.remarks}` : '第 1 集')
                          .fontSize(14)
                          .fontColor(AppColors.white)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .padding({ top: 2, bottom: 2 })
                      .onClick(() => {
                        this.openDramaDetail(drama);
                      })

                      if (drama.intro && drama.intro.length > 0) {
                        Text(drama.intro)
                          .fontSize(13)
                          .fontColor(AppColors.whiteAlpha70)
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .lineHeight(18)
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Column({ space: 12 }) {
                      Button({ type: ButtonType.Circle }) {
                        Image(this.favoritedMap[drama.id] ? $r('app.media.ic_favorite') : $r('app.media.ic_favorite_border'))
                          .width(26)
                          .height(26)
                          .fillColor(this.favoritedMap[drama.id] ? AppColors.hongguoRed : AppColors.white)
                      }
                      .width(48)
                      .height(48)
                      .backgroundColor(AppColors.feedActionBg)
                      .onClick(() => {
                        this.toggleFavorite(drama);
                      })

                      Button({ type: ButtonType.Circle }) {
                        Image($r('app.media.ic_episodes'))
                          .width(26)
                          .height(26)
                          .fillColor(AppColors.white)
                      }
                      .width(48)
                      .height(48)
                      .backgroundColor(AppColors.feedActionBg)
                      .onClick(() => {
                        this.openDramaDetail(drama);
                      })

                      Button({ type: ButtonType.Circle }) {
                        Image($r('app.media.ic_subtitles'))
                          .width(26)
                          .height(26)
                          .fillColor(this.danmakuEnabled ? AppColors.hongguoRed : AppColors.white)
                      }
                      .width(48)
                      .height(48)
                      .backgroundColor(AppColors.feedActionBg)
                      .onClick(() => {
                        this.danmakuEnabled = !this.danmakuEnabled;
                        promptAction.showToast({
                          message: this.danmakuEnabled ? '弹幕已开启' : '弹幕已关闭'
                        });
                      })

                      Button({ type: ButtonType.Circle }) {
                        Image($r('app.media.ic_info_outline'))
                          .width(26)
                          .height(26)
                          .fillColor(AppColors.white)
                      }
                      .width(48)
                      .height(48)
                      .backgroundColor(AppColors.feedActionBg)
                      .onClick(() => {
                        this.openDramaDetail(drama);
                      })

                      Button({ type: ButtonType.Circle }) {
                        Image($r('app.media.ic_tune'))
                          .width(26)
                          .height(26)
                          .fillColor(AppColors.white)
                      }
                      .width(48)
                      .height(48)
                      .backgroundColor(AppColors.feedActionBg)
                      .onClick(() => {
                        promptAction.showToast({
                          message: '当前采用高清智能硬件解码'
                        });
                      })
                    }
                    .alignItems(HorizontalAlign.Center)
                    .padding({ left: 12 })
                  }
                  .alignItems(VerticalAlign.Bottom)
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 12 })

                  if (this.durationMs > 0) {
                    Progress({
                      value: this.progressMs,
                      total: this.durationMs,
                      type: ProgressType.Linear
                    })
                      .color(AppColors.hongguoRed)
                      .backgroundColor(AppColors.whiteAlpha20)
                      .width('100%')
                      .height(2)
                  }
                }
                .width('100%')
                .height('100%')
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
    .backgroundColor(AppColors.black)
  }
}
