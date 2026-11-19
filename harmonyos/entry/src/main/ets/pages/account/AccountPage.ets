import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';
import { DramaItem } from '../../models/Drama';
import { UserProfile } from '../../models/Account';
import { WatchHistoryItem, LocalStore } from '../../core/store/LocalStore';
import { AccountService } from '../../core/account/AccountService';

@Entry
@Component
export struct AccountPage {
  @State user: UserProfile = {
    userId: '',
    nickname: '未登录用户',
    avatarUrl: '',
    isLoggedIn: false
  };

  @State currentTab: number = 0; // 0: 追剧, 1: 历史记录
  @State historyList: WatchHistoryItem[] = [];
  @State favoriteList: DramaItem[] = [];
  @State isRefreshing: boolean = false;

  aboutToAppear(): void {
    this.refreshData();
  }

  onPageShow(): void {
    this.refreshData();
  }

  async refreshData(): Promise<void> {
    this.isRefreshing = true;
    try {
      this.user = AccountService.getInstance().getCurrentUser();
      this.historyList = await LocalStore.getInstance().getHistory();
      this.favoriteList = await LocalStore.getInstance().getFavorites();
    } finally {
      this.isRefreshing = false;
    }
  }

  goToLogin(): void {
    promptAction.showDialog({
      title: '账号登录提示',
      message: '登录后将使用短剧平台的接口数据同步追剧与观看记录，原有本地记录会保留。\n\n是否确认登录？',
      buttons: [
        { text: '取消', color: AppColors.textSecondaryDark },
        { text: '确认登录', color: AppColors.hongguoRed }
      ]
    }).then(res => {
      if (res.index === 1) {
        router.pushUrl({ url: 'pages/account/LoginPage' });
      }
    });
  }

  async logout(): Promise<void> {
    await AccountService.getInstance().logout();
    this.user = AccountService.getInstance().getCurrentUser();
    promptAction.showToast({ message: '已退出登录' });
  }

  playFromHistory(item: WatchHistoryItem): void {
    router.pushUrl({
      url: 'pages/player/PlayerPage',
      params: {
        dramaId: item.dramaId,
        dramaTitle: item.dramaTitle,
        coverUrl: item.coverUrl,
        episodeIndex: item.episodeIndex
      }
    });
  }

  openDramaDetail(drama: DramaItem): void {
    router.pushUrl({
      url: 'pages/detail/DramaDetailPage',
      params: {
        dramaId: drama.id,
        dramaTitle: drama.title,
        coverUrl: drama.coverUrl
      }
    });
  }

  async removeHistory(dramaId: string): Promise<void> {
    await LocalStore.getInstance().removeHistory(dramaId);
    this.historyList = await LocalStore.getInstance().getHistory();
    promptAction.showToast({ message: '已移除观看记录' });
  }

  async clearAllHistory(): Promise<void> {
    for (const h of this.historyList) {
      await LocalStore.getInstance().removeHistory(h.dramaId);
    }
    this.historyList = [];
    promptAction.showToast({ message: '已清空历史记录' });
  }

  async removeFavorite(dramaId: string): Promise<void> {
    await LocalStore.getInstance().toggleFavorite({
      id: dramaId,
      title: '',
      coverUrl: '',
      remarks: '',
      intro: '',
      episodeCount: 0,
      source: 'hongguo'
    });
    this.favoriteList = await LocalStore.getInstance().getFavorites();
    promptAction.showToast({ message: '已取消追剧' });
  }

  build() {
    Column() {
      // 顶部 Header: 对齐 Flutter AccountScreen
      Row() {
        Text('我的')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)

        Blank()

        if (!this.user.isLoggedIn) {
          // 登录胶囊大红按钮 (对齐 Flutter FilledButton.icon)
          Button({ type: ButtonType.Capsule }) {
            Row({ space: 6 }) {
              Text('👤')
                .fontSize(14)
              Text('登录')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.white)
            }
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          }
          .backgroundColor(AppColors.hongguoRed)
          .height(36)
          .onClick(() => {
            this.goToLogin();
          })
        } else {
          // 已登录用户状态
          Row({ space: 10 }) {
            Text(this.user.nickname)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Button('退出')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .backgroundColor(AppColors.bgCard)
              .height(30)
              .borderRadius(15)
              .onClick(() => {
                this.logout();
              })
          }
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 12 })
      .backgroundColor(AppColors.bgDark)

      // 子 Tab 栏: "追剧" 与 "历史记录" (对齐 Flutter my-follows 与 my-history)
      Row({ space: 12 }) {
        Button({ type: ButtonType.Capsule }) {
          Row({ space: 6 }) {
            Text('🔖')
              .fontSize(13)
            Text(`追剧${this.favoriteList.length > 0 ? ` (${this.favoriteList.length})` : ''}`)
              .fontSize(13)
              .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentTab === 0 ? AppColors.white : AppColors.textSecondary)
          }
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        }
        .backgroundColor(this.currentTab === 0 ? AppColors.bgElevated : AppColors.transparent)
        .border({ width: 0.8, color: this.currentTab === 0 ? AppColors.hongguoRed : AppColors.whiteAlpha10 })
        .height(34)
        .onClick(() => {
          this.currentTab = 0;
          this.refreshData(); // 自动拉取本地数据，防止白屏
        })

