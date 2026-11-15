import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';

interface SourceItem {
  id: string;
  name: string;
  file: string;
  badge: string;
  selected: boolean;
  desc: string;
}

@Entry
@Component
struct SourceSwitcherPage {
  @State selectedId: string = 'hongguo';

  private readonly sources: SourceItem[] = [
    {
      id: 'hongguo',
      name: '官方免费短剧',
      file: 'hongguo.js',
      badge: '官方正版 · 规范数据源',
      selected: true,
      desc: '聚合全网热播短剧，支持 1080P 超清画质与端侧 CENC 视频流硬解密。'
    }
  ];

  private selectSource(id: string): void {
    this.selectedId = id;
    promptAction.showToast({ message: '当前数据源：官方免费短剧 (hongguo.js)' });
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

        Text('切换数据源')
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
          // 1. 合规说明
          Column({ space: 8 }) {
            Text('数据源与站源规范')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Text('根据开源合规要求，本项目面向公网严格保持纯净，仅内置官方规范数据源 (hongguo.js)。所有解析与解密均在设备本地完成。')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .lineHeight(18)
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)
          .alignItems(HorizontalAlign.Start)

          // 2. 站源卡片
          ForEach(this.sources, (source: SourceItem) => {
            Column({ space: 10 }) {
              Row() {
                Column({ space: 4 }) {
                  Row() {
                    Text(source.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(AppColors.textPrimary)

                    Text(source.badge)
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(AppColors.white)
                      .backgroundColor(AppColors.hongguoRed)
                      .borderRadius(6)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .margin({ left: 8 })
                  }

                  Text(`脚本: ${source.file}`)
                    .fontSize(12)
                    .fontColor(AppColors.textMuted)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text('● 正在使用')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.success)
              }
              .width('100%')

              Divider()
                .color(AppColors.divider)
                .height(1)

              Text(source.desc)
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
                .lineHeight(19)
            }
            .width('100%')
            .padding(AppDimensions.paddingMd)
            .backgroundColor(AppColors.bgCard)
            .borderRadius(AppDimensions.radiusMd)
            .onClick(() => {
              this.selectSource(source.id);
            })
          }, (source: SourceItem) => source.id)
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
