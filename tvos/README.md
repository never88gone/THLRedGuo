# 糖葫芦Haw Apple tvOS 独立版

基于 Apple tvOS (SwiftUI + Siri Remote Focus Engine + AVKit + Network.framework) 开发的 Apple TV 独立客户端，**100% 完整复刻 Flutter 版本的功能体系与业务逻辑**。

---

## 核心架构与功能对齐

| 模块 | Flutter 版实现 | tvOS 原生版复刻实现 |
| :--- | :--- | :--- |
| **开发语言与 UI** | Flutter 3.47 / Dart | Swift 6.0 / SwiftUI (Apple TV HIG 焦点引擎) |
| **站源体系** | 官方免费短剧开源站源 | `SourceSite.swift` 原生解析与驱动体系 |
| **首页与分类** | 横向切类、连载/完结筛选、排序、无限滚动 | `CatalogView.swift`、`HomeViewModel.swift`、大屏 6 列卡片 |
| **推荐专区** | 精选推荐（真人剧、漫剧、AI 剧），记住位置 | `RecommendationsView.swift`、子分类缓存与记忆 |
| **排行榜** | 热播榜、新剧榜、好评榜 | `RankingsView.swift`、金银铜徽章排行卡片 |
| **实时搜索** | 300ms 联想词补全、多源在线搜索、搜索历史 | `SearchRootView.swift`、`SearchViewModel.swift` |
| **剧集详情与选集** | 海报大图、展开简介、每 50 集分组、断点记忆 | `DramaDetailView.swift`、大屏毛玻璃背景、分段选集网格 |
| **大屏播放器** | media_kit / AVPlayer，控制条、选集抽屉、清晰度、倍速 | `TVPlayerView.swift`、`TVPlayerControlsOverlay.swift`、`TVEpisodeDrawer.swift`、`TVDanmakuView.swift` |
| **连播与断点** | 每 5 秒与退出时自动保存秒级进度、播完倒计时连播 | `PlayerViewModel.swift`、`LocalStore.swift` 自动持久化 |
| **追剧与历史** | 想看/在看/已看/有更新，进度百分比指示 | `SavedLibraryView.swift`、`LibraryViewModel.swift` |
| **离线下载** | 任务队列、后台下载、状态机、本地直接播放 | `DownloadService.swift`、`DownloadsView.swift` |
| **局域网互联** | mDNS `_zgj-link._tcp` 广播、手机推送大屏 Handoff 起播 | `LanSyncService.swift` 基于 Network.framework 原生实现 |
| **设置与网络** | 站源解锁、直连/自动/手动代理、并发限流调节 | `SettingsView.swift`、`SettingsViewModel.swift` |

---

## 工程目录结构

```
tvos/
├── README.md                              # tvOS 独立版说明文档
├── THLRedLook.xcodeproj/              # Xcode 工程主文件
│   └── project.pbxproj
└── THLRedLook/
    ├── App/
    │   ├── THLRedLookApp.swift        # SwiftUI App 启动主入口
    │   ├── AppEnvironment.swift          # 全局环境依赖注入
    │   └── Info.plist                    # tvOS 属性清单 (Bonjour 局域网权限、ATS 等)
    ├── Models/                           # 核心数据模型 (与 Flutter JSON 保持一致)
    │   ├── SourceSite.swift              # 站源枚举与分组定义
    │   ├── Drama.swift                   # 剧集元数据、分类与排序模型
    │   ├── Episode.swift                 # 分集与 50 集分组 Chunk 模型
    │   ├── PlaybackPlan.swift            # 播放计划与多清晰度调度
    │   ├── WatchEntry.swift              # 观看历史与追剧状态模型
    │   ├── DownloadJob.swift             # 下载任务与离线状态模型
    │   ├── RankingBoard.swift            # 排行榜与弹幕模型
    │   └── LanModels.swift               # 局域网 Bonjour 互联与代理设置模型
    ├── Core/                             # 原生服务与驱动引擎
    │   ├── NativeBridge.swift            # 纯原生 Swift 驱动与 JavaScriptCore 桥接
    │   ├── NativeRepository.swift        # 数据仓储服务
    │   ├── LocalStore.swift              # UserDefaults / JSON 持久化存储中心
    │   ├── LanSyncService.swift          # Apple Network.framework mDNS 发现与接续播放
    │   └── DownloadService.swift         # URLSession 后台下载与离线文件管理
    ├── ViewModels/                       # MVVM 业务模型
    │   ├── HomeViewModel.swift           # 分类浏览与分页加载
    │   ├── SearchViewModel.swift         # 300ms 防抖联想与搜索
    │   ├── DetailViewModel.swift         # 详情与选集管理
    │   ├── PlayerViewModel.swift         # AVPlayer 播放状态机与断点进度自动保存
    │   ├── RankingsViewModel.swift       # 排行榜数据管理
    │   ├── RecommendationsViewModel.swift# 推荐三专区分类记忆与加载
    │   ├── LibraryViewModel.swift        # 追剧与历史记录检索
    │   ├── DownloadsViewModel.swift      # 下载队列调度
    │   └── SettingsViewModel.swift       # 密码锁、网络代理与系统设置
    └── Views/                            # SwiftUI 表现层组件与页面
        ├── MainTabView.swift             # 系统级顶部 Tab 导航
        ├── Components/
        │   └── DramaCardView.swift       # 适配 Siri Remote 的焦点高亮海报卡片与 TVButton
        ├── Home/
        │   ├── CatalogView.swift         # 发现页大屏海报瀑布流
        │   └── FilterSortSheet.swift     # 排序与状态筛选浮层
        ├── Player/
        │   ├── TVPlayerView.swift        # AVPlayer 全屏播放器
        │   ├── TVPlayerControlsOverlay.swift # 遥控器悬浮控制条
        │   ├── TVEpisodeDrawer.swift     # 侧滑快速换集抽屉
        │   └── TVDanmakuView.swift       # 实时弹幕渲染图层
        ├── Detail/
        │   └── DramaDetailView.swift     # 大屏毛玻璃背景剧集详情
        ├── Search/
        │   └── SearchRootView.swift      # 搜索、联想与历史
        ├── Rankings/
        │   └── RankingsView.swift        # 榜单卡片瀑布流
        ├── Recommendations/
        │   └── RecommendationsView.swift # 推荐专区
        ├── Library/
        │   └── SavedLibraryView.swift    # 追剧与历史进度条
        ├── Downloads/
        │   └── DownloadsView.swift       # 下载列表与离线播放
        ├── Lan/
        │   └── LanSyncView.swift         # 局域网 Bonjour 同步与接续待命
        └── Settings/
            └── SettingsView.swift        # 站源密码锁解锁与设置
```

---

## 编译与运行方式

### 方式 1：使用 Xcode 直接打开与调试
1. 在 macOS 打开 Xcode。
2. 打开 `tvos/THLRedLook.xcodeproj`。
3. 选择目标设备：**Apple TV 4K (3rd generation) (Simulator)** 或连接的 Apple TV 实体机。
4. 按 `Cmd + R` 直接编译并在模拟器中运行体验！使用键盘方向键或 Siri Remote 模拟器即可畅享焦点交互与全屏播放。

### 方式 2：使用命令行自动化脚本
项目根目录提供了 `scripts/build_tvos.py`，支持一键校验和编译 tvOS 产物：
```bash
python3 scripts/build_tvos.py
```
