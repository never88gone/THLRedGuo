import { AppColors } from '../../../common/AppColors';

function formatTime(ms: number): string {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(totalSeconds / 60);
  const s = totalSeconds % 60;
  const mm = m < 10 ? `0${m}` : `${m}`;
  const ss = s < 10 ? `0${s}` : `${s}`;
  return `${mm}:${ss}`;
}

@Component
export struct PlayerControlsView {
  @Prop dramaTitle: string = '';
  @Prop currentEpisodeIndex: number = 1;
  @Prop isPlaying: boolean = false;
  @Prop isBuffering: boolean = false;
  @Prop isFullscreen: boolean = false;
  @Prop speed: number = 1.0;
  @Prop currentPosition: number = 0;
  @Prop duration: number = 0;

  onBack: () => void = () => {};
  onPrevious: () => void = () => {};
  onTogglePlay: () => void = () => {};
  onNext: () => void = () => {};
  onCycleSpeed: () => void = () => {};
  onToggleFullscreen: () => void = () => {};
  onSeek: (val: number) => void = () => {};

  build() {
    Column() {
      // A. 顶部导航栏 (PlayerTopBarView: 左侧半透明圆形返回按钮 + 剧集标题)
      Row({ space: 10 }) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_arrow_back'))
            .width(20)
            .height(20)
            .fillColor(AppColors.white)
        }
        .backgroundColor(AppColors.maskDark45)
        .border({ width: 0.8, color: AppColors.whiteAlpha20 })
        .width(36)
        .height(36)
        .onClick(() => {
          this.onBack();
        })

        Column({ space: 2 }) {
          Text(this.dramaTitle || '正在播放')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`第 ${this.currentEpisodeIndex} 集`)
            .fontSize(11)
            .fontColor(AppColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 8 })
      .backgroundColor(AppColors.maskDark45)

      Blank()

      // B. 居中操作区 (PlayerCenterView: 上一集 + 播放/暂停 + 下一集)
      if (!this.isBuffering) {
        Row({ space: 28 }) {
          // 上一集
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_skip_previous'))
              .width(24)
              .height(24)
              .fillColor(AppColors.white)
          }
          .backgroundColor(AppColors.maskDark45)
          .border({ width: 0.8, color: AppColors.whiteAlpha20 })
          .width(44)
          .height(44)
          .onClick(() => {
            this.onPrevious();
          })

          // 中央大播放/暂停按键
          Button({ type: ButtonType.Circle }) {
            Image(this.isPlaying ? $r('app.media.ic_pause') : $r('app.media.ic_play_arrow'))
              .width(32)
              .height(32)
              .fillColor(AppColors.white)
          }
          .backgroundColor(AppColors.controlsBg)
          .border({ width: 1.2, color: AppColors.whiteAlpha35 })
          .width(58)
          .height(58)
          .shadow({ radius: 16, color: AppColors.maskDark50 })
          .onClick(() => {
            this.onTogglePlay();
          })

          // 下一集
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_skip_next'))
              .width(24)
              .height(24)
              .fillColor(AppColors.white)
          }
          .backgroundColor(AppColors.maskDark45)
          .border({ width: 0.8, color: AppColors.whiteAlpha20 })
          .width(44)
          .height(44)
          .onClick(() => {
            this.onNext();
          })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }

      Blank()

      // C. 底部工具栏与进度条
      Column({ space: 4 }) {
        // 工具栏行：倍速 + 全屏按钮
        Row({ space: 10 }) {
          Blank()

          // 倍速切换胶囊
          Button(`${this.speed}x`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.white)
            .backgroundColor(AppColors.maskDark45)
            .border({ width: 0.8, color: AppColors.whiteAlpha20 })
            .height(30)
            .padding({ left: 12, right: 12 })
            .borderRadius(15)
            .onClick(() => {
              this.onCycleSpeed();
            })

          // 全屏切换按钮
          Button({ type: ButtonType.Circle }) {
            Image(this.isFullscreen ? $r('app.media.ic_fullscreen_exit') : $r('app.media.ic_fullscreen'))
              .width(20)
              .height(20)
              .fillColor(AppColors.white)
          }
          .backgroundColor(AppColors.maskDark45)
          .border({ width: 0.8, color: AppColors.whiteAlpha20 })
          .width(34)
          .height(34)
          .onClick(() => {
            this.onToggleFullscreen();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        // 进度时间行
        Row({ space: 8 }) {
          Text(formatTime(this.currentPosition))
            .fontSize(11)
            .fontColor(AppColors.textPrimary)
            .width(40)
            .textAlign(TextAlign.End)

          Slider({
            value: this.currentPosition,
            min: 0,
            max: Math.max(1, this.duration),
            style: SliderStyle.OutSet
          })
            .blockColor(AppColors.hongguoRed)
            .trackColor(AppColors.whiteAlpha25)
            .selectedColor(AppColors.hongguoRed)
            .layoutWeight(1)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End) {
                this.onSeek(value);
              }
            })

          Text(formatTime(this.duration))
            .fontSize(11)
            .fontColor(AppColors.textSecondary)
            .width(40)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
      }
      .width('100%')
      .backgroundColor(AppColors.maskDark45)
    }
    .width('100%')
    .height('100%')
  }
}
