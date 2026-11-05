import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { DramaItem } from '../../models/Drama';
import { UserProfile } from '../../models/Account';
import { WatchHistoryItem, LocalStore } from '../../core/store/LocalStore';
import { AccountService } from '../../core/account/AccountService';
import { Constants } from '../../common/Constants';

@Entry
@Component
export struct AccountPage {
  @State user: UserProfile = {
    userId: '',
    nickname: '未登录用户',
    avatarUrl: '',
    isLoggedIn: false
  };

  @State currentTab: number = 0; // 0: 历史记录, 1: 追剧收藏
  @State historyList: WatchHistoryItem[] = [];
  @State favoriteList: DramaItem[] = [];
  @State cacheSizeText: string = '12.8 MB';

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
    router.pushUrl({ url: 'pages/account/LoginPage' });
  }

  async logout(): Promise<void> {
    await AccountService.getInstance().logout();
    this.user = AccountService.getInstance().getCurrentUser();
    promptAction.showToast({ message: '已安全退出登录' });
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
        dramaTitle: drama.title
      }
    });
  }

  async clearHistory(): Promise<void> {
    for (const h of this.historyList) {
      await LocalStore.getInstance().removeHistory(h.dramaId);
    }
    this.historyList = [];
    promptAction.showToast({ message: '已清空历史记录' });
  }

  clearCache(): void {
    this.cacheSizeText = '0.0 KB';
    promptAction.showToast({ message: '应用临时缓存已清理完毕' });
  }

  showAboutDialog(): void {
    promptAction.showDialog({
      title: Constants.APP_NAME,
      message: `版本号：${Constants.APP_VERSION}\n基于 HarmonyOS NEXT 原生 ArkTS 打造。\n\n全端独立运行短剧应用，支持海量短剧极速秒播。`,
      buttons: [
        { text: '确定', color: AppColors.hongguoRed }
      ]
    });
  }

  build() {
    Column() {
      // 顶部标题
      Row() {
        Text('个人中心')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)

        Blank()

        Button('⚙️')
          .fontSize(16)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            router.pushUrl({ url: 'pages/settings/SettingsPage' });
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 16 }) {
          // 用户信息卡片
          Row({ space: 14 }) {
            // 头像
            Stack({ alignContent: Alignment.Center }) {
              Circle({ width: 56, height: 56 })
                .fill(AppColors.bgCard)
              Text(this.user.isLoggedIn ? '👤' : '👻')
                .fontSize(28)
            }

            // 用户名与标识
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Text(this.user.nickname)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.textPrimary)

                if (this.user.vipStatus) {
                  Text(this.user.vipStatus)
                    .fontSize(10)
                    .fontColor(AppColors.hongguoGold)
                    .backgroundColor('rgba(255, 179, 0, 0.15)')
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                }
              }

              Text(this.user.isLoggedIn ? (this.user.phoneMasked ?? '官方用户') : '登录享受跨端同步与高清秒播')
                .fontSize(12)
                .fontColor(AppColors.textSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 登录 / 退出 按钮
            if (this.user.isLoggedIn) {
              Button('退出')
                .fontSize(12)
                .fontColor(AppColors.textSecondary)
                .backgroundColor(AppColors.bgCard)
                .height(30)
                .borderRadius(15)
                .onClick(() => {
                  this.logout();
                })
            } else {
              Button('登录')
                .fontSize(12)
                .fontColor(Color.White)
                .backgroundColor(AppColors.hongguoRed)
                .height(30)
                .padding({ left: 16, right: 16 })
                .borderRadius(15)
                .onClick(() => {
                  this.goToLogin();
                })
            }
          }
          .width('100%')
          .padding(AppDimensions.paddingLg)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusLg)

          // 常用功能入口矩阵
          Row({ space: 12 }) {
            // 离线缓存
            Column({ space: 6 }) {
              Text('📥')
                .fontSize(22)
              Text('离线缓存')
                .fontSize(12)
                .fontColor(AppColors.textPrimary)
            }
            .layoutWeight(1)
            .padding({ top: 12, bottom: 12 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius(AppDimensions.radiusMd)
            .onClick(() => {
              router.pushUrl({ url: 'pages/downloads/DownloadsPage' });
            })

            // 清理缓存
            Column({ space: 6 }) {
              Text('🧹')
                .fontSize(22)
              Text(`清理 (${this.cacheSizeText})`)
                .fontSize(12)
                .fontColor(AppColors.textPrimary)
            }
            .layoutWeight(1)
            .padding({ top: 12, bottom: 12 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius(AppDimensions.radiusMd)
            .onClick(() => {
              this.clearCache();
            })

            // 关于应用
            Column({ space: 6 }) {
              Text('ℹ️')
                .fontSize(22)
              Text('关于糖葫芦')
                .fontSize(12)
                .fontColor(AppColors.textPrimary)
            }
            .layoutWeight(1)
            .padding({ top: 12, bottom: 12 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius(AppDimensions.radiusMd)
            .onClick(() => {
              this.showAboutDialog();
            })
          }
          .width('100%')

          // 历史记录与追剧收藏 Tab 栏
          Row() {
            Button(`观看历史 (${this.historyList.length})`)
              .layoutWeight(1)
              .fontSize(13)
              .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentTab === 0 ? AppColors.hongguoRed : AppColors.textSecondary)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.currentTab = 0;
              })

            Button(`追剧收藏 (${this.favoriteList.length})`)
              .layoutWeight(1)
              .fontSize(13)
              .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentTab === 1 ? AppColors.hongguoRed : AppColors.textSecondary)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.currentTab = 1;
              })
          }
          .width('100%')
          .border({ width: { bottom: 1 }, color: AppColors.divider })
          .padding({ top: 4, bottom: 4 })

          // 列表区域
          if (this.currentTab === 0) {
            // 观看历史
            if (this.historyList.length === 0) {
              Column({ space: 8 }) {
                Text('🎬')
                  .fontSize(36)
                Text('暂无观看历史')
                  .fontSize(13)
                  .fontColor(AppColors.textMuted)
              }
              .width('100%')
              .padding({ top: 40, bottom: 40 })
            } else {
              Column({ space: 10 }) {
                Row() {
                  Blank()
                  Button('清空全部历史')
                    .fontSize(11)
                    .fontColor(AppColors.textMuted)
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                      this.clearHistory();
                    })
                }
                .width('100%')

                ForEach(this.historyList, (item: WatchHistoryItem) => {
                  Row({ space: 12 }) {
                    Image(item.coverUrl)
                      .width(64)
                      .height(84)
                      .borderRadius(AppDimensions.radiusSm)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(AppColors.bgCard)

                    Column({ space: 6 }) {
                      Text(item.dramaTitle)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(AppColors.textPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })

                      Text(`观看到 第 ${item.episodeIndex} 集`)
                        .fontSize(12)
                        .fontColor(AppColors.hongguoRed)

                      Blank()

                      Text('点击继续播放')
                        .fontSize(11)
                        .fontColor(AppColors.textMuted)
                    }
                    .layoutWeight(1)
                    .height(84)
                    .alignItems(HorizontalAlign.Start)

                    Button('▶ 继续')
                      .fontSize(11)
                      .fontColor(Color.White)
                      .backgroundColor(AppColors.hongguoRed)
                      .borderRadius(14)
                      .height(28)
                      .onClick(() => {
                        this.playFromHistory(item);
                      })
                  }
                  .width('100%')
                  .padding(AppDimensions.paddingMd)
                  .backgroundColor(AppColors.bgCard)
                  .borderRadius(AppDimensions.radiusMd)
                })
              }
              .width('100%')
            }
          } else {
            // 追剧收藏
            if (this.favoriteList.length === 0) {
              Column({ space: 8 }) {
                Text('❤️')
                  .fontSize(36)
                Text('暂无追剧收藏')
                  .fontSize(13)
                  .fontColor(AppColors.textMuted)
              }
              .width('100%')
              .padding({ top: 40, bottom: 40 })
            } else {
              Grid() {
                ForEach(this.favoriteList, (drama: DramaItem) => {
                  GridItem() {
                    Column({ space: 6 }) {
                      Image(drama.coverUrl)
                        .width('100%')
                        .height(150)
                        .borderRadius(AppDimensions.radiusMd)
                        .objectFit(ImageFit.Cover)
                        .backgroundColor(AppColors.bgCard)

                      Text(drama.title)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(AppColors.textPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
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
            }
          }
        }
        .padding(AppDimensions.paddingMd)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
