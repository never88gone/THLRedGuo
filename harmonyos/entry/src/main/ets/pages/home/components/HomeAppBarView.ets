import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors } from '../../../common/AppColors';

@Component
export struct HomeAppBarView {
  @Prop isSearchVisible: boolean = false;
  onToggleSearch: () => void = () => {};

  build() {
    Row() {
      // 左侧：数据源切换胶囊 (官方免费短剧 + 下拉箭头)
      Row({ space: 6 }) {
        Image($r('app.media.ic_movie_filter'))
          .width(18)
          .height(18)
          .fillColor(AppColors.hongguoRed)

        Text('官方免费短剧')
          .fontSize(16)
          .fontWeight(FontWeight.Bolder)
          .fontColor(AppColors.textPrimary)

        Image($r('app.media.ic_expand_more'))
          .width(18)
          .height(18)
          .fillColor(AppColors.textSecondary)
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(AppColors.darkSurfaceHighest70)
      .borderRadius(12)
      .onClick(() => {
        promptAction.showToast({ message: '当前数据源：官方免费短剧（独立直连）' });
      })

      Blank()

      // 右侧操作按钮：榜单与搜索
      Row({ space: 8 }) {
        // 榜单按钮
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_rankings'))
            .width(20)
            .height(20)
            .fillColor(AppColors.textPrimary)
        }
        .backgroundColor(AppColors.transparent)
        .width(36)
        .height(36)
        .onClick(() => {
          router.pushUrl({ url: 'pages/rankings/RankingsPage' });
        })

        // 搜索按钮 (折叠/展开搜索栏)
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_search'))
            .width(20)
            .height(20)
            .fillColor(this.isSearchVisible ? AppColors.hongguoRed : AppColors.textPrimary)
        }
        .backgroundColor(this.isSearchVisible ? AppColors.redAlpha15 : AppColors.transparent)
        .width(36)
        .height(36)
        .onClick(() => {
          this.onToggleSearch();
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 38, bottom: 10 })
    .backgroundColor(AppColors.bgDark)
  }
}
