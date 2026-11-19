import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';
import { DramaItem } from '../../models/Drama';
import { AnchorItem } from '../../models/Account';
import { CoreEngine } from '../../core/engine/CoreEngine';
import { AccountService } from '../../core/account/AccountService';

interface RouterParams {
  id?: string;
  name?: string;
  avatar?: string;
  bio?: string;
  worksCount?: number;
  isFollowed?: boolean;
  relativeType?: number;
}

@Entry
@Component
export struct AnchorDetailPage {
  @State anchor: AnchorItem = {
    id: '',
    name: '红果主播',
    avatar: '',
    bio: '',
    worksCount: 0,
    isFollowed: false,
    relativeType: 2
  };

  @State works: DramaItem[] = [];
  @State isLoading: boolean = true;
  @State isFollowing: boolean = false;
  @State isTogglingFollow: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as RouterParams;
    if (params) {
      this.anchor = {
        id: params.id || '',
        name: params.name || '红果主播',
        avatar: params.avatar || '',
        bio: params.bio || '',
        worksCount: params.worksCount || 0,
        isFollowed: !!params.isFollowed,
        relativeType: params.relativeType || 2
      };
      this.isFollowing = !!params.isFollowed;
    }
    this.loadData();
  }

  async loadData(): Promise<void> {
    if (!this.anchor.id) return;
    this.isLoading = true;
    try {
      // 1. 获取主播个人资料确认
      const profile = await CoreEngine.getInstance().fetchCreatorProfile(this.anchor.id);
      if (profile) {
        this.anchor.name = profile.name || this.anchor.name;
        this.anchor.avatar = profile.avatar || this.anchor.avatar;
        this.anchor.bio = profile.bio || this.anchor.bio;
        if (typeof profile.worksCount === 'number') {
          this.anchor.worksCount = profile.worksCount;
        }
        if (typeof profile.isFollowed === 'boolean') {
          this.isFollowing = profile.isFollowed;
        }
      }

      // 2. 获取主播短剧作品列表
      const worksList = await CoreEngine.getInstance().fetchCreatorWorks(this.anchor.id);
      this.works = worksList;
      if (this.works.length > 0 && (!this.anchor.worksCount || this.anchor.worksCount < this.works.length)) {
        this.anchor.worksCount = this.works.length;
      }
    } catch (_) {
      promptAction.showToast({ message: '获取主播作品失败' });
    } finally {
      this.isLoading = false;
    }
  }

  async toggleFollow(): Promise<void> {
    const user = AccountService.getInstance().getCurrentUser();
    if (!user.isLoggedIn) {
      promptAction.showToast({ message: '请先登录红果账号' });
      return;
    }
    if (this.isTogglingFollow) return;
    this.isTogglingFollow = true;
    const targetState = !this.isFollowing;
    try {
      const ok = await AccountService.getInstance().setCreatorFollowing(
        this.anchor.id,
        this.anchor.relativeType || 2,
        targetState
      );
      if (ok) {
        this.isFollowing = targetState;
        promptAction.showToast({ message: targetState ? '已关注主播' : '已取消关注' });
      } else {
        promptAction.showToast({ message: '关注操作失败，请重试' });
      }
    } catch (_) {
      promptAction.showToast({ message: '关注操作异常' });
    } finally {
      this.isTogglingFollow = false;
    }
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

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button({ type: ButtonType.Circle }) {
          Text('‹')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
        }
        .width(36)
        .height(36)
        .backgroundColor(AppColors.transparent)
        .onClick(() => {
          router.back();
        })

        Text('主播主页')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .margin({ left: 8 })

        Blank()
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 38, bottom: 10 })
      .backgroundColor(AppColors.bgDark)

      // 主播信息头部卡片
      Row() {
        // 主播头像
        Stack() {
          if (this.anchor.avatar) {
            Image(this.anchor.avatar)
              .width(54)
              .height(54)
              .borderRadius(27)
              .objectFit(ImageFit.Cover)
          } else {
            Circle({ width: 54, height: 54 })
              .fill(AppColors.hongguoRed)
              .opacity(0.15)
            Text('👤')
              .fontSize(26)
          }
        }
        .width(54)
        .height(54)
        .margin({ right: 14 })

        // 主播名称与简介
        Column() {
          Text(this.anchor.name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.anchor.bio) {
            Text(this.anchor.bio)
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 4 })
          }

          Text(`短剧作品 ${this.anchor.worksCount || this.works.length} 部`)
            .fontSize(11)
            .fontColor(AppColors.hongguoRed)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 关注按钮
        Button({ type: ButtonType.Capsule }) {
          Row({ space: 4 }) {
            Text(this.isFollowing ? '已关注' : '+ 关注')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isFollowing ? AppColors.textSecondary : AppColors.white)
          }
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        }
        .backgroundColor(this.isFollowing ? AppColors.bgElevated : AppColors.hongguoRed)
        .border({ width: 0.8, color: this.isFollowing ? AppColors.whiteAlpha15 : AppColors.hongguoRed })
        .height(30)
        .margin({ left: 8 })
        .onClick(() => {
          this.toggleFollow();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      .backgroundColor(AppColors.bgCard)
      .margin({ bottom: 10 })

      // 作品列表栏标题
      Row() {
        Text('作品列表')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)

        Text(`(${this.works.length})`)
          .fontSize(12)
          .fontColor(AppColors.textSecondary)
          .margin({ left: 6 })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })

      // 作品网格或骨架
      if (this.isLoading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppColors.hongguoRed)
          Text('正在加载主播短剧作品...')
            .fontSize(13)
            .fontColor(AppColors.textSecondary)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.works.length === 0) {
        Column({ space: 12 }) {
          Text('🎬')
            .fontSize(44)
          Text('暂无作品')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
          Text('该主播暂未发布公开短剧作品')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.works, (drama: DramaItem) => {
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

                Text('短剧专区')
                  .fontSize(10.5)
                  .fontColor(AppColors.textSecondary)
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
