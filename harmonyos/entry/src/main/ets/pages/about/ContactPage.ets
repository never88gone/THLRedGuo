import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import pasteboard from '@ohos.pasteboard';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';

@Entry
@Component
struct ContactPage {
  private static readonly EMAIL_ADDRESS: string = 'hawapp@163.com';
  private static readonly GITHUB_URL: string = 'https://github.com/never88gone/THLRedGuo';
  private static readonly TELEGRAM_URL: string = 'https://t.me/thlredguo';
  private static readonly TELEGRAM_CHANNEL: string = '@thlredguo';

  private copyText(text: string, label: string): void {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(pasteData);
      promptAction.showToast({ message: `已复制 ${label}：${text}` });
    } catch (_) {
      promptAction.showToast({ message: `已复制 ${label}` });
    }
  }

  @Builder
  CompactChannelTile(icon: string, title: string, value: string, hint: string, copyLabel: string, copyValue: string) {
    Row({ space: 12 }) {
      // 左侧图标容器
      Column() {
        Text(icon)
          .fontSize(20)
      }
      .width(40)
      .height(40)
      .borderRadius(10)
      .backgroundColor(AppColors.redAlpha12)
      .justifyContent(FlexAlign.Center)

      // 中间文本区
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(title)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
        }

        Text(value)
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.hongguoRed)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(hint)
          .fontSize(11)
          .fontColor(AppColors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧复制操作按钮
      Button('复制')
        .fontSize(11.5)
        .fontColor(AppColors.white)
        .backgroundColor(AppColors.hongguoRed)
        .borderRadius(13)
        .height(26)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          this.copyText(copyValue, copyLabel);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(AppColors.bgCard)
    .borderRadius(AppDimensions.radiusMd)
  }

  @Builder
  CompactInfoRow(title: string, detail: string) {
    Row({ space: 8 }) {
      Text('•')
        .fontSize(13)
        .fontColor(AppColors.hongguoRed)
        .margin({ top: -1 })

      Text(`${title}：`)
        .fontSize(11.5)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary)

      Text(detail)
        .fontSize(11.5)
        .fontColor(AppColors.textSecondary)
        .layoutWeight(1)
        .lineHeight(16)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
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

        Text('联系方式')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .margin({ left: 12 })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 8 })

      // 单屏紧凑内容区域
      Scroll() {
        Column({ space: 10 }) {
          // 1. 官方支持邮箱
          this.CompactChannelTile(
            '✉️',
            '官方支持与反馈邮箱',
            ContactPage.EMAIL_ADDRESS,
            '使用咨询、版权与技术反馈',
            '邮箱地址',
            ContactPage.EMAIL_ADDRESS
          )

          // 2. GitHub 官方开源代码仓库
          this.CompactChannelTile(
            '🐙',
            'GitHub 官方开源代码仓库',
            ContactPage.GITHUB_URL,
            '源码开源、Issue 反馈与技术探讨',
            '仓库链接',
            ContactPage.GITHUB_URL
          )

          // 3. Telegram 官方交流频道
          this.CompactChannelTile(
            '✈️',
            'Telegram 官方交流频道',
            `${ContactPage.TELEGRAM_CHANNEL} (${ContactPage.TELEGRAM_URL})`,
            '版本发布、功能预告与日常交流',
            '频道链接',
            ContactPage.TELEGRAM_URL
          )

          // 4. 交流与反馈说明卡片
          Column({ space: 8 }) {
            Row({ space: 6 }) {
              Text('ℹ️')
                .fontSize(14)
              Text('交流与反馈说明')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.textPrimary)
            }
            .width('100%')

            this.CompactInfoRow('功能体验与建议', '欢迎分享您的观看体验与改进设想，共同完善软件功能。')
            this.CompactInfoRow('异常与排查诊断', '若遇播放失败，可在【设置 - 数据源诊断】中复制脱敏报告协助排查。')
            this.CompactInfoRow('开源社区与共建', '遵循开源规范透明维护，技术探讨与反馈欢迎通过邮件与 GitHub 交流。')
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 16, right: 16, top: 6, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
