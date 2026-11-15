import router from '@ohos.router';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';
import { Constants } from '../../common/Constants';

interface IntroFeature {
  title: string;
  desc: string;
}

@Entry
@Component
struct AppIntroPage {
  private readonly features: IntroFeature[] = [
    {
      title: '端侧闭环解析',
      desc: '内置独立 JavaScript 沙箱环境与解密驱动，站源协议实时动态执行，毫秒级直接获取高清直链。'
    },
    {
      title: '多端全场景适配',
      desc: '针对触屏手势、电脑键鼠与电视遥控器进行专用 UI 布局优化，支持沉浸全屏及大屏焦点漫游。'
    },
    {
      title: '极速播放与倍速切换',
      desc: '底层集成硬件加速解码引擎，支持 0.5x ~ 2.0x 多档流畅倍速即时生效与记忆保存。'
    },
    {
      title: '个性化实时弹幕',
      desc: '支持弹幕字体比例、透明度及显示区域自由调节，长按弹幕按钮随时唤起快速设置。'
    },
    {
      title: '并发离线下载',
      desc: '支持全集批量队列调度、断点续传与离线播放，通勤旅途无网环境下随时畅快追剧。'
    },
    {
      title: '本地隐私与保险箱',
      desc: '观看进度与追剧收藏全部保存在本地，支持配置独立手势密码与私密安全锁。'
    }
  ];

  private readonly tips: string[] = [
    '双击屏幕中央快速暂停或恢复播放；',
    '推荐页上下滑动无缝切换下一部热门短剧；',
    '短剧播放页轻触右上方选集按钮快速跨集跳转；',
    '支持 1080P/720P/480P 多清晰度起播记忆。'
  ];

  @Builder
  FeatureRow(item: IntroFeature) {
    Column({ space: 4 }) {
      Row() {
        Text('★ ')
          .fontSize(14)
          .fontColor(AppColors.hongguoRed)

        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
      }

      Text(item.desc)
        .fontSize(13)
        .fontColor(AppColors.textSecondary)
        .lineHeight(19)
        .padding({ left: 16 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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

        Text('应用说明')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .margin({ left: 12 })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 12 })

      Scroll() {
        Column({ space: 16 }) {
          // 1. 应用定位
          Column({ space: 10 }) {
            Row() {
              Image($r('app.media.startIcon'))
                .width(44)
                .height(44)
                .borderRadius(10)

              Column({ space: 3 }) {
                Text(Constants.APP_NAME)
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.textPrimary)

                Text('全平台独立短剧与流媒体聚合')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .margin({ left: 12 })
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')

            Divider()
              .color(AppColors.divider)
              .height(1)

            Text('本应用专注于提供沉浸、纯粹、高效的短剧视听体验。所有网络请求、站源解析、加密解密和流媒体调度均在您的设备本地端侧直接完成，不依赖任何第三方远程自建代理服务，充分保障运行速度与个人私密性。')
              .fontSize(13)
              .fontColor(AppColors.textSecondary)
              .lineHeight(20)
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)

          // 2. 核心特性与优势
          Column({ space: 14 }) {
            Text('核心特性与优势')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            ForEach(this.features, (feature: IntroFeature) => {
              this.FeatureRow(feature);
            }, (feature: IntroFeature) => feature.title)
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)
          .alignItems(HorizontalAlign.Start)

          // 3. 常用操作技巧
          Column({ space: 10 }) {
            Text('常用操作技巧')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.warning)

            ForEach(this.tips, (tip: string) => {
              Row() {
                Text('• ')
                  .fontSize(14)
                  .fontColor(AppColors.warning)

                Text(tip)
                  .fontSize(13)
                  .fontColor(AppColors.textSecondary)
                  .lineHeight(19)
                  .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }, (tip: string) => tip)
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 16, right: 16, top: 4, bottom: 40 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
