import { AppColors } from '../../../common/AppColors';

@Component
export struct SettingsBackupSection {
  onShowBackupDialog: () => void = () => {};

  build() {
    Column({ space: 1 }) {
      Text('数据与备份')
        .fontSize(13)
        .fontColor(AppColors.hongguoRed)
        .fontWeight(FontWeight.Bold)
        .padding({ left: 4, bottom: 6 })

      Row() {
        Column({ space: 4 }) {
          Text('备份与恢复')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('导出完整配置、恢复追剧记录与网络调度设置')
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
      .borderRadius(12)
      .onClick(() => {
        this.onShowBackupDialog();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
