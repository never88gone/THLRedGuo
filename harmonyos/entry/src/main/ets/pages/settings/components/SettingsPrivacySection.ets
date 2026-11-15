import { AppColors } from '../../../common/AppColors';

@Component
export struct SettingsPrivacySection {
  onShowPrivacyLock: () => void = () => {};
  onClearHistory: () => void = () => {};

  build() {
    Column({ space: 1 }) {
      Text('隐私与安全')
        .fontSize(13)
        .fontColor(AppColors.hongguoRed)
        .fontWeight(FontWeight.Bold)
        .padding({ left: 4, bottom: 6 })

      // 手势密码
      Row() {
        Column({ space: 4 }) {
          Text('手势密码与隐私短剧库')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('手势隐私锁 · 隐私短剧库密码保护')
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
        this.onShowPrivacyLock();
      })

      // 清除观看与搜索历史
      Row() {
        Column({ space: 4 }) {
          Text('清除观看与搜索历史')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('一键清空本地观看进度与搜索记录')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('清空 >')
          .fontSize(13)
          .fontColor(AppColors.hongguoRed)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .backgroundColor(AppColors.bgCard)
      .borderRadius({ bottomLeft: 12, bottomRight: 12 })
      .onClick(() => {
        this.onClearHistory();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
