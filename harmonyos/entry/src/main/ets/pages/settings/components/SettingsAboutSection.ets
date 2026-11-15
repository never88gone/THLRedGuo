import { AppColors } from '../../../common/AppColors';

@Component
export struct SettingsAboutSection {
  @Prop appVersion: string = '';
  @Prop appBuild: string = '';
  onCheckUpdate: () => void = () => {};
  onShowReleaseNotes: () => void = () => {};
  onShowAppIntro: () => void = () => {};
  onShowContact: () => void = () => {};
  onShowThirdParty: () => void = () => {};
  onShowDiary: () => void = () => {};
  onShowAbout: () => void = () => {};

  build() {
    Column({ space: 1 }) {
      Text('关于与支持')
        .fontSize(13)
        .fontColor(AppColors.hongguoRed)
        .fontWeight(FontWeight.Bold)
        .padding({ left: 4, bottom: 6 })

      // 检查新版本
      Row() {
        Column({ space: 4 }) {
          Text('检查新版本')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('检测官方 GitHub 最新版本及各端安装包')
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
        this.onCheckUpdate();
      })

      // 更新内容
      Row() {
        Column({ space: 4 }) {
          Text('更新内容')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('版本历程 · 每次版本与功能的更新记录')
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
        this.onShowReleaseNotes();
      })

      // 应用说明
      Row() {
        Column({ space: 4 }) {
          Text('应用说明')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('核心功能特性、架构说明与使用技巧')
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
        this.onShowAppIntro();
      })

      // 联系方式
      Row() {
        Column({ space: 4 }) {
          Text('联系方式')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('官方邮箱 · GitHub 开源 · Telegram 交流')
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
        this.onShowContact();
      })

      // 第三方开源组件
      Row() {
        Column({ space: 4 }) {
          Text('第三方开源组件')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('核心开源库、开源许可证与授权声明')
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
        this.onShowThirdParty();
      })

      // 播放诊断日记
      Row() {
        Column({ space: 4 }) {
          Text('播放诊断日记')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('查看原生解码、流媒体握手与解密运行轨迹')
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
        this.onShowDiary();
      })

      // 关于 糖葫芦Haw
      Row() {
        Column({ space: 4 }) {
          Text('关于 糖葫芦Haw')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text(`v${this.appVersion} (Build ${this.appBuild})`)
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
        this.onShowAbout();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
