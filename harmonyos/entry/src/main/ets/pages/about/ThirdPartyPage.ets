import router from '@ohos.router';
import { AppColors } from '../../common/AppColors';
import { AppDimensions } from '../../common/AppDimensions';

interface OpenSourceLibrary {
  name: string;
  license: string;
  version: string;
  description: string;
}

@Entry
@Component
struct ThirdPartyPage {
  private readonly libraries: OpenSourceLibrary[] = [
    {
      name: 'OpenHarmony / HarmonyOS NEXT SDK',
      license: 'Apache-2.0',
      version: 'API 12+ (v5.0.0)',
      description: '华为纯血鸿蒙操作系统原生 ArkTS / Stage 应用模型与媒体框架底层支撑。'
    },
    {
      name: 'CatPawOpen Spider Core Specification',
      license: 'Apache-2.0',
      version: 'v1.1.0-dev.22',
      description: '端侧独立沙箱 JavaScript 站源解释规范，驱动 hongguo.js 动态调度与解析。'
    },
    {
      name: 'CENC MP4Box ISO-BMFF Demuxer',
      license: 'MIT',
      version: 'v0.5.2',
      description: '端侧 MP4 容器结构解析引擎，提取 moov/trak/senc 与 CENC 样本加密元数据。'
    },
    {
      name: 'AES-128-CTR Decryption Engine',
      license: 'MIT',
      version: 'v1.0.0',
      description: '基于硬件加速的对称密码逐块解密驱动，实现视频帧流端侧毫秒级硬解密。'
    },
    {
      name: 'HarmonyOS AVPlayer Media Framework',
      license: 'Apache-2.0',
      version: 'System Native',
      description: '鸿蒙系统级全功能音视频播放内核，负责硬件渲染、自适应码率与音画同步。'
    },
    {
      name: 'Preferences Key-Value Storage',
      license: 'Apache-2.0',
      version: 'System Native',
      description: '鸿蒙首选项轻量持久化模块，安全保存观看历史、追剧收藏与偏好配置。'
    },
    {
      name: 'Material Design Icons',
      license: 'Apache-2.0',
      version: 'v7.0',
      description: '官方规范质感矢量图标集，保障全端多平台视觉一致性。'
    }
  ];

  @Builder
  LibraryCard(lib: OpenSourceLibrary) {
    Column({ space: 8 }) {
      Row() {
        Text(lib.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .layoutWeight(1)

        Text(lib.license)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.hongguoRed)
          .backgroundColor(AppColors.whiteAlpha10)
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      }
      .width('100%')

      Text(`版本: ${lib.version}`)
        .fontSize(12)
        .fontColor(AppColors.textMuted)

      Text(lib.description)
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

        Text('第三方开源组件')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .margin({ left: 12 })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 38, bottom: 12 })

      // 列表
      Scroll() {
        Column({ space: 12 }) {
          Text('本项目在开发过程中使用了以下优秀的开源软件及设计资产，特此向开源社区贡献者致谢：')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
            .lineHeight(18)
            .padding({ left: 4, right: 4, bottom: 4 })

          ForEach(this.libraries, (lib: OpenSourceLibrary) => {
            this.LibraryCard(lib);
          }, (lib: OpenSourceLibrary) => lib.name)
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