        Button({ type: ButtonType.Capsule }) {
          Row({ space: 6 }) {
            Text('🕒')
              .fontSize(13)
            Text(`历史记录${this.historyList.length > 0 ? ` (${this.historyList.length})` : ''}`)
              .fontSize(13)
              .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentTab === 1 ? AppColors.white : AppColors.textSecondary)
          }
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        }
        .backgroundColor(this.currentTab === 1 ? AppColors.bgElevated : AppColors.transparent)
        .border({ width: 0.8, color: this.currentTab === 1 ? AppColors.hongguoRed : AppColors.whiteAlpha10 })
        .height(34)
        .onClick(() => {
          this.currentTab = 1;
          this.refreshData(); // 修复初次切换时未自动拉取数据需手动刷新的问题 (对齐 commit 9101b3a)
        })

        Blank()

        // 刷新列表按钮
        Button({ type: ButtonType.Circle }) {
          Text('🔄')
            .fontSize(13)
        }
        .width(32)
        .height(32)
        .backgroundColor(AppColors.whiteAlpha08)
        .onClick(() => {
          this.refreshData();
        })

        if (this.currentTab === 1 && this.historyList.length > 0) {
          Button('清空')
            .fontSize(12)
            .fontColor(AppColors.textSecondaryDark)
            .backgroundColor(AppColors.transparent)
            .height(32)
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              this.clearAllHistory();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 2, bottom: 10 })

      // 主内容区: 升级为紧凑多列自适应网格 (3列，对齐 Flutter commit 0f8c861)
      if (this.currentTab === 0) {
        // "追剧" 收藏网格
        if (this.favoriteList.length === 0) {
          Column({ space: 12 }) {
            Text('🎬')
              .fontSize(44)
            Text('暂无追剧记录')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)
            Text('快去发现精彩短剧，点击追剧一键收藏')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.favoriteList, (drama: DramaItem) => {
              GridItem() {
                Column() {
                  Stack({ alignContent: Alignment.BottomEnd }) {
                    Image(drama.coverUrl)
                      .width('100%')
                      .height(148)
                      .borderRadius(AppDimensions.radiusSm)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(AppColors.bgCardHover)

                    if (drama.remarks) {
                      Text(drama.remarks)
                        .fontSize(9.5)
                        .fontColor(AppColors.white)
                        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                        .backgroundColor(AppColors.maskDark65)
                        .borderRadius({ topLeft: 4, bottomRight: AppDimensions.radiusSm })
                    }
                  }
                  .width('100%')
                  .height(148)

                  Text(drama.title)
                    .fontSize(12.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 5, bottom: 2 })
                    .width('100%')

                  Row() {
                    Text('连载中')
                      .fontSize(10.5)
                      .fontColor(AppColors.textSecondary)
                      .layoutWeight(1)

                    Text('取消')
                      .fontSize(10)
                      .fontColor(AppColors.hongguoRed)
                      .onClick(() => {
                        this.removeFavorite(drama.id);
                      })
                  }
                  .width('100%')
                }
                .width('100%')
                .onClick(() => {
                  this.openDramaDetail(drama);
                })
              }
            })
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(10)
          .rowsGap(12)
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 14, right: 14, bottom: 16 })
        }
      } else {
        // "历史记录" 观看历史网格 (3列紧凑网格)
        if (this.historyList.length === 0) {
          Column({ space: 12 }) {
            Text('🕒')
              .fontSize(44)
            Text('暂无观看历史')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)
            Text('您看过的短剧都会保存在这里')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.historyList, (item: WatchHistoryItem) => {
              GridItem() {
                Column() {
                  Stack({ alignContent: Alignment.BottomEnd }) {
                    Image(item.coverUrl)
                      .width('100%')
                      .height(148)
                      .borderRadius(AppDimensions.radiusSm)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(AppColors.bgCardHover)

                    Text(`第 ${item.episodeIndex} 集`)
                      .fontSize(9.5)
                      .fontColor(AppColors.white)
                      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                      .backgroundColor(AppColors.hongguoRed)
                      .borderRadius({ topLeft: 4, bottomRight: AppDimensions.radiusSm })
                  }
                  .width('100%')
                  .height(148)

                  Text(item.dramaTitle)
                    .fontSize(12.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 5, bottom: 2 })
                    .width('100%')

                  Row() {
                    Text('继续观看')
                      .fontSize(10.5)
                      .fontColor(AppColors.hongguoOrange)
                      .layoutWeight(1)

                    Text('删除')
                      .fontSize(10)
                      .fontColor(AppColors.textSecondary)
                      .onClick(() => {
                        this.removeHistory(item.dramaId);
                      })
                  }
                  .width('100%')
                }
                .width('100%')
                .onClick(() => {
                  this.playFromHistory(item);
                })
              }
            })
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(10)
          .rowsGap(12)
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 14, right: 14, bottom: 16 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
