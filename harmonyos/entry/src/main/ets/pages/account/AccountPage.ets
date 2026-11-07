import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors, AppDimensions } from '../../common/AppTheme';
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

  aboutToAppear(): void {
    this.refreshData();
  }

  onPageShow(): void {
    this.refreshData();
  }

  async refreshData(): Promise<void> {
    this.user = AccountService.getInstance().getCurrentUser();
    this.historyList = await LocalStore.getInstance().getHistory();
    this.favoriteList = await LocalStore.getInstance().getFavorites();
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
                .fontColor(Color.White)
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
            Text('追剧')
              .fontSize(13)
              .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentTab === 0 ? Color.White : AppColors.textSecondary)
          }
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        }
        .backgroundColor(this.currentTab === 0 ? AppColors.bgElevated : Color.Transparent)
        .border({ width: 0.8, color: this.currentTab === 0 ? AppColors.hongguoRed : 'rgba(255,255,255,0.1)' })
        .height(36)
        .onClick(() => {
          this.currentTab = 0;
        })

        Button({ type: ButtonType.Capsule }) {
          Row({ space: 6 }) {
            Text('🕒')
              .fontSize(13)
            Text('历史记录')
              .fontSize(13)
              .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentTab === 1 ? Color.White : AppColors.textSecondary)
          }
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        }
        .backgroundColor(this.currentTab === 1 ? AppColors.bgElevated : Color.Transparent)
        .border({ width: 0.8, color: this.currentTab === 1 ? AppColors.hongguoRed : 'rgba(255,255,255,0.1)' })
        .height(36)
        .onClick(() => {
          this.currentTab = 1;
        })

        Blank()

        if (this.currentTab === 1 && this.historyList.length > 0) {
          Button('清空历史')
            .fontSize(12)
            .fontColor(AppColors.textSecondaryDark)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.clearAllHistory();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 12 })

      // 主内容区
      if (this.currentTab === 0) {
        // "追剧" 收藏列表
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
          List({ space: 10 }) {
            ForEach(this.favoriteList, (drama: DramaItem) => {
              ListItem() {
                Row({ space: 12 }) {
                  Image(drama.coverUrl)
                    .width(60)
                    .height(80)
                    .borderRadius(AppDimensions.radiusSm)
                    .objectFit(ImageFit.Cover)
                    .backgroundColor(AppColors.bgCard)

                  Column({ space: 6 }) {
                    Text(drama.title)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(AppColors.textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(drama.remarks || '连载中')
                      .fontSize(12)
                      .fontColor(AppColors.textSecondary)

                    Blank()

                    Row({ space: 8 }) {
                      Button('继续播放')
                        .fontSize(11)
                        .fontColor(Color.White)
                        .backgroundColor(AppColors.hongguoRed)
                        .height(26)
                        .borderRadius(13)
                        .padding({ left: 12, right: 12 })
                        .onClick(() => {
                          this.openDramaDetail(drama);
                        })

                      Button('取消追剧')
                        .fontSize(11)
                        .fontColor(AppColors.textSecondary)
                        .backgroundColor(AppColors.bgElevated)
                        .height(26)
                        .borderRadius(13)
                        .padding({ left: 10, right: 10 })
                        .onClick(() => {
                          this.removeFavorite(drama.id);
                        })
                    }
                  }
                  .layoutWeight(1)
                  .height(80)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(AppDimensions.paddingMd)
                .backgroundColor(AppColors.bgCard)
                .borderRadius(AppDimensions.radiusMd)
                .onClick(() => {
                  this.openDramaDetail(drama);
                })
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, bottom: 16 })
        }
      } else {
        // "历史记录" 观看历史列表
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
          List({ space: 10 }) {
            ForEach(this.historyList, (item: WatchHistoryItem) => {
              ListItem() {
                Row({ space: 12 }) {
                  Image(item.coverUrl)
                    .width(60)
                    .height(80)
                    .borderRadius(AppDimensions.radiusSm)
                    .objectFit(ImageFit.Cover)
                    .backgroundColor(AppColors.bgCard)

                  Column({ space: 6 }) {
                    Text(item.dramaTitle)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(AppColors.textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(`观看到第 ${item.episodeIndex} 集`)
                      .fontSize(12)
                      .fontColor(AppColors.hongguoRed)

                    Blank()

                    Row({ space: 8 }) {
                      Button('续播')
                        .fontSize(11)
                        .fontColor(Color.White)
                        .backgroundColor(AppColors.hongguoRed)
                        .height(26)
                        .borderRadius(13)
                        .padding({ left: 12, right: 12 })
                        .onClick(() => {
                          this.playFromHistory(item);
                        })

                      Button('删除')
                        .fontSize(11)
                        .fontColor(AppColors.textSecondary)
                        .backgroundColor(AppColors.bgElevated)
                        .height(26)
                        .borderRadius(13)
                        .padding({ left: 10, right: 10 })
                        .onClick(() => {
                          this.removeHistory(item.dramaId);
                        })
                    }
                  }
                  .layoutWeight(1)
                  .height(80)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(AppDimensions.paddingMd)
                .backgroundColor(AppColors.bgCard)
                .borderRadius(AppDimensions.radiusMd)
                .onClick(() => {
                  this.playFromHistory(item);
                })
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, bottom: 16 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
