# 糖葫芦Haw - HarmonyOS NEXT 原生应用

本目录（`harmonyos/`）为糖葫芦Haw针对华为 **HarmonyOS NEXT**（API 12+，Stage 模型，ArkTS / ArkUI）的原生开发工程。与 Flutter 客户端实现架构、视觉规范与业务闭环完全对齐。

## 技术栈与设计规范

- **开发框架**：HarmonyOS NEXT SDK (API Version 12+)
- **开发语言**：ArkTS (TypeScript 超集)、ArkUI 声明式 UI 开发范式
- **应用模型**：Stage 模型 (`UIAbility`)
- **播放引擎**：官方媒体框架 `@ohos.multimedia.media.AVPlayer` + 原生 `XComponent` 表面渲染
- **数据持久化**：`@ohos.data.preferences` 用户首选项轻量存储（播放历史、追剧收藏、搜索历史）
- **数据源合规**：纯净独立，统一加载官方标准规范短剧源（`entry/src/main/resources/rawfile/sources/hongguo.js`）
- **视觉主题**：与 Flutter 端完全一致，暗夜黑深色沉浸式主题 (`#101114`)，品牌红 (`#FF2442`)，会员金 (`#FFB300`)

## 工程目录结构

```text
harmonyos/
├── AppScope/                            # 全局应用配置与资源 (bundleName: com.never88gone.redlook)
│   ├── app.json5
│   └── resources/
├── entry/                               # 主 Feature 模块
│   ├── build-profile.json5              # 模块编译配置
│   ├── hvigorfile.ts
│   ├── package.json
│   └── src/main/
│       ├── module.json5                 # 模块声明、权限与 UIAbility 注册
│       ├── resources/                   # 资源目录（颜色、字符串、主页面路由）
│       │   └── rawfile/sources/hongguo.js # 官方纯净短剧源
│       └── ets/
│           ├── common/                  # 全局设计规范 (AppTheme, Constants)
│           ├── models/                  # 数据实体模型 (Drama, Episode, Category, Ranking, Account, Download)
│           ├── core/                    # 核心业务引擎层
│           │   ├── account/             # 扫码登录、手机验证码与会话管理
│           │   ├── download/            # 离线视频下载管理器
│           │   ├── engine/              # 核心业务调度引擎 (CoreEngine)
│           │   ├── js/                  # JS 数据源执行桥接 (CatPawJsRuntime)
│           │   ├── player/              # AVPlayer 播放控制器封装
│           │   └── store/               # 本地存储 (LocalStore)
│           ├── entryability/            # 应用入口生命周期 (EntryAbility)
│           └── pages/                   # 原生 ArkUI 页面实现
│               ├── Index.ets            # 底部 5-Tab 导航入口 (首页、推荐流、排行榜、我的、设置)
│               ├── home/HomePage.ets    # 首页分类浏览与短剧双列流
│               ├── detail/DramaDetailPage.ets # 剧集详情、选集与追剧状态
│               ├── player/PlayerPage.ets # 全屏沉浸式播放器 (XComponent, 进度拖拽, 倍速, 选集抽屉)
│               ├── search/SearchPage.ets # 搜索页 (热搜推荐、历史记录、剧集检索)
│               ├── rankings/RankingsPage.ets # 排行榜 (热播榜、飙升榜、新剧榜)
│               ├── feed/VideoFeedPage.ets # 短剧沉浸式上下滑动推荐流
│               ├── account/AccountPage.ets # 个人中心 (历史进度、追剧、缓存清理)
│               ├── account/LoginPage.ets # 登录界面 (二维码扫码 + 手机号短信)
│               ├── downloads/DownloadsPage.ets # 离线缓存与存储监控
│               └── settings/SettingsPage.ets # 设置 (播放偏好、清晰度、自动连播、关于)
├── build-profile.json5                  # 顶层构建配置
├── hvigorfile.ts                        # 顶层构建脚本
└── package.json
```

## 构建与运行

1. 下载并安装 **DevEco Studio 5.0+** (Release 或 NEXT 正式版)。
2. 在 DevEco Studio 中选择 **File -> Open**，打开本项目下的 `harmonyos` 文件夹。
3. DevEco Studio 会自动识别 `build-profile.json5` 并同步工程依赖。
4. 连接已开启“开发者选项”与“USB调试”的 HarmonyOS NEXT 手机/平板设备，或启动 HarmonyOS 官方模拟器。
5. 点击上方工具栏的 **Run 'entry'** (Shift + F10) 即可直接安装并运行原生应用。
