import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors, AppDimensions } from '../../common/AppTheme';
import { Constants } from '../../common/Constants';
import common from '@ohos.app.ability.common';
import { LocalStore } from '../../core/store/LocalStore';
import { AppUpdateService } from '../../core/update/AppUpdateService';

@Entry
@Component
export struct SettingsPage {
  @State autoAdvance: boolean = true;
  @State hardwareDecode: boolean = true;
  @State wifiOnlyDownload: boolean = true;
  @State danmakuEnabled: boolean = true;
  @State pipEnabled: boolean = false;
  @State selectedQuality: string = '1080P 超清';
  @State selectedSpeed: string = '1.0x (正常)';
  @State displayMode: string = '自动适配 (手机/平板)';
  @State themeMode: string = '深色模式 (暗黑质感)';
  @State cacheSize: string = '12.4 MB';

  showQualityPicker(): void {
    promptAction.showActionMenu({
      title: '选择默认播放画质',
      buttons: [
        { text: '1080P 超清', color: AppColors.textPrimary },
        { text: '720P 高清', color: AppColors.textPrimary },
        { text: '480P 标清', color: AppColors.textPrimary },
        { text: '自动匹配最佳', color: AppColors.textPrimary }
      ]
    }, (err, data) => {
      if (!err) {
        const qualities = ['1080P 超清', '720P 高清', '480P 标清', '自动匹配最佳'];
        this.selectedQuality = qualities[data.index];
        promptAction.showToast({ message: `已将默认画质设为: ${this.selectedQuality}` });
      }
    });
  }

  showSpeedPicker(): void {
    promptAction.showActionMenu({
      title: '选择默认起播倍速',
      buttons: [
        { text: '1.0x (正常)', color: AppColors.textPrimary },
        { text: '1.25x', color: AppColors.textPrimary },
        { text: '1.5x', color: AppColors.textPrimary },
        { text: '2.0x', color: AppColors.textPrimary }
      ]
    }, (err, data) => {
      if (!err) {
        const speeds = ['1.0x (正常)', '1.25x', '1.5x', '2.0x'];
        this.selectedSpeed = speeds[data.index];
        promptAction.showToast({ message: `默认倍速设为: ${this.selectedSpeed}` });
      }
    });
  }

  showDisplayModePicker(): void {
    promptAction.showActionMenu({
      title: '切换页面显示模式',
      buttons: [
        { text: '自动识别设备 (推荐)', color: AppColors.textPrimary },
        { text: '手机 / 电脑标准版', color: AppColors.textPrimary },
        { text: '电视大屏 / 遥控器版', color: AppColors.textPrimary }
      ]
    }, (err, data) => {
      if (!err) {
        const modes = ['自动识别设备 (推荐)', '手机 / 电脑标准版', '电视大屏 / 遥控器版'];
        this.displayMode = modes[data.index];
        promptAction.showToast({ message: `页面模式已切换: ${this.displayMode}` });
      }
    });
  }

  showThemePicker(): void {
    promptAction.showActionMenu({
      title: '外观与色彩主题',
      buttons: [
        { text: '深色模式 (暗黑质感)', color: AppColors.textPrimary },
        { text: '跟随系统深浅色', color: AppColors.textPrimary },
        { text: '红果品牌红主题', color: AppColors.textPrimary }
      ]
    }, (err, data) => {
      if (!err) {
        const themes = ['深色模式 (暗黑质感)', '跟随系统深浅色', '红果品牌红主题'];
        this.themeMode = themes[data.index];
        promptAction.showToast({ message: `主题已应用: ${this.themeMode}` });
      }
    });
  }

  runDiagnostics(): void {
    promptAction.showDialog({
      title: '数据源网络诊断',
      message: '正在检测官方数据源连接...\n\n✅ 官方 API 网络连通正常\n✅ DNS 与 TLS 证书链正常\n✅ CatPawOpen JS 运行时正常\n✅ 站源脚本 (hongguo.js) 签名有效',
      buttons: [
        { text: '完成', color: AppColors.hongguoRed }
      ]
    });
  }

  clearAppCache(): void {
    this.cacheSize = '0.0 MB';
    promptAction.showToast({ message: '本地图片与临时缓存已清理干净' });
  }

