import { AppColors } from '../../../common/AppColors';

@Component
export struct SettingsPlaybackSection {
  @Prop autoAdvance: boolean = true;
  @Prop selectedQuality: string = '1080P 超清';
  @Prop selectedSpeed: string = '1.0x (正常)';
  @Prop danmakuEnabled: boolean = true;
  @Prop pipEnabled: boolean = false;
  @Prop hardwareDecode: boolean = true;

  onToggleAutoAdvance: (isOn: boolean) => void = () => {};
  onShowQualityPicker: () => void = () => {};
  onShowSpeedPicker: () => void = () => {};
  onToggleDanmaku: (isOn: boolean) => void = () => {};
  onTogglePip: (isOn: boolean) => void = () => {};
  onToggleHardwareDecode: (isOn: boolean) => void = () => {};

  build() {
    Column({ space: 1 }) {
      Text('短剧播放')
        .fontSize(13)
        .fontColor(AppColors.hongguoRed)
        .fontWeight(FontWeight.Bold)
        .padding({ left: 4, bottom: 6 })

      // 播放设置
      Row() {
        Column({ space: 4 }) {
          Text('播放设置')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text(`默认 ${this.selectedQuality} · ${this.selectedSpeed} · 弹幕${this.danmakuEnabled ? '开启' : '关闭'}${this.pipEnabled ? ' · 画中画开启' : ''}`)
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
        this.onShowQualityPicker();
      })

      // 画中画模式
      Row() {
        Column({ space: 4 }) {
          Text('画中画模式')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text(this.pipEnabled ? '已开启画中画（切出应用或点击按钮悬浮播放）' : '已关闭（开启后可在播放器使用画中画小窗）')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.pipEnabled })
          .selectedColor(AppColors.hongguoRed)
          .onChange((isOn: boolean) => {
            this.onTogglePip(isOn);
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(AppColors.bgCard)

      // 自动连播开关
      Row() {
        Column({ space: 4 }) {
          Text('自动连播下一集')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('当前集播完后自动加载下一集')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.autoAdvance })
          .selectedColor(AppColors.hongguoRed)
          .onChange((isOn: boolean) => {
            this.onToggleAutoAdvance(isOn);
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(AppColors.bgCard)

      // 弹幕展示
      Row() {
        Column({ space: 4 }) {
          Text('短剧弹幕展示')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('在视频画面上方展示实时滚动的观众弹幕')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.danmakuEnabled })
          .selectedColor(AppColors.hongguoRed)
          .onChange((isOn: boolean) => {
            this.onToggleDanmaku(isOn);
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(AppColors.bgCard)

      // 硬件加速
      Row() {
        Column({ space: 4 }) {
          Text('硬件加速解码')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)
          Text('调用系统硬件解码器播放高清与超清片源')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.hardwareDecode })
          .selectedColor(AppColors.hongguoRed)
          .onChange((isOn: boolean) => {
            this.onToggleHardwareDecode(isOn);
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(AppColors.bgCard)
      .borderRadius({ bottomLeft: 12, bottomRight: 12 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
