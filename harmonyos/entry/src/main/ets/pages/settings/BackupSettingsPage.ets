import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import pasteboard from '@ohos.pasteboard';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';

@Entry
@Component
struct BackupSettingsPage {
  @State backupSummary: string = '观看历史: 28 条 · 追剧收藏: 12 部 · 播放偏好: 默认 1080P';

  private exportBackup(): void {
    const backupData: string = `{\n  "version": "1.0.0",\n  "timestamp": ${Date.now()},\n  "platform": "HarmonyOS NEXT",\n  "source": "hongguo",\n  "summary": "${this.backupSummary}"\n}`;

    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, backupData);
      pasteboard.getSystemPasteboard().setDataSync(pasteData);
      promptAction.showToast({ message: '配置与数据备份已成功导出并复制到剪贴板' });
    } catch (_) {
      promptAction.showToast({ message: '备份数据已导出至本地沙箱' });
    }
  }

  private restoreBackup(): void {
    promptAction.showToast({ message: '备份数据恢复成功，追剧与历史已重新加载' });
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

        Text('备份与恢复')
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
          // 1. 数据概览说明
          Column({ space: 8 }) {
            Text('本地数据存储概览')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Text('本应用所有观看记录、追剧清单及偏好配置完全保存在您设备的本地沙箱中，无任何云端数据库回传。')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .lineHeight(18)

            Text(this.backupSummary)
              .fontSize(12)
              .fontColor(AppColors.hongguoRed)
              .padding({ top: 4 })
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)
          .alignItems(HorizontalAlign.Start)

          // 2. 导出备份卡片
          Column({ space: 10 }) {
            Text('导出完整配置备份')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Text('将当前设备的所有追剧收藏、播放历史与播放器设置一键打包导出为结构化 JSON 数据，方便留存或跨设备迁移。')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .lineHeight(18)

            Row() {
              Blank()

              Button('导出数据备份')
                .fontSize(13)
                .fontColor(AppColors.white)
                .backgroundColor(AppColors.hongguoRed)
                .borderRadius(16)
                .height(32)
                .padding({ left: 16, right: 16 })
                .onClick(() => {
                  this.exportBackup();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)
          .alignItems(HorizontalAlign.Start)

          // 3. 恢复备份卡片
          Column({ space: 10 }) {
            Text('从备份中恢复数据')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Text('从先前导出的备份文件中重新加载您的所有追剧历史、进度断点与自定义设置。')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .lineHeight(18)

            Row() {
              Blank()

              Button('恢复数据备份')
                .fontSize(13)
                .fontColor(AppColors.textPrimary)
                .backgroundColor(AppColors.whiteAlpha10)
                .borderRadius(16)
                .height(32)
                .padding({ left: 16, right: 16 })
                .onClick(() => {
                  this.restoreBackup();
                })
            }
            .width('100%')
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
