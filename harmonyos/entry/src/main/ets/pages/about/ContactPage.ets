import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import pasteboard from '@ohos.pasteboard';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';

@Entry
@Component
struct ContactPage {
  private static readonly EMAIL_ADDRESS: string = 'support@thltv.com';
  private static readonly GITHUB_URL: string = 'https://github.com/never88gone/THLRedGuo';
  private static readonly TELEGRAM_URL: string = 'https://t.me/tanghulutvos';
  private static readonly TELEGRAM_GROUP: string = '@tanghulutvos';

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
  ContactCard(title: string, value: string, hint: string, copyLabel: string, copyValue: string) {
    Column({ space: 10 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary)

      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.hongguoRed)

      Text(hint)
        .fontSize(12)
        .fontColor(AppColors.textSecondary)
        .lineHeight(18)

      Row() {
        Blank()

        Button(`复制${copyLabel}`)
          .fontSize(12)
          .fontColor(AppColors.white)
          .backgroundColor(AppColors.hongguoRed)
          .borderRadius(14)
          .height(28)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            this.copyText(copyValue, copyLabel);
          })
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

        Text('联系方式')
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
        Column({ space: 16 }) {
          // 1. 官方支持与反馈邮箱
          this.ContactCard(
            '官方支持与反馈邮箱',
            ContactPage.EMAIL_ADDRESS,
            '商务合作、使用咨询、版权与技术反馈，欢迎来信沟通。',
            '邮箱地址',
            ContactPage.EMAIL_ADDRESS
          )

          // 2. GitHub 官方开源代码仓库
          this.ContactCard(
            'GitHub 官方开源代码仓库',
            ContactPage.GITHUB_URL,
            '欢迎提交 Issue、参与开源共建或 Star 关注支持项目开发。',
            '仓库链接',
            ContactPage.GITHUB_URL
          )

          // 3. Telegram 官方交流群组
          this.ContactCard(
            'Telegram 官方交流群组',
            `${ContactPage.TELEGRAM_GROUP} (${ContactPage.TELEGRAM_URL})`,
            '加入官方讨论组，参与新功能体验、测试反馈与交流。',
            '群组链接',
            ContactPage.TELEGRAM_URL
          )

          // 4. 反馈须知与说明
          Column({ space: 8 }) {
            Text('反馈须知与说明')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Text('1. 问题反馈请尽可能附带设备型号（如 HarmonyOS NEXT）、系统版本及具体复现步骤；\n' +
                 '2. 短剧版权归各原版权方所有，如涉及版权事宜请直接通过官方邮箱联系；\n' +
                 '3. 开发者会在工作日尽快查收并跟进所有有效信件。')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .lineHeight(18)
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 16, right: 16, top: 12, bottom: 40 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
