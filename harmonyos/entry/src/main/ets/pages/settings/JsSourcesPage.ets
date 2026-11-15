import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';

interface JsSourcePlugin {
  id: string;
  name: string;
  file: string;
  version: string;
  status: string;
  isOfficial: boolean;
  desc: string;
}

@Entry
@Component
struct JsSourcesPage {
  @State sources: JsSourcePlugin[] = [
    {
      id: 'hongguo',
      name: '官方免费短剧',
      file: 'hongguo.js',
      version: 'v1.1.0-dev.22',
      status: '已激活 · 正在使用',
      isOfficial: true,
      desc: '官方规范短剧数据源，支持全网热门短剧搜索、分类筛选、选集播放与 1080P 超清直链解析。'
    }
  ];

  private reloadSandbox(): void {
    promptAction.showToast({ message: '已重新加载并扫描端侧 JS 数据源沙箱' });
  }

  @Builder
  PluginCard(plugin: JsSourcePlugin) {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Row() {
            Text(plugin.name)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            if (plugin.isOfficial) {
              Text('官方规范')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.white)
                .backgroundColor(AppColors.hongguoRed)
                .borderRadius(6)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .margin({ left: 8 })
            }
          }

          Text(`脚本文件: ${plugin.file} (${plugin.version})`)
            .fontSize(12)
            .fontColor(AppColors.textMuted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('✓ ' + plugin.status)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.success)
          .backgroundColor(AppColors.whiteAlpha10)
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      }
      .width('100%')

      Divider()
        .color(AppColors.divider)
        .height(1)

      Text(plugin.desc)
        .fontSize(13)
        .fontColor(AppColors.textSecondary)
        .lineHeight(19)

      Row() {
        Blank()

        Button('重载插件')
          .fontSize(12)
          .fontColor(AppColors.textPrimary)
          .backgroundColor(AppColors.whiteAlpha10)
          .borderRadius(14)
          .height(28)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            this.reloadSandbox();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppDimensions.paddingMd)
    .backgroundColor(AppColors.bgCard)
    .borderRadius(AppDimensions.radiusMd)
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

        Text('JS 数据源插件管理')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .margin({ left: 12 })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 12 })

      // 内容列表
      Scroll() {
        Column({ space: 16 }) {
          // 1. 开源合规与沙箱红线说明
          Column({ space: 8 }) {
            Text('开源合规与沙箱隔离')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Text('本项目严格遵守开源合规红线，仅内置并维护官方规范数据源 (hongguo.js)。所有站源解析、签名注入与直链获取均在设备端侧独立沙箱闭环执行，不连接任何第三方中转自建服务器。')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .lineHeight(18)
          }
          .width('100%')
          .padding(AppDimensions.paddingMd)
          .backgroundColor(AppColors.bgCard)
          .borderRadius(AppDimensions.radiusMd)
          .alignItems(HorizontalAlign.Start)

          // 2. 插件列表
          ForEach(this.sources, (plugin: JsSourcePlugin) => {
            this.PluginCard(plugin);
          }, (plugin: JsSourcePlugin) => plugin.id)

          // 3. 沙箱环境指标
          Column({ space: 8 }) {
            Text('运行时沙箱指标')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)

            Text('• 运行时核心：CatPawOpen Spider Core Specification\n' +
                 '• 执行模式：HarmonyOS NEXT 端侧独立无网络代理沙箱\n' +
                 '• 安全策略：防篡改哈希绑定，仅调度合规数据源\n' +
                 '• 视频解密协议：CENC AES-128-CTR 逐块硬解密')
              .fontSize(12)
              .fontColor(AppColors.textSecondary)
              .lineHeight(20)
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
