import { AppColors } from '../../../common/AppColors';

@Component
export struct SettingsStorageSection {
  @Prop wifiOnlyDownload: boolean = true;
  @Prop cacheSize: string = '0.0 MB';
  onToggleWifiOnly: (isOn: boolean) => void = () => {};
  onShowDownloads: () => void = () => {};
  onClearCache: () => void = () => {};

  build() {
    Column({ space: 1 }) {
      Text('离线与存储')
        .fontSize(13)
        .fontColor(AppColors.hongguoRed)
        .fontWeight(FontWeight.Bold)
        .padding({ left: 4, bottom: 6 })

      // 仅在 Wi-Fi 下下载
      Row() {
        Column({ space: 4 }) {
          Text('离线下载偏好')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('仅在 Wi-Fi 网络下下载视频')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.wifiOnlyDownload })
          .selectedColor(AppColors.hongguoRed)
          .onChange((isOn: boolean) => {
            this.onToggleWifiOnly(isOn);
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(AppColors.bgCard)
      .borderRadius({ topLeft: 12, topRight: 12 })

      // 存储空间与下载目录
      Row() {
        Column({ space: 4 }) {
          Text('存储空间与下载目录')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text(`查看离线短剧空间占用与缓存（当前占用：${this.cacheSize}）`)
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('清理 >')
          .fontSize(13)
          .fontColor(AppColors.hongguoRed)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .backgroundColor(AppColors.bgCard)
      .onClick(() => {
        this.onClearCache();
      })

      // 离线下载管理
      Row() {
        Column({ space: 4 }) {
          Text('离线下载管理')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('进入离线缓存列表查看已下载短剧')
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
        this.onShowDownloads();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