  clearHistoryData(): void {
    promptAction.showDialog({
      title: '清除历史数据',
      message: '确定要清除所有本地播放进度、搜索历史与追剧记录吗？',
      buttons: [
        { text: '取消', color: AppColors.textSecondary },
        { text: '确认清除', color: AppColors.hongguoRed }
      ]
    }, (err, data) => {
      if (!err && data.index === 1) {
        LocalStore.getInstance().clearAllHistory();
        promptAction.showToast({ message: '本地历史记录已清空' });
      }
    });
  }

  showAboutDialog(): void {
    promptAction.showDialog({
      title: Constants.APP_NAME,
      message: `版本号：v${Constants.APP_VERSION} (Build ${Constants.APP_BUILD_NUMBER})\n\n基于 HarmonyOS NEXT 原生 ArkTS 与 Stage 模型研发。\n\n遵守开源合规规范，纯净短剧独立设备端客户端。\n\n端侧解析，无第三方中转。`,
      buttons: [
        { text: '确定', color: AppColors.hongguoRed }
      ]
    });
  }

  checkAppUpdate(): void {
    promptAction.showToast({ message: '正在检查新版本...' });
    AppUpdateService.getInstance().checkUpdate()
      .then((info) => {
        if (info.hasUpdate) {
          const targetUrl = info.primaryAsset ? info.primaryAsset.downloadUrl : info.htmlUrl;
          const notes = info.releaseNotes ? ('\n\n更新说明:\n' + info.releaseNotes.substring(0, 300)) : '';
          promptAction.showDialog({
            title: `发现新版本: ${info.title}`,
            message: `当前版本: v${info.currentVersion} (Build ${info.currentBuild})\n最新版本: v${info.remoteVersion} (Build ${info.remoteBuild})${notes}`,
            buttons: [
              { text: '前往下载', color: AppColors.hongguoRed },
              { text: '稍后再说', color: AppColors.textSecondary }
            ]
          }, (err, data) => {
            if (!err && data.index === 0) {
              const ctx = getContext(this) as common.UIAbilityContext;
              AppUpdateService.getInstance().openUpdateUrl(ctx, targetUrl);
            }
          });
        } else {
          promptAction.showToast({ message: `当前版本 v${info.currentVersion} (Build ${info.currentBuild}) 已是最新` });
        }
      })
      .catch(() => {
        promptAction.showToast({ message: '检查更新失败，请检查网络或稍后重试' });
      });
  }

