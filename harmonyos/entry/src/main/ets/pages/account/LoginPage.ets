import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { QRLoginState } from '../../models/Account';
import { AccountService } from '../../core/account/AccountService';

@Entry
@Component
export struct LoginPage {
  @State selectedTab: number = 0; // 0: 扫码登录, 1: 手机号登录
  @State qrState: QRLoginState | null = null;
  @State isLoadingQr: boolean = false;

  @State phoneNumber: string = '';
  @State smsCode: string = '';
  @State countdown: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.refreshQrCode();
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
    }
  }

  async refreshQrCode(): Promise<void> {
    this.isLoadingQr = true;
    try {
      this.qrState = await AccountService.getInstance().requestQrCode();
    } catch (e) {
      promptAction.showToast({ message: '获取二维码失败' });
    }
    this.isLoadingQr = false;
  }

  async confirmMockQr(): Promise<void> {
    if (!this.qrState) return;
    const ok = await AccountService.getInstance().mockConfirmQr(this.qrState.token);
    if (ok) {
      promptAction.showToast({ message: '登录成功' });
      router.back();
    }
  }

  sendSmsCode(): void {
    if (!/^1\d{10}$/.test(this.phoneNumber.trim())) {
      promptAction.showToast({ message: '请输入正确的11位手机号' });
      return;
    }

    this.countdown = 60;
    promptAction.showToast({ message: '验证码已发送至手机: 8888' });
    this.smsCode = '8888';

    if (this.timer !== -1) {
      clearInterval(this.timer);
    }
    this.timer = setInterval(() => {
      this.countdown--;
      if (this.countdown <= 0) {
        clearInterval(this.timer);
        this.timer = -1;
      }
    }, 1000);
  }

  async doPhoneLogin(): Promise<void> {
    if (!this.phoneNumber.trim()) {
      promptAction.showToast({ message: '请输入手机号' });
      return;
    }
    if (!this.smsCode.trim()) {
      promptAction.showToast({ message: '请输入验证码' });
      return;
    }

    const success = await AccountService.getInstance().loginWithPhone(
      this.phoneNumber.trim(),
      this.smsCode.trim()
    );

    if (success) {
      promptAction.showToast({ message: '登录成功！' });
      router.back();
    } else {
      promptAction.showToast({ message: '登录失败，请检查验证码' });
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button('< 返回')
          .fontSize(14)
          .fontColor(AppColors.textPrimary)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            router.back();
          })

        Blank()

        Text('登录红果账号')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)

        Blank()

        // 占位保对称
        Text('      ')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      // 登录方式 Tab 切换
      Row() {
        Button('扫码登录')
          .layoutWeight(1)
          .fontSize(14)
          .fontWeight(this.selectedTab === 0 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selectedTab === 0 ? AppColors.hongguoRed : AppColors.textSecondary)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.selectedTab = 0;
          })

        Button('短信登录')
          .layoutWeight(1)
          .fontSize(14)
          .fontWeight(this.selectedTab === 1 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selectedTab === 1 ? AppColors.hongguoRed : AppColors.textSecondary)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.selectedTab = 1;
          })
      }
      .width('80%')
      .margin({ top: 16, bottom: 24 })
      .border({ width: { bottom: 1 }, color: AppColors.divider })

      // Tab 内容
      if (this.selectedTab === 0) {
        // 扫码登录区
        Column({ space: 16 }) {
          Text('使用红果短剧 App 扫码登录')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.textPrimary)

          // 二维码卡片容器
          Column() {
            if (this.isLoadingQr) {
              LoadingProgress()
                .width(48)
                .height(48)
                .color(AppColors.hongguoRed)
            } else {
              // 模拟二维码图块展示
              Stack({ alignContent: Alignment.Center }) {
                Column()
                  .width(180)
                  .height(180)
                  .backgroundColor(Color.White)
                  .borderRadius(AppDimensions.radiusMd)

                Text('📱\n[二维码]')
                  .fontSize(20)
                  .textAlign(TextAlign.Center)
                  .fontColor(Color.Black)
              }
            }
          }
          .width(210)
          .height(210)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusLg)
          .justifyContent(FlexAlign.Center)

          Row({ space: 12 }) {
            Button('刷新二维码')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .backgroundColor(AppColors.bgCard)
              .height(34)
              .borderRadius(17)
              .onClick(() => {
                this.refreshQrCode();
              })

            Button('模拟扫码成功')
              .fontSize(12)
              .fontColor(Color.White)
              .backgroundColor(AppColors.hongguoRed)
              .height(34)
              .borderRadius(17)
              .onClick(() => {
                this.confirmMockQr();
              })
          }
        }
        .width('100%')
        .padding(AppDimensions.paddingLg)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 手机验证码登录区
        Column({ space: 16 }) {
          // 手机号输入框
          Row({ space: 8 }) {
            Text('+86')
              .fontSize(14)
              .fontColor(AppColors.textSecondary)
              .padding({ left: 12, right: 6 })

            TextInput({ placeholder: '请输入手机号', text: this.phoneNumber })
              .placeholderColor(AppColors.textMuted)
              .fontSize(14)
              .fontColor(AppColors.textPrimary)
              .backgroundColor(Color.Transparent)
              .type(InputType.PhoneNumber)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.phoneNumber = v;
              })
          }
          .width('100%')
          .height(48)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)

          // 验证码输入框
          Row({ space: 8 }) {
            TextInput({ placeholder: '请输入6位短信验证码', text: this.smsCode })
              .placeholderColor(AppColors.textMuted)
              .fontSize(14)
              .fontColor(AppColors.textPrimary)
              .backgroundColor(Color.Transparent)
              .type(InputType.Number)
              .layoutWeight(1)
              .padding({ left: 12 })
              .onChange((v: string) => {
                this.smsCode = v;
              })

            Button(this.countdown > 0 ? `${this.countdown}s后重发` : '获取验证码')
              .fontSize(12)
              .fontColor(this.countdown > 0 ? AppColors.textMuted : AppColors.hongguoRed)
              .backgroundColor(Color.Transparent)
              .enabled(this.countdown <= 0)
              .onClick(() => {
                this.sendSmsCode();
              })
          }
          .width('100%')
          .height(48)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)

          // 登录确认大按钮
          Button('登录 / 注册')
            .width('100%')
            .height(46)
            .backgroundColor(AppColors.hongguoRed)
            .fontColor(AppColors.textPrimary)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .borderRadius(23)
            .margin({ top: 16 })
            .onClick(() => {
              this.doPhoneLogin();
            })
        }
        .width('100%')
        .padding(AppDimensions.paddingXl)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
      }

      // 底部隐私与协议说明
      Text('未注册手机号验证后将自动创建新账号\n登录即代表您已阅读并同意《用户服务协议》与《隐私政策》')
        .fontSize(11)
        .fontColor(AppColors.textMuted)
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
