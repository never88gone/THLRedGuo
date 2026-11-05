import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { DramaItem } from '../../models/Drama';
import { CoreEngine } from '../../core/engine/CoreEngine';
import { LocalStore } from '../../core/store/LocalStore';

@Entry
@Component
export struct VideoFeedPage {
  @State feedItems: DramaItem[] = [];
  @State currentIndex: number = 0;
  @State isLoading: boolean = true;
  @State favoritedMap: Record<string, boolean> = {};

  private swiperController: SwiperController = new SwiperController();

  aboutToAppear(): void {
    this.loadFeed();
  }

  async loadFeed(): Promise<void> {
    this.isLoading = true;
    try {
      this.feedItems = await CoreEngine.getInstance().getFeedDramas(1);

      // 初始化收藏状态
      for (const item of this.feedItems) {
        const fav = await LocalStore.getInstance().isFavorite(item.id);
        this.favoritedMap[item.id] = fav;
      }
    } catch (e) {
      console.error('Failed to load feed dramas: ' + JSON.stringify(e));
    }
    this.isLoading = false;
  }

  async toggleLike(drama: DramaItem): Promise<void> {
    const nextState = await LocalStore.getInstance().toggleFavorite(drama);
    this.favoritedMap[drama.id] = nextState;
    promptAction.showToast({
      message: nextState ? '已加入追剧列表' : '已取消追剧'
    });
  }

  openPlayer(drama: DramaItem): void {
    router.pushUrl({
      url: 'pages/player/PlayerPage',
      params: {
        dramaId: drama.id,
        dramaTitle: drama.title,
        coverUrl: drama.coverUrl,
        episodeIndex: 1
      }
    });
  }

  openDetail(drama: DramaItem): void {
    router.pushUrl({
      url: 'pages/detail/DramaDetailPage',
      params: {
        dramaId: drama.id,
        dramaTitle: drama.title
      }
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isLoading) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(44)
            .height(44)
            .color(AppColors.hongguoRed)
          Text('正在加载短剧推荐流...')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
      } else if (this.feedItems.length > 0) {
        Swiper(this.swiperController) {
          ForEach(this.feedItems, (drama: DramaItem, index: number) => {
            Stack({ alignContent: Alignment.Bottom }) {
              // 沉浸式全屏封面与毛玻璃暗色氛围底图
              Image(drama.coverUrl)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)

              // 渐变蒙层保证文字可读性
              Column()
                .width('100%')
                .height('100%')
                .linearGradient({
                  direction: GradientDirection.Bottom,
                  colors: [
                    ['rgba(0, 0, 0, 0.25)', 0.0],
                    ['rgba(0, 0, 0, 0.1)', 0.4],
                    ['rgba(0, 0, 0, 0.85)', 1.0]
                  ]
                })

              // 右侧快捷浮动操作条
              Column({ space: 20 }) {
                // 追剧/点赞
                Column({ space: 4 }) {
                  Button(this.favoritedMap[drama.id] ? '❤️' : '🤍')
                    .fontSize(24)
                    .backgroundColor('rgba(0, 0, 0, 0.45)')
                    .width(48)
                    .height(48)
                    .borderRadius(24)
                    .onClick(() => {
                      this.toggleLike(drama);
                    })

                  Text(this.favoritedMap[drama.id] ? '已追' : '追剧')
                    .fontSize(11)
                    .fontColor(AppColors.textPrimary)
                }

                // 剧集详情
                Column({ space: 4 }) {
                  Button('📖')
                    .fontSize(22)
                    .backgroundColor('rgba(0, 0, 0, 0.45)')
                    .width(48)
                    .height(48)
                    .borderRadius(24)
                    .onClick(() => {
                      this.openDetail(drama);
                    })

                  Text('选集')
                    .fontSize(11)
                    .fontColor(AppColors.textPrimary)
                }

                // 播放
                Column({ space: 4 }) {
                  Button('▶')
                    .fontSize(20)
                    .backgroundColor(AppColors.hongguoRed)
                    .width(48)
                    .height(48)
                    .borderRadius(24)
                    .onClick(() => {
                      this.openPlayer(drama);
                    })

                  Text('播放')
                    .fontSize(11)
                    .fontColor(AppColors.textPrimary)
                }
              }
              .position({ x: '82%', y: '50%' })

              // 底部短剧信息与开播快捷入口
              Column({ space: 10 }) {
                Row({ space: 6 }) {
                  Text('@热剧推荐')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(AppColors.hongguoGold)

                  if (drama.remarks) {
                    Text(drama.remarks)
                      .fontSize(11)
                      .fontColor(AppColors.textPrimary)
                      .backgroundColor('rgba(255, 255, 255, 0.2)')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(4)
                  }
                }

                Text(drama.title)
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.textPrimary)
                  .maxLines(2)

                // 快捷进入全屏播放栏
                Row() {
                  Button('▶ 立即开始沉浸播放')
                    .width('100%')
                    .height(42)
                    .backgroundColor(AppColors.hongguoRed)
                    .fontColor(AppColors.textPrimary)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .borderRadius(21)
                    .onClick(() => {
                      this.openPlayer(drama);
                    })
                }
                .width('100%')
                .margin({ top: 4 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 16, right: 90, bottom: 28 })
            }
            .width('100%')
            .height('100%')
          })
        }
        .vertical(true)
        .loop(true)
        .indicator(false)
        .onChange((index: number) => {
          this.currentIndex = index;
        })
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
