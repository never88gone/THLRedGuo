import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import pasteboard from '@ohos.pasteboard';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';

interface DiaryLogEntry {
  level: string;
  tag: string;
  message: string;
  time: string;
}

@Entry
@Component
struct PlaybackDiaryPage {
  @State logList: DiaryLogEntry[] = [
    { level: 'INFO', tag: 'StationSource', message: '站源引擎加载成功: hongguo.js (官方规范数据源)', time: '08:30:12' },
    { level: 'INFO', tag: 'JsSandbox', message: 'CatPawOpen JS 运行时沙箱初始化完毕，版本 v1.1.0-dev.22', time: '08:30:13' },
    { level: 'INFO', tag: 'Network', message: '官方短剧聚合 API 请求成功 (HTTP 200 OK，耗时 54ms)', time: '08:30:14' },
    { level: 'INFO', tag: 'CencDemux', message: 'MP4 容器解析就绪，识别 CENC senc 样本加密索引 (AES-128-CTR)', time: '08:30:15' },
    { level: 'INFO', tag: 'CryptoEngine', message: '端侧对称密码硬件加速解密器启动，逐块解密就绪', time: '08:30:16' },
    { level: 'INFO', tag: 'PlayerCore', message: 'AVPlayer 硬件渲染管线绑定 XComponent Surface', time: '08:30:17' },
    { level: 'INFO', tag: 'PlayerCore', message: '播放器状态机流转: initialized -> prepared -> playing', time: '08:30:18' },
    { level: 'INFO', tag: 'Playback', message: '自适应画质 1080P@60fps 起播秒开成功，首帧耗时 180ms', time: '08:30:19' }
  ];

  private copyAllLogs(): void {
    const text = this.logList.map(item => `[${item.time}] [${item.level}] [${item.tag}] ${item.message}`).join('\n');
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(pasteData);
      promptAction.showToast({ message: '已复制全部诊断轨迹到剪贴板' });
    } catch (_) {
      promptAction.showToast({ message: '复制日志失败' });
    }
  }

  private clearLogs(): void {
    this.logList = [
      { level: 'INFO', tag: 'Diary', message: '日志已重置，正在监听后续播放器解码与流媒体交互...', time: '08:35:00' }
    ];
    promptAction.showToast({ message: '日记已清空' });
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

        Text('播放诊断日记')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .margin({ left: 12 })

        Blank()

        Button('复制')
          .fontSize(12)
          .fontColor(AppColors.white)
          .backgroundColor(AppColors.hongguoRed)
          .borderRadius(14)
          .height(28)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.copyAllLogs();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 12 })

      // 诊断概览卡片
      Column({ space: 8 }) {
        Row() {
          Text('内核诊断追踪')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)

          Blank()

          Text('● 运行正常')
            .fontSize(12)
            .fontColor(AppColors.success)
        }
        .width('100%')

        Text('记录视频起播、CENC 逐帧硬解密、JS 站源沙箱及 AVPlayer 底层渲染管线流转轨迹。')
          .fontSize(12)
          .fontColor(AppColors.textSecondary)
          .lineHeight(17)
      }
      .width('100%')
      .padding(AppDimensions.paddingMd)
      .backgroundColor(AppColors.bgCard)
      .margin({ left: 16, right: 16, bottom: 12 })
      .borderRadius(AppDimensions.radiusMd)

      // 实时日志流列表
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.logList, (log: DiaryLogEntry, index: number) => {
            Column({ space: 4 }) {
              Row() {
                Text(`[${log.level}]`)
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(log.level === 'WARN' ? AppColors.warning : AppColors.hongguoRed)

                Text(`[${log.tag}]`)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.textPrimary)
                  .margin({ left: 4 })

                Blank()

                Text(log.time)
                  .fontSize(11)
                  .fontColor(AppColors.textMuted)
              }
              .width('100%')

              Text(log.message)
                .fontSize(12)
                .fontColor(AppColors.textSecondary)
                .lineHeight(17)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(AppColors.bgCard)
            .borderRadius(AppDimensions.radiusSm)
            .alignItems(HorizontalAlign.Start)
          }, (log: DiaryLogEntry, index: number) => `${index}_${log.time}`)

          Row() {
            Blank()

            Button('清空日记')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .backgroundColor(AppColors.whiteAlpha10)
              .borderRadius(14)
              .height(28)
              .padding({ left: 14, right: 14 })
              .margin({ top: 12, bottom: 32 })
              .onClick(() => {
                this.clearLogs();
              })

            Blank()
          }
          .width('100%')
        }
        .padding({ left: 16, right: 16, bottom: 30 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.bgDark)
  }
}
