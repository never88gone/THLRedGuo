import router from '@ohos.router';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';

interface VersionItem {
  version: string;
  date: string;
  badge: string;
  highlights: string[];
}

@Entry
@Component
struct ReleaseNotesPage {
  private readonly releaseHistory: VersionItem[] = [
    {
      version: 'v1.0.0',
      date: '2026-11-15',
      badge: '当前最新',
      highlights: [
        '采用纯血鸿蒙 HarmonyOS NEXT (API 12+) 原生 ArkTS / Stage 模型全新重构',
        '接入官方短剧规范数据源 hongguo.js，端侧独立沙箱执行',
        '支持 CENC AES-128-CTR 硬件级视频流解密与 1080P 高清流畅起播',
        '实现沉浸式推荐短剧流上滑无缝切集与首帧秒开体验',
        '支持官方二维码扫码登录、状态轮询与账号数据持久化',
        '设置页全功能全面重构为原生二级页面，对齐多端一致交互体验',
        '严格遵守单文件单类、行数解耦与集中色彩管理规范'
      ]
    },
    {
      version: 'v0.9.8',
      date: '2026-11-03',
      badge: '公测版本',
      highlights: [
        '接入官方数据源动态签名与沙箱调用机制',
        '支持沉浸全屏双击播放/暂停、滑动调节亮度与音量手势',
        '支持历史记录、追剧收藏与本地首选项存储'
      ]
    },
    {
      version: 'v0.9.0',
      date: '2026-10-23',
      badge: '首版原型',
      highlights: [
        '完成纯端侧无中心化代理服务的架构设计',
        '支持短剧列表浏览、搜索与分集切换'
      ]
    }
  ];

  @Builder
  VersionCard(item: VersionItem) {
    Column({ space: 12 }) {
      Row() {
        Text(item.version)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)

        Text(item.badge)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.white)
          .backgroundColor(item.badge === '当前最新' ? AppColors.hongguoRed : AppColors.whiteAlpha20)
          .borderRadius(10)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .margin({ left: 10 })

        Blank()

        Text(item.date)
          .fontSize(12)
          .fontColor(AppColors.textSecondary)
      }
      .width('100%')

      Divider()
        .color(AppColors.divider)
        .height(1)

      Column({ space: 8 }) {
        ForEach(item.highlights, (highlight: string, index: number) => {
          Row() {
            Text('• ')
              .fontSize(14)
              .fontColor(AppColors.hongguoRed)
              .fontWeight(FontWeight.Bold)

            Text(highlight)
              .fontSize(13)
              .fontColor(AppColors.textSecondary)
              .lineHeight(19)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (highlight: string) => highlight)
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppDimensions.paddingMd)
    .backgroundColor(AppColors.bgCard)
    .borderRadius(AppDimensions.radiusMd)
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_arrow_back'))
            .width(20)
            .height(20)
            .fillColor(AppColors.white)
        }
        .width(36)
        .height(36)
        .backgroundColor(AppColors.whiteAlpha10)
        .onClick(() => {
          router.back();
        })

        Text('更新内容')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .margin({ left: 12 })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 12 })

      // 内容列表
      Scroll() {
        Column({ space: 16 }) {
          ForEach(this.releaseHistory, (item: VersionItem) => {
            this.VersionCard(item);
          }, (item: VersionItem) => item.version)
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 40 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
