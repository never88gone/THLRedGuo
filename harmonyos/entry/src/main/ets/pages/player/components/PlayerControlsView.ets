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
  onOpenComments: () => void = () => {};

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

      // B. 居中现代化毛玻璃悬浮操作区 (对齐 Flutter commit b4b10ce)
      if (!this.isBuffering) {
        Row({ space: 24 }) {
          // 上一集 (轻量毛玻璃质感悬浮圆钮)
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_skip_previous'))
              .width(22)
              .height(22)
              .fillColor(AppColors.white)
          }
          .backgroundColor('rgba(35, 26, 22, 0.65)')
          .border({ width: 1.0, color: AppColors.whiteAlpha25 })
          .width(42)
          .height(42)
          .shadow({ radius: 12, color: AppColors.maskDark50 })
          .onClick(() => {
            this.onPrevious();
          })

          // 中央现代化毛玻璃质感主播放圆钮 (校准重心并支持微光按压弹性)
          Button({ type: ButtonType.Circle }) {
            Image(this.isPlaying ? $r('app.media.ic_pause') : $r('app.media.ic_play_arrow'))
              .width(30)
              .height(30)
              .fillColor(AppColors.white)
              .margin(this.isPlaying ? { left: 0 } : { left: 2 }) // 校准播放图标三角形视觉重心偏移
          }
          .backgroundColor(this.isPlaying ? 'rgba(46, 34, 29, 0.75)' : AppColors.hongguoRed)
          .border({ width: 1.5, color: this.isPlaying ? AppColors.whiteAlpha35 : 'rgba(255, 255, 255, 0.45)' })
          .width(56)
          .height(56)
          .shadow({ radius: 18, color: this.isPlaying ? AppColors.maskDark65 : AppColors.redAlpha15 })
          .onClick(() => {
            this.onTogglePlay();
          })

          // 下一集 (轻量毛玻璃质感悬浮圆钮)
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_skip_next'))
              .width(22)
              .height(22)
              .fillColor(AppColors.white)
          }
          .backgroundColor('rgba(35, 26, 22, 0.65)')
          .border({ width: 1.0, color: AppColors.whiteAlpha25 })
          .width(42)
          .height(42)
          .shadow({ radius: 12, color: AppColors.maskDark50 })
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
        // 工具栏行：评论 + 倍速 + 全屏按钮
        Row({ space: 10 }) {
          Blank()

          // 评论入口按钮 (对齐 Flutter commit e171586)
          Button({ type: ButtonType.Capsule }) {
            Row({ space: 4 }) {
              Text('💬')
                .fontSize(12)
              Text('评论')
                .fontSize(11.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.white)
            }
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          }
          .backgroundColor('rgba(35, 26, 22, 0.65)')
          .border({ width: 0.8, color: AppColors.whiteAlpha20 })
          .height(28)
          .onClick(() => {
            this.onOpenComments();
          })

          // 倍速切换胶囊
          Button(`${this.speed}x`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.white)
            .backgroundColor('rgba(35, 26, 22, 0.65)')
            .border({ width: 0.8, color: AppColors.whiteAlpha20 })
            .height(28)
            .padding({ left: 10, right: 10 })
            .borderRadius(14)
            .onClick(() => {
              this.onCycleSpeed();
            })

          // 全屏切换按钮
          Button({ type: ButtonType.Circle }) {
            Image(this.isFullscreen ? $r('app.media.ic_fullscreen_exit') : $r('app.media.ic_fullscreen'))
              .width(18)
              .height(18)
              .fillColor(AppColors.white)
          }
          .backgroundColor('rgba(35, 26, 22, 0.65)')
          .border({ width: 0.8, color: AppColors.whiteAlpha20 })
          .width(32)
          .height(32)
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
