import { AppColors } from '../../../common/AppColors';

@Component
export struct SettingsSourceSection {
  onShowSourceSwitcher: () => void = () => {};
  onShowJsManagement: () => void = () => {};
  onRunDiagnostics: () => void = () => {};

  build() {
    Column({ space: 1 }) {
      Text('数据源与插件')
        .fontSize(13)
        .fontColor(AppColors.hongguoRed)
        .fontWeight(FontWeight.Bold)
        .padding({ left: 4, bottom: 6 })

      // 切换当前数据源
      Row() {
        Column({ space: 4 }) {
          Text('切换当前数据源')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('当前正在使用：官方免费短剧 · 轻触切换可用站源')
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
        this.onShowSourceSwitcher();
      })

      // JS 数据源插件管理
      Row() {
        Column({ space: 4 }) {
          Text('JS 数据源插件管理')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('独立沙箱运行 · 官方规范短剧数据源 (hongguo.js)')
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
      .onClick(() => {
        this.onShowJsManagement();
      })

      // 网络与数据源诊断
      Row() {
        Column({ space: 4 }) {
          Text('网络与数据源诊断')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('检测网络连通性、DNS、JS引擎与搜索详情，生成详细报告')
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
        this.onRunDiagnostics();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
