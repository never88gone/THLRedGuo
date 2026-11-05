import { AppColors } from '../common/AppTheme';
import { HomePage } from './home/HomePage';
import { VideoFeedPage } from './feed/VideoFeedPage';
import { RankingsPage } from './rankings/RankingsPage';
import { AccountPage } from './account/AccountPage';
import { SettingsPage } from './settings/SettingsPage';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  private controller: TabsController = new TabsController();

  @Builder
  TabBuilder(title: string, index: number, emoji: string) {
    Column({ space: 2 }) {
      Text(emoji)
        .fontSize(18)
      Text(title)
        .fontSize(11)
        .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? AppColors.hongguoRed : AppColors.textSecondary)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
        TabContent() {
          HomePage()
        }
        .tabBar(this.TabBuilder('首页', 0, '🏠'))

        TabContent() {
          VideoFeedPage()
        }
        .tabBar(this.TabBuilder('推荐流', 1, '🎬'))

        TabContent() {
          RankingsPage()
        }
        .tabBar(this.TabBuilder('排行榜', 2, '🔥'))

        TabContent() {
          AccountPage()
        }
        .tabBar(this.TabBuilder('我的', 3, '👤'))

        TabContent() {
          SettingsPage()
        }
        .tabBar(this.TabBuilder('设置', 4, '⚙️'))
      }
      .barHeight(56)
      .barBackgroundColor(AppColors.bgCard)
      .animationDuration(200)
      .onChange((index: number) => {
        this.currentIndex = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
    .padding({ top: 38 })
  }
}
