import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';
import { DramaItem } from '../../models/Drama';
import { UserProfile, LikedVideoItem, AnchorItem, CloudWatchEntry } from '../../models/Account';
import { WatchHistoryItem, LocalStore } from '../../core/store/LocalStore';
import { AccountService } from '../../core/account/AccountService';

interface TabDef {
  index: number;
  label: string;
}

@Entry
@Component
export struct AccountPage {
  @State user: UserProfile = {
    userId: '',
    nickname: '未登录用户',
    avatarUrl: '',
    isLoggedIn: false
  };

  // 0: 追剧, 1: 历史记录, 2: 点赞视频, 3: 关注主播 (对齐 Flutter tabDefs)
  @State currentTab: number = 0;
  @State historyList: WatchHistoryItem[] = [];
  @State favoriteList: DramaItem[] = [];
  @State cloudFavorites: CloudWatchEntry[] = [];
  @State cloudHistory: CloudWatchEntry[] = [];
  @State likedVideos: LikedVideoItem[] = [];
  @State anchorsList: AnchorItem[] = [];
  @State isRefreshing: boolean = false;
  @State isLoadingTab: boolean = false;
  @State errorMessage: string = '';

  aboutToAppear(): void {
    this.refreshAllData();
  }

  onPageShow(): void {
    this.refreshAllData();
  }

  getTabDefs(): TabDef[] {
    const tabs: TabDef[] = [
      { index: 0, label: '追剧' },
      { index: 1, label: '历史记录' }
    ];
    if (this.user.isLoggedIn) {
      tabs.push({ index: 2, label: '点赞视频' });
      tabs.push({ index: 3, label: '关注主播' });
    }
    return tabs;
  }

  async refreshAllData(): Promise<void> {
    this.isRefreshing = true;
    try {
      this.user = AccountService.getInstance().getCurrentUser();
      if (!this.user.isLoggedIn && this.currentTab >= 2) {
        this.currentTab = 0;
      }
      this.historyList = await LocalStore.getInstance().getHistory();
      this.favoriteList = await LocalStore.getInstance().getFavorites();
      await this.loadActiveTabData();
    } finally {
      this.isRefreshing = false;
    }
  }

  async loadActiveTabData(): Promise<void> {
    this.isLoadingTab = true;
    this.errorMessage = '';
    const tab = this.currentTab;
    try {
      if (tab === 0) {
        // 追剧 (如果登录则拉取云端追剧，失败或未登录则展示本地收藏)
        if (this.user.isLoggedIn) {
          const cloud = await AccountService.getInstance().getCloudLibrary(false);
          this.cloudFavorites = cloud;
        }
        this.favoriteList = await LocalStore.getInstance().getFavorites();
      } else if (tab === 1) {
        // 历史记录 (如果登录则拉取云端历史记录，失败或未登录则展示本地历史)
        if (this.user.isLoggedIn) {
          const cloud = await AccountService.getInstance().getCloudLibrary(true);
          this.cloudHistory = cloud;
        }
        this.historyList = await LocalStore.getInstance().getHistory();
      } else if (tab === 2 && this.user.isLoggedIn) {
        // 点赞视频
        const page = await AccountService.getInstance().getLikedVideos(0, 30);
        this.likedVideos = page.items;
      } else if (tab === 3 && this.user.isLoggedIn) {
        // 关注主播
        const page = await AccountService.getInstance().getFollowingCreators(0, 30);
        this.anchorsList = page.creators;
      }
    } catch (_) {
      this.errorMessage = '数据获取失败，请重试';
    } finally {
      this.isLoadingTab = false;
    }
  }

