import router from '@ohos.router';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { RankingBoard, RankingItem } from '../../models/Ranking';
import { CoreEngine } from '../../core/engine/CoreEngine';

@Entry
@Component
export struct RankingsPage {
  @State boards: RankingBoard[] = [];
  @State selectedBoardIndex: number = 0;
  @State isLoading: boolean = true;

  aboutToAppear(): void {
    this.loadBoards();
  }

  async loadBoards(): Promise<void> {
    this.isLoading = true;
    try {
      this.boards = await CoreEngine.getInstance().getRankingBoards();
    } catch (e) {
      console.error('Failed to load ranking boards: ' + JSON.stringify(e));
    }
    this.isLoading = false;
  }

  getRankColor(rank: number): ResourceColor {
    if (rank === 1) return '#FFD700'; // 金
    if (rank === 2) return '#C0C0C0'; // 银
    if (rank === 3) return '#CD7F32'; // 铜
    return AppColors.textMuted;
  }

  openDramaDetail(item: RankingItem): void {
    router.pushUrl({
      url: 'pages/detail/DramaDetailPage',
      params: {
        dramaId: item.dramaId,
        dramaTitle: item.title
      }
    });
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('短剧排行榜')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)

        Blank()

        Button('🔍')
          .fontSize(16)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            router.pushUrl({ url: 'pages/search/SearchPage' });
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 榜单切换切换标签
      if (this.boards.length > 0) {
        Row({ space: 8 }) {
          ForEach(this.boards, (board: RankingBoard, index: number) => {
            Button(board.title)
              .fontSize(13)
              .fontWeight(this.selectedBoardIndex === index ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.selectedBoardIndex === index ? Color.White : AppColors.textSecondary)
              .backgroundColor(this.selectedBoardIndex === index ? AppColors.hongguoRed : AppColors.bgCard)
              .height(32)
              .padding({ left: 14, right: 14 })
              .borderRadius(16)
              .onClick(() => {
                this.selectedBoardIndex = index;
              })
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 8 })
      }

      if (this.isLoading) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(44)
            .height(44)
            .color(AppColors.hongguoRed)
          Text('正在加载短剧榜单...')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.boards.length > 0) {
        // 当前选中的榜单
        List({ space: 12 }) {
          // 榜单副标题与更新说明
          ListItem() {
            Row() {
              Text(this.boards[this.selectedBoardIndex].subTitle)
                .fontSize(12)
                .fontColor(AppColors.textMuted)

              Blank()

              Text('每日实时更新')
                .fontSize(11)
                .fontColor(AppColors.hongguoGold)
            }
            .width('100%')
            .padding({ left: 4, right: 4, top: 4, bottom: 4 })
          }

          // 榜单排行列表项
          ForEach(this.boards[this.selectedBoardIndex].items, (item: RankingItem) => {
            ListItem() {
              Row({ space: 12 }) {
                // 排名数字序号
                Text(`${item.rank}`)
                  .fontSize(item.rank <= 3 ? 18 : 14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.getRankColor(item.rank))
                  .width(28)
                  .textAlign(TextAlign.Center)

                // 封面
                Image(item.coverUrl)
                  .width(64)
                  .height(86)
                  .borderRadius(AppDimensions.radiusSm)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor(AppColors.bgCard)

                // 信息详情
                Column({ space: 6 }) {
                  Text(item.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(AppColors.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  if (item.remarks) {
                    Text(item.remarks)
                      .fontSize(11)
                      .fontColor(AppColors.textSecondary)
                      .maxLines(1)
                  }

                  Blank()

                  Row({ space: 4 }) {
                    Text('🔥')
                      .fontSize(11)
                    Text(item.heat)
                      .fontSize(11)
                      .fontColor(AppColors.hongguoRed)
                  }
                }
                .layoutWeight(1)
                .height(86)
                .alignItems(HorizontalAlign.Start)

                // 立即观看小按钮
                Button('追剧')
                  .fontSize(11)
                  .fontColor(AppColors.hongguoRed)
                  .backgroundColor('rgba(255, 36, 66, 0.12)')
                  .borderRadius(14)
                  .height(28)
                  .padding({ left: 12, right: 12 })
              }
              .width('100%')
              .padding(AppDimensions.paddingMd)
              .backgroundColor(AppColors.bgCard)
              .borderRadius(AppDimensions.radiusMd)
              .onClick(() => {
                this.openDramaDetail(item);
              })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
