import { AppColors } from '../../../common/AppColors';
import { AppDimensions } from '../../../common/AppDimensions';
import { DramaDetail, EpisodeInfo } from '../../../models/Drama';

@Component
export struct PlayerMobilePanelView {
  @Prop currentTab: number = 0;
  @Prop isFavorite: boolean = false;
  @Prop currentEpisodeIndex: number = 1;
  @Prop detail: DramaDetail | null = null;
  @Prop coverUrl: string = '';
  @Prop dramaTitle: string = '';

  onTabChange: (tab: number) => void = () => {};
  onToggleFavorite: () => void = () => {};
  onSelectEpisode: (epIndex: number) => void = () => {};

  build() {
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
          this.onTabChange(0);
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
          this.onTabChange(1);
        })

        // 追剧状态按钮
        Button(this.isFavorite ? '❤️ 已追剧' : '🤍 追剧')
          .fontSize(12)
          .fontColor(this.isFavorite ? AppColors.hongguoRed : AppColors.textPrimary)
          .backgroundColor(this.isFavorite ? AppColors.redAlpha15 : AppColors.bgElevated)
          .height(30)
          .borderRadius(15)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.onToggleFavorite();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .backgroundColor(AppColors.bgDark)

      // 内容区
      if (this.currentTab === 0) {
        // 选集列表网格 (5列网格，当前播放集高亮为红果红)
        if (this.detail && this.detail.episodes.length > 0) {
          Grid() {
            ForEach(this.detail.episodes, (ep: EpisodeInfo) => {
              GridItem() {
                Button(`${ep.index}`)
                  .fontSize(13)
                  .fontWeight(this.currentEpisodeIndex === ep.index ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.currentEpisodeIndex === ep.index ? AppColors.white : AppColors.textPrimary)
                  .backgroundColor(this.currentEpisodeIndex === ep.index ? AppColors.hongguoRed : AppColors.bgCard)
                  .width('100%')
                  .height(44)
                  .borderRadius(AppDimensions.radiusSm)
                  .onClick(() => {
                    this.onSelectEpisode(ep.index);
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