  goToLogin(): void {
    promptAction.showDialog({
      title: '账号登录提示',
      message: '登录后将使用短剧平台的接口数据同步追剧与观看记录，原有本地记录会保留，退出账号后继续使用。\n\n是否确认登录？',
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
    promptAction.showDialog({
      title: '退出红果账号？',
      message: '本机追剧、历史和播放进度会保留。',
      buttons: [
        { text: '取消', color: AppColors.textSecondaryDark },
        { text: '退出登录', color: AppColors.hongguoRed }
      ]
    }).then(async res => {
      if (res.index === 1) {
        await AccountService.getInstance().logout();
        this.user = AccountService.getInstance().getCurrentUser();
        this.currentTab = 0;
        this.cloudFavorites = [];
        this.cloudHistory = [];
        this.likedVideos = [];
        this.anchorsList = [];
        promptAction.showToast({ message: '已退出登录' });
        this.refreshAllData();
      }
    });
  }

  playFromHistory(dramaId: string, dramaTitle: string, coverUrl: string, episodeIndex: number): void {
    router.pushUrl({
      url: 'pages/player/PlayerPage',
      params: {
        dramaId: dramaId,
        dramaTitle: dramaTitle,
        coverUrl: coverUrl,
        episodeIndex: episodeIndex
      }
    });
  }

  openDramaDetail(id: string, title: string, coverUrl: string): void {
    router.pushUrl({
      url: 'pages/detail/DramaDetailPage',
      params: {
        dramaId: id,
        dramaTitle: title,
        coverUrl: coverUrl
      }
    });
  }

  openAnchorDetail(anchor: AnchorItem): void {
    router.pushUrl({
      url: 'pages/anchor/AnchorDetailPage',
      params: {
        id: anchor.id,
        name: anchor.name,
        avatar: anchor.avatar,
        bio: anchor.bio,
        worksCount: anchor.worksCount,
        isFollowed: anchor.isFollowed,
        relativeType: anchor.relativeType
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
    this.cloudHistory = [];
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
      // 1. 顶部 Header (对齐 Flutter _buildHeader)
      if (this.user.isLoggedIn) {
        // 已登录 Header: 头像、昵称、同步状态、退出登录按钮
        Row() {
          Stack() {
            if (this.user.avatarUrl) {
              Image(this.user.avatarUrl)
                .width(36)
                .height(36)
                .borderRadius(18)
                .objectFit(ImageFit.Cover)
            } else {
              Circle({ width: 36, height: 36 })
                .fill(AppColors.hongguoRed)
                .opacity(0.18)
              Text('👤')
                .fontSize(18)
            }
          }
          .width(36)
          .height(36)
          .border({ width: 1.5, color: AppColors.hongguoRed })
          .borderRadius(18)
          .margin({ right: 10 })

          Column() {
            Text(this.user.nickname || '红果剧友')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Row({ space: 4 }) {
              Circle({ width: 5, height: 5 })
                .fill('#4CAF50')
              Text('红果账号已同步')
                .fontSize(10.5)
                .fontColor(AppColors.hongguoRed)
                .fontWeight(FontWeight.Medium)
            }
            .padding({ left: 6, right: 6, top: 1.5, bottom: 1.5 })
            .backgroundColor(AppColors.hongguoRedAlpha10)
            .borderRadius(4)
            .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('退出登录')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
            .backgroundColor(AppColors.bgCard)
            .height(30)
            .borderRadius(15)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.logout();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 38, bottom: 10 })
        .backgroundColor(AppColors.bgDark)
      } else {
        // 未登录 Header: "我的" 标题与登录胶囊按钮 + 登录提示引导条
        Column() {
          Row() {
            Text('我的')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Blank()

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
          }
          .width('100%')

          // 引导登录横幅卡片 (对齐 Flutter 登录卡片)
          Row() {
            Circle({ width: 38, height: 38 })
              .fill(AppColors.whiteAlpha08)
              .overlay(
                Text('👤')
                  .fontSize(18)
                  .fontColor(AppColors.textSecondary)
              )
              .margin({ right: 12 })

            Column() {
              Text('点击登录红果账号')
                .fontSize(14.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.textPrimary)
              Text('登录同步多端追剧与观看记录')
                .fontSize(11.5)
                .fontColor(AppColors.textSecondary)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('›')
              .fontSize(20)
              .fontColor(AppColors.textSecondary)
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(AppColors.bgCard)
          .borderRadius(12)
          .border({ width: 0.8, color: AppColors.whiteAlpha10 })
          .margin({ top: 10 })
          .onClick(() => {
            this.goToLogin();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 38, bottom: 10 })
        .backgroundColor(AppColors.bgDark)
      }

      // 2. Tab 切换胶囊栏: 对齐 Flutter tabDefs (未登录2个，已登录4个)
      Row() {
        Row({ space: 4 }) {
          ForEach(this.getTabDefs(), (tab: TabDef) => {
            Button({ type: ButtonType.Capsule }) {
              Text(tab.label)
                .fontSize(this.currentTab === tab.index ? 12.5 : 12)
                .fontWeight(this.currentTab === tab.index ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.currentTab === tab.index ? AppColors.white : AppColors.textSecondary)
                .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            }
            .backgroundColor(this.currentTab === tab.index ? AppColors.hongguoRedAlpha20 : AppColors.transparent)
            .border({
              width: 0.8,
              color: this.currentTab === tab.index ? AppColors.hongguoRed : AppColors.transparent
            })
            .height(32)
            .onClick(() => {
              this.currentTab = tab.index;
              this.loadActiveTabData();
            })
          })
        }
        .padding(3)
        .backgroundColor(AppColors.whiteAlpha08)
        .borderRadius(20)
        .border({ width: 0.8, color: AppColors.whiteAlpha10 })

        Blank()

        // 刷新按钮
        Button({ type: ButtonType.Circle }) {
          Text('🔄')
            .fontSize(13)
        }
        .width(32)
        .height(32)
        .backgroundColor(AppColors.whiteAlpha08)
        .onClick(() => {
          this.refreshAllData();
        })

        // 历史记录清空按钮
        if (this.currentTab === 1 && (this.cloudHistory.length > 0 || this.historyList.length > 0)) {
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
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })

      // 3. 子标题与状态栏 (对齐 Flutter '红果账号 · 追剧' / '红果账号 · 历史记录' 等)
      Row() {
        Text(
          this.currentTab === 0
            ? (this.user.isLoggedIn ? '红果账号 · 追剧' : '追剧列表')
            : (this.currentTab === 1
                ? (this.user.isLoggedIn ? '红果账号 · 历史记录' : '观看历史')
                : (this.currentTab === 2
                    ? '红果账号 · 点赞视频'
                    : '红果账号 · 关注主播'))
        )
          .fontSize(12.5)
          .fontColor(AppColors.textSecondary)
          .fontWeight(FontWeight.Medium)

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 2, bottom: 6 })

      // 4. 主内容展示区 (各 Tab 内容与骨架状态)
      if (this.isLoadingTab) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppColors.hongguoRed)
          Text('正在读取账号数据...')
            .fontSize(13)
            .fontColor(AppColors.textSecondary)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.currentTab === 0) {
        // Tab 0: 追剧 (优先云端追剧，无云端则本地收藏)
        if (this.user.isLoggedIn && this.cloudFavorites.length > 0) {
          // 云端追剧列表网格
          Grid() {
            ForEach(this.cloudFavorites, (entry: CloudWatchEntry) => {
              GridItem() {
                Column() {
                  Stack({ alignContent: Alignment.BottomEnd }) {
                    Image(entry.coverUrl)
                      .width('100%')
                      .height(148)
                      .borderRadius(AppDimensions.radiusSm)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(AppColors.bgCardHover)

                    if (entry.episodes > 0) {
                      Text(`全${entry.episodes}集`)
                        .fontSize(9.5)
                        .fontColor(AppColors.white)
                        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                        .backgroundColor(AppColors.maskDark65)
                        .borderRadius({ topLeft: 4, bottomRight: AppDimensions.radiusSm })
                    }
                  }
                  .width('100%')
                  .height(148)

                  Text(entry.dramaTitle)
                    .fontSize(12.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 5, bottom: 2 })
                    .width('100%')

                  Text('账号追剧')
                    .fontSize(10.5)
                    .fontColor(AppColors.hongguoRed)
                    .width('100%')
                }
                .width('100%')
                .onClick(() => {
                  this.openDramaDetail(entry.dramaId, entry.dramaTitle, entry.coverUrl);
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
        } else if (this.favoriteList.length > 0) {
          // 本地追剧列表网格
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
                  this.openDramaDetail(drama.id, drama.title, drama.coverUrl);
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
        } else {
          // 暂无追剧记录
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
        }
      } else if (this.currentTab === 1) {
        // Tab 1: 历史记录 (优先云端历史，无云端则本地历史)
        if (this.user.isLoggedIn && this.cloudHistory.length > 0) {
          // 云端历史记录网格
          Grid() {
            ForEach(this.cloudHistory, (entry: CloudWatchEntry) => {
              GridItem() {
                Column() {
                  Stack({ alignContent: Alignment.BottomEnd }) {
                    Image(entry.coverUrl)
                      .width('100%')
                      .height(148)
                      .borderRadius(AppDimensions.radiusSm)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(AppColors.bgCardHover)

                    Text(`第 ${entry.episodeIndex} 集`)
                      .fontSize(9.5)
                      .fontColor(AppColors.white)
                      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                      .backgroundColor(AppColors.hongguoRed)
                      .borderRadius({ topLeft: 4, bottomRight: AppDimensions.radiusSm })
                  }
                  .width('100%')
                  .height(148)

                  Text(entry.dramaTitle)
                    .fontSize(12.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 5, bottom: 2 })
                    .width('100%')

                  Text('继续观看')
                    .fontSize(10.5)
                    .fontColor(AppColors.hongguoOrange)
                    .width('100%')
                }
                .width('100%')
                .onClick(() => {
                  this.playFromHistory(entry.dramaId, entry.dramaTitle, entry.coverUrl, entry.episodeIndex);
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
        } else if (this.historyList.length > 0) {
          // 本地历史记录网格
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
                  this.playFromHistory(item.dramaId, item.dramaTitle, item.coverUrl, item.episodeIndex);
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
        } else {
          // 暂无观看历史
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
        }
      } else if (this.currentTab === 2) {
        // Tab 2: 点赞视频 (对齐 Flutter HongguoCollectionView<HongguoLikedVideo>)
        if (this.likedVideos.length === 0) {
          Column({ space: 12 }) {
            Text('❤️')
              .fontSize(44)
            Text('暂无点赞的视频')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)
            Text('在播放器中点击喜欢，点赞过的视频将保存在这里')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.likedVideos, (row: LikedVideoItem) => {
              GridItem() {
                Column() {
                  Stack({ alignContent: Alignment.BottomEnd }) {
                    Image(row.cover)
                      .width('100%')
                      .height(148)
                      .borderRadius(AppDimensions.radiusSm)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(AppColors.bgCardHover)

                    Text(row.kind === 'series' ? '合集' : (row.episode ? `第${row.episode}集` : '单集'))
                      .fontSize(9.5)
                      .fontColor(AppColors.white)
                      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                      .backgroundColor(AppColors.hongguoRed)
                      .borderRadius({ topLeft: 4, bottomRight: AppDimensions.radiusSm })
                  }
                  .width('100%')
                  .height(148)

                  Text(row.title)
                    .fontSize(12.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 5, bottom: 2 })
                    .width('100%')

                  Text(
                    row.kind === 'series'
                      ? '已点赞合集'
                      : (row.episode ? `已点赞 · 第 ${row.episode} 集` : '已点赞视频')
                  )
                    .fontSize(10.5)
                    .fontColor(AppColors.hongguoOrange)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
                .width('100%')
                .onClick(() => {
                  const targetId = row.seriesId || row.id;
                  this.openDramaDetail(targetId, row.title, row.cover);
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
      } else if (this.currentTab === 3) {
        // Tab 3: 关注主播 (对齐 Flutter HongguoCollectionView<Anchor>)
        if (this.anchorsList.length === 0) {
          Column({ space: 12 }) {
            Text('🌟')
              .fontSize(44)
            Text('暂无关注的主播')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)
            Text('关注心仪的主播，第一时间获取最新短剧动态')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.anchorsList, (anchor: AnchorItem) => {
              ListItem() {
                Row() {
                  // 头像
                  Stack() {
                    if (anchor.avatar) {
                      Image(anchor.avatar)
                        .width(42)
                        .height(42)
                        .borderRadius(21)
                        .objectFit(ImageFit.Cover)
                    } else {
                      Circle({ width: 42, height: 42 })
                        .fill(AppColors.hongguoRed)
                        .opacity(0.15)
                      Text('👤')
                        .fontSize(20)
                    }
                  }
                  .width(42)
                  .height(42)
                  .margin({ right: 12 })

                  // 主播信息
                  Column() {
                    Text(anchor.name)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(AppColors.textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    if (anchor.bio) {
                      Text(anchor.bio)
                        .fontSize(11.5)
                        .fontColor(AppColors.textSecondary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 3 })
                    } else if (anchor.worksCount && anchor.worksCount > 0) {
                      Text(`作品 ${anchor.worksCount} 部`)
                        .fontSize(11)
                        .fontColor(AppColors.hongguoRed)
                        .margin({ top: 3 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text('›')
                    .fontSize(22)
                    .fontColor(AppColors.textSecondary)
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .backgroundColor(AppColors.bgCard)
                .borderRadius(10)
                .border({ width: 0.8, color: AppColors.whiteAlpha10 })
                .onClick(() => {
                  this.openAnchorDetail(anchor);
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
