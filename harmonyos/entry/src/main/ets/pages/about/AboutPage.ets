import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';
import { Constants } from '../../common/Constants';
import { AppUpdateService, AppUpdateInfo } from '../../core/update/AppUpdateService';

@Entry
@Component
struct AboutPage {
  private checkUpdate(): void {
    promptAction.showToast({ message: '正在从 GitHub Releases 检测最新版本...' });
    AppUpdateService.getInstance().checkUpdate()
      .then((info: AppUpdateInfo) => {
        if (info.hasUpdate) {
          const targetUrl = info.primaryAsset ? info.primaryAsset.downloadUrl : info.htmlUrl;
          const notes = info.releaseNotes ? ('\n\n更新说明:\n' + info.releaseNotes.substring(0, 300)) : '';
          promptAction.showDialog({
            title: `发现新版本: ${info.title}`,
            message: `当前版本: v${info.currentVersion} (Build ${info.currentBuild})\n最新版本: v${info.remoteVersion} (Build ${info.remoteBuild})${notes}`,
            buttons: [
              { text: '前往下载', color: AppColors.hongguoRed },
              { text: '稍后再说', color: AppColors.textSecondary }
            ]
          }, (err, data) => {
            if (!err && data.index === 0) {
              const ctx = getContext(this) as common.UIAbilityContext;
              AppUpdateService.getInstance().openUpdateUrl(ctx, targetUrl);
            }
          });
        } else {
          promptAction.showToast({ message: `当前版本 v${info.currentVersion} (Build ${info.currentBuild}) 已是最新` });
        }
      })
      .catch(() => {
        promptAction.showToast({ message: '检查更新失败，请检查网络或稍后重试' });
      });
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

        Text(`关于 ${Constants.APP_NAME}`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .margin({ left: 12 })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 12 })

      // 内容区域
      Scroll() {
        Column({ space: 20 }) {
          // 1. 应用 Logo 与简介
          Column({ space: 10 }) {
            Image($r('app.media.startIcon'))
              .width(88)
              .height(88)
              .borderRadius(22)

            Text(Constants.APP_NAME)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Text('全平台独立短剧与流媒体聚合')
              .fontSize(13)
              .fontColor(AppColors.textSecondary)
          }
          .width('100%')
          .padding({ top: 16, bottom: 8 })
          .alignItems(HorizontalAlign.Center)

          // 2. 版本号与检查更新卡片
          Column() {
            Row() {
              Column({ space: 4 }) {
                Text('应用版本')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.textPrimary)
                Text(`v${Constants.APP_VERSION} (Build ${Constants.APP_BUILD_NUMBER})`)
                  .fontSize(13)
                  .fontColor(AppColors.hongguoRed)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 14, bottom: 14 })

            Divider()
              .color(AppColors.divider)
              .height(1)

            Row() {
              Column({ space: 4 }) {
                Text('检查新版本')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.textPrimary)
                Text('从 GitHub Releases 检测最新版本与更新日志')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('>')
                .fontSize(14)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 14, bottom: 14 })
            .onClick(() => {
              this.checkUpdate();
            })
          }
          .width('100%')
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)

          // 3. 技术架构与设计规范
          Column({ space: 10 }) {
            Text('技术架构与设计规范')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Text('• 平台：HarmonyOS NEXT (API 12+) 原生 ArkTS / Stage 模型\n' +
                 '• 播放：系统级媒体框架 AVPlayer + 原生 XComponent 渲染\n' +
                 '• 解密：CENC AES-128-CTR 端侧硬件解密引擎\n' +
                 '• 存储：首选项（Preferences）本地持久化，无中心化自建服务')
              .fontSize(13)
              .fontColor(AppColors.textSecondary)
              .lineHeight(20)
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)
          .alignItems(HorizontalAlign.Start)

          // 4. 免责声明 (Disclaimer)
          Column({ space: 10 }) {
            Text('免责声明 (Disclaimer)')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.warning)

            Text('1. 本软件仅供移动端与大屏端跨平台编程技术学习、个人研究及非商业测试使用；\n' +
                 '2. 本软件为纯本地客户端工具，开发者不提供、不存储、不修改任何网络音视频内容，所有媒体数据均来源于网络公开接口；\n' +
                 '3. 媒体内容及相关版权均归原版权方所有，请自觉支持正版内容；\n' +
                 '4. 使用者因个人使用行为产生的一切法律责任及版权纠纷均由使用者自行承担，与软件开发者无关。')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .lineHeight(19)
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)
          .alignItems(HorizontalAlign.Start)

          // 5. 版权信息
          Text(`Copyright © 2026 ${Constants.APP_NAME}. All rights reserved.`)
            .fontSize(11)
            .fontColor(AppColors.textMuted)
            .margin({ top: 12, bottom: 24 })
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
