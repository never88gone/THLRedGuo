import { AppColors } from '../../../common/AppColors';

@Component
export struct SettingsDisplaySection {
  @Prop displayMode: string = '';
  @Prop themeMode: string = '';
  onShowDisplayModePicker: () => void = () => {};
  onShowThemePicker: () => void = () => {};

  build() {
    Column({ space: 1 }) {
      Text('界面与显示')
        .fontSize(13)
        .fontColor(AppColors.hongguoRed)
        .fontWeight(FontWeight.Bold)
        .padding({ left: 4, bottom: 6 })

      // 页面模式
      Row() {
        Column({ space: 4 }) {
          Text('页面模式')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text(`当前：${this.displayMode} · 电视、手机或电脑适配`)
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
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .backgroundColor(AppColors.bgCard)
      .borderRadius({ topLeft: 12, topRight: 12 })
      .onClick(() => {
        this.onShowDisplayModePicker();
      })

      // 外观与主题
      Row() {
        Column({ space: 4 }) {
          Text('外观与主题')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text(`当前：${this.themeMode} · 深色模式与品牌色彩`)
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
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .backgroundColor(AppColors.bgCard)
      .borderRadius({ bottomLeft: 12, bottomRight: 12 })
      .onClick(() => {
        this.onShowThemePicker();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
