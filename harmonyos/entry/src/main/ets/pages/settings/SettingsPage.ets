import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';
import { Constants } from '../../common/Constants';
import { LocalStore } from '../../core/store/LocalStore';
import { AppUpdateService } from '../../core/update/AppUpdateService';
import { SettingsDisplaySection } from './components/SettingsDisplaySection';
import { SettingsPlaybackSection } from './components/SettingsPlaybackSection';
import { SettingsSourceSection } from './components/SettingsSourceSection';
import { SettingsStorageSection } from './components/SettingsStorageSection';
import { SettingsBackupSection } from './components/SettingsBackupSection';
import { SettingsPrivacySection } from './components/SettingsPrivacySection';
import { SettingsAboutSection } from './components/SettingsAboutSection';

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
  @State displayMode: string = '自动识别设备';
  @State themeMode: string = '深色模式';
  @State cacheSize: string = '12.4 MB';

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
        const modes = ['自动识别设备', '手机 / 电脑标准版', '电视大屏 / 遥控器版'];
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
        const themes = ['深色模式', '跟随系统深浅色', '红果品牌红主题'];
        this.themeMode = themes[data.index];
        promptAction.showToast({ message: `主题已应用: ${this.themeMode}` });
      }
    });
  }

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

  showSourceSwitcher(): void {
    router.pushUrl({ url: 'pages/settings/SourceSwitcherPage' });
  }

  showJsManagement(): void {
    router.pushUrl({ url: 'pages/settings/JsSourcesPage' });
  }

  runDiagnostics(): void {
    router.pushUrl({ url: 'pages/settings/SourceDiagnosticsPage' });
  }

  clearAppCache(): void {
    this.cacheSize = '0.0 MB';
    promptAction.showToast({ message: '本地封面图片与解密临时缓存已清理干净' });
  }

  showBackupDialog(): void {
    router.pushUrl({ url: 'pages/settings/BackupSettingsPage' });
  }

  showPrivacyLockDialog(): void {
    router.pushUrl({ url: 'pages/privacy/PrivacySettingsPage' });
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

  showReleaseNotesDialog(): void {
    router.pushUrl({ url: 'pages/about/ReleaseNotesPage' });
  }

  showAppIntroDialog(): void {
    router.pushUrl({ url: 'pages/about/AppIntroPage' });
  }

  showContactDialog(): void {
    router.pushUrl({ url: 'pages/about/ContactPage' });
  }

  showThirdPartyDialog(): void {
    router.pushUrl({ url: 'pages/about/ThirdPartyPage' });
  }

  showDiaryDialog(): void {
    router.pushUrl({ url: 'pages/about/PlaybackDiaryPage' });
  }

  showAboutDialog(): void {
    router.pushUrl({ url: 'pages/about/AboutPage' });
  }

  build() {
    Column() {
      // 顶部标题
      Row() {
        Text('设置')
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
          SettingsDisplaySection({
            displayMode: this.displayMode,
            themeMode: this.themeMode,
            onShowDisplayModePicker: () => {
              this.showDisplayModePicker();
            },
            onShowThemePicker: () => {
              this.showThemePicker();
            }
          })

          // 分组 2：短剧播放
          SettingsPlaybackSection({
            autoAdvance: this.autoAdvance,
            selectedQuality: this.selectedQuality,
            selectedSpeed: this.selectedSpeed,
            danmakuEnabled: this.danmakuEnabled,
            pipEnabled: this.pipEnabled,
            hardwareDecode: this.hardwareDecode,
            onToggleAutoAdvance: (isOn: boolean) => {
              this.autoAdvance = isOn;
            },
            onShowQualityPicker: () => {
              this.showQualityPicker();
            },
            onShowSpeedPicker: () => {
              this.showSpeedPicker();
            },
            onToggleDanmaku: (isOn: boolean) => {
              this.danmakuEnabled = isOn;
            },
            onTogglePip: (isOn: boolean) => {
              this.pipEnabled = isOn;
            },
            onToggleHardwareDecode: (isOn: boolean) => {
              this.hardwareDecode = isOn;
            }
          })

          // 分组 3：数据源与插件
          SettingsSourceSection({
            onShowSourceSwitcher: () => {
              this.showSourceSwitcher();
            },
            onShowJsManagement: () => {
              this.showJsManagement();
            },
            onRunDiagnostics: () => {
              this.runDiagnostics();
            }
          })

          // 分组 4：离线与存储
          SettingsStorageSection({
            wifiOnlyDownload: this.wifiOnlyDownload,
            cacheSize: this.cacheSize,
            onToggleWifiOnly: (isOn: boolean) => {
              this.wifiOnlyDownload = isOn;
            },
            onShowDownloads: () => {
              router.pushUrl({ url: 'pages/downloads/DownloadsPage' });
            },
            onClearCache: () => {
              this.clearAppCache();
            }
          })

          // 分组 5：数据与备份
          SettingsBackupSection({
            onShowBackupDialog: () => {
              this.showBackupDialog();
            }
          })

          // 分组 6：隐私与安全
          SettingsPrivacySection({
            onShowPrivacyLock: () => {
              this.showPrivacyLockDialog();
            },
            onClearHistory: () => {
              this.clearHistoryData();
            }
          })

          // 分组 7：关于与支持
          SettingsAboutSection({
            appVersion: Constants.APP_VERSION,
            appBuild: Constants.APP_BUILD_NUMBER,
            onCheckUpdate: () => {
              this.checkAppUpdate();
            },
            onShowReleaseNotes: () => {
              this.showReleaseNotesDialog();
            },
            onShowAppIntro: () => {
              this.showAppIntroDialog();
            },
            onShowContact: () => {
              this.showContactDialog();
            },
            onShowThirdParty: () => {
              this.showThirdPartyDialog();
            },
            onShowDiary: () => {
              this.showDiaryDialog();
            },
            onShowAbout: () => {
              this.showAboutDialog();
            }
          })
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
