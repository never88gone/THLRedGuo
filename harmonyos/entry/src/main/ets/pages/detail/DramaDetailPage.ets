import router from '@ohos.router';
import hilog from '@ohos.hilog';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { DramaDetail, EpisodeInfo } from '../../models/Drama';
import { CoreEngine } from '../../core/engine/CoreEngine';
import { LocalStore } from '../../core/store/LocalStore';

@Entry
@Component
struct DramaDetailPage {
  @State dramaId: string = '';
  @State dramaTitle: string = '';
  @State detail: DramaDetail | null = null;
  @State isFavorited: boolean = false;
  @State isLoading: boolean = true;
  @State isIntroExpanded: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      this.dramaId = (params['dramaId'] as string) ?? '';
      this.dramaTitle = (params['dramaTitle'] as string) ?? '';
    }
    this.loadDetail();
  }

  async loadDetail(): Promise<void> {
    this.isLoading = true;
    if (this.dramaId) {
      this.detail = await CoreEngine.getInstance().getDramaDetail(this.dramaId);
      this.isFavorited = await LocalStore.getInstance().isFavorite(this.dramaId);
    }
    this.isLoading = false;
  }

  async toggleFavorite(): Promise<void> {
    if (this.detail) {
      this.isFavorited = await LocalStore.getInstance().toggleFavorite(this.detail);
    }
  }

  playEpisode(episodeIndex: number): void {
    if (!this.detail) return;
    try {
      router.pushUrl({
        url: 'pages/player/PlayerPage',
        params: {
          dramaId: this.detail.id,
          dramaTitle: this.detail.title,
          coverUrl: this.detail.coverUrl,
          episodeIndex: episodeIndex
        }
      }, (err) => {
        if (err) {
          hilog.error(0x0000, 'DramaDetailPage', 'router.pushUrl error: %{public}s', JSON.stringify(err));
        }
      });
    } catch (e) {
      hilog.error(0x0000, 'DramaDetailPage', 'playEpisode error: %{public}s', JSON.stringify(e));
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_arrow_back'))
            .width(22)
            .height(22)
            .fillColor(AppColors.textPrimary)
        }
        .backgroundColor(Color.Transparent)
        .width(40)
        .height(40)
        .onClick(() => {
          router.back();
        })

        Blank()

        Button(this.isFavorited ? '❤️ 已追剧' : '🤍 追剧')
          .fontSize(13)
          .fontColor(this.isFavorited ? AppColors.hongguoRed : AppColors.textPrimary)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusLg)
          .onClick(() => {
            this.toggleFavorite();
          })
      }
      .width('100%')
      .padding({ left: AppDimensions.paddingMd, right: AppDimensions.paddingMd, top: 38, bottom: 8 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(AppColors.hongguoRed)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.detail) {
        Scroll() {
          Column({ space: 16 }) {
            // 剧集头部概览卡片
            Row({ space: 14 }) {
              Image(this.detail.coverUrl)
                .width(110)
                .height(150)
                .borderRadius(AppDimensions.radiusMd)
                .objectFit(ImageFit.Cover)
                .backgroundColor(AppColors.bgCard)

              Column({ space: 8 }) {
                Text(this.detail.title)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.textPrimary)
                  .maxLines(2)

                if (this.detail.remarks) {
                  Text(this.detail.remarks)
                    .fontSize(12)
                    .fontColor(AppColors.hongguoGold)
                }

                Blank()

                // 主播放按钮
                Button('▶ 开始播放')
                  .width('100%')
                  .height(38)
                  .backgroundColor(AppColors.hongguoRed)
                  .fontColor(AppColors.textPrimary)
                  .borderRadius(AppDimensions.radiusLg)
                  .onClick(() => {
                    this.playEpisode(1);
                  })
              }
              .layoutWeight(1)
              .height(150)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')

            // 简介折叠区
            if (this.detail.intro) {
              Column({ space: 4 }) {
                Text('剧情简介')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.textPrimary)

                Text(this.detail.intro)
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
                  .maxLines(this.isIntroExpanded ? 10 : 2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .onClick(() => {
                    this.isIntroExpanded = !this.isIntroExpanded;
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(AppDimensions.paddingMd)
              .backgroundColor(AppColors.bgCard)
              .borderRadius(AppDimensions.radiusMd)
            }

            // 选集列表
            Column({ space: 10 }) {
              Row() {
                Text('选集')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.textPrimary)

                Blank()

                Text(`共 ${this.detail.episodes.length} 集`)
                  .fontSize(12)
                  .fontColor(AppColors.textMuted)
              }
              .width('100%')

              Grid() {
                ForEach(this.detail.episodes, (ep: EpisodeInfo) => {
                  GridItem() {
                    Button(`${ep.index}`)
                      .width('100%')
                      .height(44)
                      .fontSize(14)
                      .fontColor(AppColors.textPrimary)
                      .backgroundColor(AppColors.bgCard)
                      .borderRadius(AppDimensions.radiusSm)
                      .onClick(() => {
                        this.playEpisode(ep.index);
                      })
                  }
                })
              }
              .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
              .columnsGap(8)
              .rowsGap(8)
              .width('100%')
            }
            .width('100%')
          }
          .padding(AppDimensions.paddingLg)
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