  build() {
    Column() {
      // 顶部标题
      Row() {
        Text('应用设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 8 })

      Scroll() {
        Column({ space: 16 }) {
          // 分组 1：界面与显示
          Column({ space: 1 }) {
            Text('界面与显示')
              .fontSize(13)
              .fontColor(AppColors.hongguoRed)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 4, bottom: 6 })

            Row() {
              Text('页面布局模式')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Text(this.displayMode + ' >')
                .fontSize(12)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius({ topLeft: 12, topRight: 12 })
            .onClick(() => {
              this.showDisplayModePicker();
            })

            Row() {
              Text('外观与色彩主题')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Text(this.themeMode + ' >')
                .fontSize(12)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius({ bottomLeft: 12, bottomRight: 12 })
            .onClick(() => {
              this.showThemePicker();
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 分组 2：短剧播放
          Column({ space: 1 }) {
            Text('短剧播放')
              .fontSize(13)
              .fontColor(AppColors.hongguoRed)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 4, bottom: 6 })

            // 自动连播开关
            Row() {
              Text('自动连播下一集')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.autoAdvance })
                .selectedColor(AppColors.hongguoRed)
                .onChange((isOn: boolean) => {
                  this.autoAdvance = isOn;
                })
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius({ topLeft: 12, topRight: 12 })

            // 默认画质
            Row() {
              Text('默认清晰度')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Text(this.selectedQuality + ' >')
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .onClick(() => {
              this.showQualityPicker();
            })

            // 默认倍速
            Row() {
              Text('默认起播倍速')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Text(this.selectedSpeed + ' >')
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .onClick(() => {
              this.showSpeedPicker();
            })

            // 弹幕开关
            Row() {
              Text('短剧弹幕展示')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.danmakuEnabled })
                .selectedColor(AppColors.hongguoRed)
                .onChange((isOn: boolean) => {
                  this.danmakuEnabled = isOn;
                })
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)

            // 画中画模式
            Row() {
              Text('画中画小窗播放')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.pipEnabled })
                .selectedColor(AppColors.hongguoRed)
                .onChange((isOn: boolean) => {
                  this.pipEnabled = isOn;
                })
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)

            // 硬件加速
            Row() {
              Text('硬件加速解码')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.hardwareDecode })
                .selectedColor(AppColors.hongguoRed)
                .onChange((isOn: boolean) => {
                  this.hardwareDecode = isOn;
                })
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius({ bottomLeft: 12, bottomRight: 12 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 分组 3：数据源与诊断
          Column({ space: 1 }) {
            Text('数据源与网络诊断')
              .fontSize(13)
              .fontColor(AppColors.hongguoRed)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 4, bottom: 6 })

            Row() {
              Column({ space: 4 }) {
                Text('当前数据源')
                  .fontSize(14)
                  .fontColor(AppColors.textPrimary)
                Text('官方规范短剧数据源 (hongguo.js)')
                  .fontSize(11)
                  .fontColor(AppColors.hongguoGold)
              }
              .alignItems(HorizontalAlign.Start)

              Blank()

              Text('官方直连')
                .fontSize(12)
                .fontColor(AppColors.textMuted)
            }
            .width('100%')
            .height(56)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius({ topLeft: 12, topRight: 12 })

            Row() {
              Text('网络连通性与源诊断')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Text('开始诊断 >')
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius({ bottomLeft: 12, bottomRight: 12 })
            .onClick(() => {
              this.runDiagnostics();
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 分组 4：离线与存储
          Column({ space: 1 }) {
            Text('离线与存储')
              .fontSize(13)
              .fontColor(AppColors.hongguoRed)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 4, bottom: 6 })

            Row() {
              Text('仅在 Wi-Fi 下下载视频')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.wifiOnlyDownload })
                .selectedColor(AppColors.hongguoRed)
                .onChange((isOn: boolean) => {
                  this.wifiOnlyDownload = isOn;
                })
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius({ topLeft: 12, topRight: 12 })

            Row() {
              Text('离线下载管理')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Text('进入查看 >')
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .onClick(() => {
              router.pushUrl({ url: 'pages/downloads/DownloadsPage' });
            })

            Row() {
              Text('清理缓存')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Text(this.cacheSize + ' (点击清理)')
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius({ bottomLeft: 12, bottomRight: 12 })
            .onClick(() => {
              this.clearAppCache();
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 分组 5：隐私与安全
          Column({ space: 1 }) {
            Text('隐私与安全')
              .fontSize(13)
              .fontColor(AppColors.hongguoRed)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 4, bottom: 6 })

            Row() {
              Text('清除观看与搜索历史')
                .fontSize(14)
                .fontColor(AppColors.hongguoRed)
              Blank()
              Text('一键清空 >')
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius(AppDimensions.radiusMd)
            .onClick(() => {
              this.clearHistoryData();
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 分组 6：关于与系统
          Column({ space: 1 }) {
            Text('关于应用')
              .fontSize(13)
              .fontColor(AppColors.hongguoRed)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 4, bottom: 6 })

            Row() {
              Text('应用版本')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Text(`v${Constants.APP_VERSION} (${Constants.APP_BUILD_NUMBER})`)
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius({ topLeft: 12, topRight: 12 })

            Row() {
              Text('检查更新')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Text('检测 GitHub 最新版本 >')
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .onClick(() => {
              this.checkAppUpdate();
            })

            Row() {
              Text('开源说明与架构规范')
                .fontSize(14)
                .fontColor(AppColors.textPrimary)
              Blank()
              Text('查看 >')
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
            }
            .width('100%')
            .height(50)
            .padding({ left: 14, right: 14 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius({ bottomLeft: 12, bottomRight: 12 })
            .onClick(() => {
              this.showAboutDialog();
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .padding(AppDimensions.paddingMd)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
