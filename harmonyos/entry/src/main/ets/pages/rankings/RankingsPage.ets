import router from '@ohos.router';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { RankingBoard, RankingItem, RankingPageResult } from '../../models/Ranking';
import { CoreEngine } from '../../core/engine/CoreEngine';

@Entry
@Component
export struct RankingsPage {
  @State boards: RankingBoard[] = [];
  @State selectedBoardIndex: number = 0;
  @State items: RankingItem[] = [];
  @State page: number = 1;
  @State hasMore: boolean = true;
  @State isLoading: boolean = true;
  @State isLoadingMore: boolean = false;

  aboutToAppear(): void {
    this.loadBoards();
  }

  async loadBoards(): Promise<void> {
    this.isLoading = true;
    try {
      this.boards = await CoreEngine.getInstance().getRankingBoards();
      if (this.boards.length > 0) {
        await this.loadRankings(this.selectedBoardIndex, 1, false);
      }
    } catch (e) {
      console.error('Failed to load ranking boards: ' + JSON.stringify(e));
    }
    this.isLoading = false;
  }

  async loadRankings(boardIndex: number, page: number, append: boolean): Promise<void> {
    if (boardIndex < 0 || boardIndex >= this.boards.length) return;
    const board = this.boards[boardIndex];
    if (append) {
      this.isLoadingMore = true;
    } else {
      this.isLoading = true;
    }

    try {
      const res: RankingPageResult = await CoreEngine.getInstance().getRankings(board.boardId, page);
      if (append) {
        const seen = new Set<string>();
        const merged: RankingItem[] = [];
        for (const item of this.items) {
          seen.add(item.dramaId);
          merged.push(item);
        }
        for (const item of res.items) {
          if (!seen.has(item.dramaId)) {
            seen.add(item.dramaId);
            item.rank = merged.length + 1;
            merged.push(item);
          }
        }
        this.items = merged;
      } else {
        this.items = res.items;
      }
      this.page = res.page;
      this.hasMore = res.hasMore;
    } catch (e) {
      console.error('Failed to load rankings: ' + JSON.stringify(e));
    } finally {
      this.isLoading = false;
      this.isLoadingMore = false;
    }
  }

  async onSelectBoard(index: number): Promise<void> {
    if (this.selectedBoardIndex === index) return;
    this.selectedBoardIndex = index;
    this.items = [];
    this.page = 1;
    this.hasMore = true;
    await this.loadRankings(index, 1, false);
  }

  async loadMore(): Promise<void> {
    if (this.isLoadingMore || !this.hasMore || this.isLoading) return;
    await this.loadRankings(this.selectedBoardIndex, this.page + 1, true);
  }

  getRankColor(rank: number): ResourceColor {
    if (rank === 1) return '#FF2442'; // 榜首使用红果红
    if (rank === 2) return '#FFA000'; // 榜眼使用琥珀金
    if (rank === 3) return '#FFC107'; // 探花使用暖黄色
    return AppColors.textSecondaryDark;
  }

  openDramaDetail(item: RankingItem): void {
    router.pushUrl({
      url: 'pages/detail/DramaDetailPage',
      params: {
        dramaId: item.dramaId,
        dramaTitle: item.title,
        coverUrl: item.coverUrl
      }
    });
  }

  build() {
    Column() {
      // 顶部导航栏 (对齐 Flutter 风格返回按钮与标题)
      Row({ space: 8 }) {
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

        Text('短剧排行榜')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)

        Blank()

        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_search'))
            .width(20)
            .height(20)
            .fillColor(AppColors.textPrimary)
        }
        .backgroundColor(Color.Transparent)
        .width(40)
        .height(40)
        .onClick(() => {
          router.pushUrl({ url: 'pages/search/SearchPage' });
        })
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 38, bottom: 8 })
      .backgroundColor(AppColors.bgDark)

      // 榜单切换横向滑动标签
      if (this.boards.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.boards, (board: RankingBoard, index: number) => {
              Button(board.title)
                .fontSize(13)
                .fontWeight(this.selectedBoardIndex === index ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.selectedBoardIndex === index ? Color.White : AppColors.textSecondary)
                .backgroundColor(this.selectedBoardIndex === index ? AppColors.hongguoRed : AppColors.bgCard)
                .height(32)
                .padding({ left: 16, right: 16 })
                .borderRadius(16)
                .onClick(() => {
                  this.onSelectBoard(index);
                })
            })
          }
          .padding({ left: 16, right: 16, top: 4, bottom: 8 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }

      if (this.isLoading && this.items.length === 0) {
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
      } else {
        // 当前榜单列表与分页
        List({ space: 10 }) {
          // 榜单副标题与更新说明
          if (this.boards.length > this.selectedBoardIndex) {
            ListItem() {
              Row() {
                Text(this.boards[this.selectedBoardIndex].subTitle || '官方短剧每日实时榜单')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)

                Blank()

                Text('实时更新')
                  .fontSize(11)
                  .fontColor(AppColors.hongguoGold)
              }
              .width('100%')
              .padding({ left: 4, right: 4, top: 2, bottom: 4 })
            }
          }

          // 榜单排行列表项
          ForEach(this.items, (item: RankingItem) => {
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

          // 底部加载更多或已到底提示
          ListItem() {
            Row() {
              if (this.isLoadingMore) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(AppColors.hongguoRed)
                  .margin({ right: 8 })
                Text('正在加载更多榜单短剧...')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              } else if (!this.hasMore && this.items.length > 0) {
                Text('已经到底啦')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 12, bottom: 24 })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 8 })
        .onReachEnd(() => {
          this.loadMore();
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
