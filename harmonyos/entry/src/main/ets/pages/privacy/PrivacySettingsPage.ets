import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';

@Entry
@Component
struct PrivacySettingsPage {
  @State privacyLockEnabled: boolean = false;
  @State hideInRecents: boolean = true;
  @State lockOnBackground: boolean = true;

  private togglePrivacyLock(isOn: boolean): void {
    this.privacyLockEnabled = isOn;
    if (isOn) {
      promptAction.showToast({ message: '手势隐私锁已启用，进入私密短剧库将验证手势' });
    } else {
      promptAction.showToast({ message: '手势隐私锁已关闭' });
    }
  }

  private resetGesture(): void {
    promptAction.showToast({ message: '请绘制新的 9 宫格手势密码' });
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

        Text('手势密码与隐私保护')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .margin({ left: 12 })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 12 })

      Scroll() {
        Column({ space: 16 }) {
          // 1. 手势锁总开关
          Column({ space: 12 }) {
            Row() {
              Column({ space: 4 }) {
                Text('启用手势隐私锁')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.textPrimary)

                Text('保护私密短剧收藏与核心偏好设置')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.privacyLockEnabled })
                .selectedColor(AppColors.hongguoRed)
                .onChange((isOn: boolean) => {
                  this.togglePrivacyLock(isOn);
                })
            }
            .width('100%')

            if (this.privacyLockEnabled) {
              Divider()
                .color(AppColors.divider)
                .height(1)

              Row() {
                Text('设置 / 修改手势图案')
                  .fontSize(14)
                  .fontColor(AppColors.textPrimary)

                Blank()

                Button('重置图案')
                  .fontSize(12)
                  .fontColor(AppColors.hongguoRed)
                  .backgroundColor(AppColors.whiteAlpha10)
                  .borderRadius(14)
                  .height(28)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => {
                    this.resetGesture();
                  })
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)

          // 2. 隐蔽与后台看护
          Column({ space: 12 }) {
            Text('隐私看护与防护策略')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Row() {
              Column({ space: 2 }) {
                Text('多任务列表卡片模糊隐蔽')
                  .fontSize(14)
                  .fontColor(AppColors.textPrimary)
                Text('切到系统多任务预览时不泄露视频画面')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.hideInRecents })
                .selectedColor(AppColors.hongguoRed)
                .onChange((isOn: boolean) => {
                  this.hideInRecents = isOn;
                })
            }
            .width('100%')

            Divider()
              .color(AppColors.divider)
              .height(1)

            Row() {
              Column({ space: 2 }) {
                Text('切后台立即加锁')
                  .fontSize(14)
                  .fontColor(AppColors.textPrimary)
                Text('离开应用后重新进入需重新绘制手势')
                  .fontSize(12)
                  .fontColor(AppColors.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.lockOnBackground })
                .selectedColor(AppColors.hongguoRed)
                .onChange((isOn: boolean) => {
                  this.lockOnBackground = isOn;
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)
          .alignItems(HorizontalAlign.Start)

          // 3. 隐私原则说明
          Column({ space: 8 }) {
            Text('端侧本地隐私原则')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Text('糖葫芦Haw 坚守纯端侧独立原则，不采集、不存储、不回传任何用户设备标识或观影偏好。所有数据均采用鸿蒙系统级 Preferences 本地加密存储。')
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
        .padding({ left: 16, right: 16, top: 4, bottom: 40 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
