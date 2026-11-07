import { AppColors } from '../common/AppTheme';
import { HomePage } from './home/HomePage';
import { VideoFeedPage } from './feed/VideoFeedPage';
import { AccountPage } from './account/AccountPage';
import { DownloadsPage } from './downloads/DownloadsPage';
import { SettingsPage } from './settings/SettingsPage';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  private controller: TabsController = new TabsController();

  @Builder
  TabBuilder(title: string, index: number, iconRes: Resource) {
    Column({ space: 3 }) {
      Image(iconRes)
        .width(this.currentIndex === index ? 24 : 22)
        .height(this.currentIndex === index ? 24 : 22)
        .fillColor(this.currentIndex === index ? AppColors.hongguoRed : AppColors.textSecondaryDark)

      Text(title)
        .fontSize(11)
        .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? AppColors.hongguoRed : AppColors.textSecondaryDark)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppColors.bottomNavBg)
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
        TabContent() {
          HomePage()
        }
        .tabBar(this.TabBuilder('发现', 0, $r('app.media.nav_explore')))

        TabContent() {
          VideoFeedPage()
        }
        .tabBar(this.TabBuilder('推荐', 1, $r('app.media.nav_recommend')))

        TabContent() {
          AccountPage()
        }
        .tabBar(this.TabBuilder('我的', 2, $r('app.media.nav_account')))

        TabContent() {
          DownloadsPage()
        }
        .tabBar(this.TabBuilder('下载', 3, $r('app.media.nav_download')))

        TabContent() {
          SettingsPage()
        }
        .tabBar(this.TabBuilder('设置', 4, $r('app.media.nav_settings')))
      }
      .barHeight(66)
      .barBackgroundColor(AppColors.bottomNavBg)
      .animationDuration(200)
      .onChange((index: number) => {
        this.currentIndex = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
