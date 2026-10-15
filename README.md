# 糖葫芦Haw (THLRedLook)

> ⚠️ **免责声明**：本项目仅供编程学习与个人技术研究使用。代码中所有接口与解析逻辑均在设备端侧沙箱中独立执行，请勿用于任何商业用途。

**糖葫芦Haw**（工程标识：`THLRedLook`，包名 / Application ID：`com.never88gone.redlook`）是一款基于 **Flutter + 纯 Dart 高性能核心引擎** 与 **Apple tvOS 原生 SwiftUI** 打造的全平台独立流媒体与短剧聚合应用。

站源请求、协议解析、动态取流、在线播放与离线下载均在设备本地端侧闭环完成，全平台实现真正一键构建与零配置运行；无需搭建任何远程中转或中心化代理服务，兼具极致的启动速度、数据私密性与多端一致的使用体验。

---

## 界面预览

### 🖥️ 桌面端宽屏与分栏视窗 (Windows / macOS)

| 桌面端宽屏分栏全景 | 桌面端高清播放与选集 |
| :---: | :---: |
| <img src="assets/screenshots/desktop_overview.png" width="440" alt="桌面端全景" /> | <img src="assets/screenshots/desktop_player.png" width="440" alt="桌面端播放器" /> |

### 📱 移动端核心观影体验 (iOS / Android)

| 首页发现与分类 | 搜索与关键词联想 | 热播短剧排行榜 |
| :---: | :---: | :---: |
| <img src="assets/screenshots/mobile_home.png" width="180" alt="首页发现" /> | <img src="assets/screenshots/mobile_search.png" width="180" alt="搜索联想" /> | <img src="assets/screenshots/mobile_rankings.png" width="180" alt="短剧榜单" /> |

| 剧集详情与选集 | 竖屏沉浸式播放 | 横屏全屏影院模式 |
| :---: | :---: | :---: |
| <img src="assets/screenshots/mobile_detail.png" width="180" alt="剧集详情" /> | <img src="assets/screenshots/mobile_player_portrait.png" width="180" alt="竖屏播放" /> | <img src="assets/screenshots/mobile_player_fullscreen.png" width="260" alt="横屏播放" /> |

### 🗂️ 追剧、历史、离线缓存与插件管理

| 我的追剧收藏 | 最近观看 | 离线下载管理 | JS 数据源插件管理 |
| :---: | :---: | :---: | :---: |
| <img src="assets/screenshots/mobile_follow.png" width="150" alt="我的追剧" /> | <img src="assets/screenshots/mobile_history.png" width="150" alt="最近观看" /> | <img src="assets/screenshots/mobile_downloads.png" width="150" alt="离线下载" /> | <img src="assets/screenshots/mobile_js_sources.png" width="150" alt="JS数据源管理" /> |

### 🔒 隐私安全与私密保险箱

| 九宫格手势锁 | 隐私模式与私密设置 | 独立私密短剧库 |
| :---: | :---: | :---: |
| <img src="assets/screenshots/privacy_lock.png" width="180" alt="九宫格手势锁" /> | <img src="assets/screenshots/privacy_settings.png" width="180" alt="隐私设置" /> | <img src="assets/screenshots/privacy_vault.png" width="180" alt="私密短剧库" /> |

### 📺 Apple tvOS 客厅大屏原生端

| tvOS 首页瀑布流 | tvOS 剧集详情与选集 |
| :---: | :---: |
| <img src="assets/screenshots/tvos_home.png" width="380" alt="tvOS首页" /> | <img src="assets/screenshots/tvos_detail.png" width="380" alt="tvOS详情" /> |

| tvOS 热播排行榜 | tvOS 全屏播放与控制层 |
| :---: | :---: |
| <img src="assets/screenshots/tvos_rankings.png" width="380" alt="tvOS榜单" /> | <img src="assets/screenshots/tvos_player.png" width="380" alt="tvOS播放器" /> |

---

## 平台支持矩阵

应用深度适配移动端、桌面端与客厅大屏，覆盖以下操作系统与形态：

| 平台 | 形态与特性 | 构建与交付产物 |
| :--- | :--- | :--- |
| **Android** | 适配手机与折叠屏，支持竖屏短剧滑动手势、画中画（PiP）浮窗、arm64-v8a / armeabi-v7a / x86_64 三架构 | 原生 Flutter + NDK 编译，输出 APK / AAB |
| **Android TV** | 自动识别大屏电视模式，锁定横屏影院布局，完整适配遥控器方向键与焦点移动 | 共用 Flutter 源码，自适应电视 UI 布局 |
| **iOS** | 适配 iPhone / iPad，支持深色模式自适应、原生手势返回与后台低功耗下载 | Xcode 编译签名，输出 IPA 归档 |
| **macOS** | 桌面端大屏响应式三栏/分栏布局，键盘方向键与快捷键全面支持 | macOS App / PKG 安装包 |
| **Windows** | 基于 `media_kit` / libmpv 硬件解码，独家集成专属 Shader 画质增强滤镜 | 独立免安装绿色包 / 便携目录（含完整 DLL 与运行环境） |
| **Apple tvOS** | 独立原生工程（`tvos/`），纯 SwiftUI + Siri Remote 焦点引擎 + AVKit 原生渲染打造，具备完整客厅大屏交互与原生影院体验 | 独立 Xcode 工程，输出 tvOS IPA |

---

## 核心功能特性

### 🧩 CatPawOpen 标准规范与真实 JS 运行时沙箱
- **开源 CatPawOpen 规范**：预置官方首发免费短剧数据源脚本，采用通用 `spider` 规范（`init`, `home`, `category`, `detail`, `play`, `search`），开箱即用；
- **JavaScript 运行时沙箱**：基于 `flutter_js` 深度封装 `CatPawJsRuntime`，在端侧沙箱内原生执行 JS 脚本，注入完整异步 `fetch` 网络客户端、纯 JS 轻量 DOM 解析引擎以及标准控制台与异常隔离机制；
- **单源上下文与数据闭环**：应用所有功能逻辑均运行于当前激活的数据源上下文，包括分类浏览、搜索联想、剧集详情、排行榜、我的追剧与离线下载；
- **多沙箱端侧并发看护**：基于运行时池与并发队列调度，支持 15s 异步超时熔断与多级优雅降级保底；
- **插件管理与自定义导入**：设置页提供专属【JS 数据源插件管理】控制面板，支持查看已装载插件列表、重新扫描重载，以及通过本地文件、远程链接或剪贴板导入第三方符合 CatPawOpen 规范的 JS Spider 脚本。

### ⚡ 影院级视听与交互
- **自适应清晰度与线路切换**：支持流畅、高清、超清、1080P 及原画平滑切换，支持加密流端侧实时解密与防盗链请求头自动适配；
- **沉浸式手势操作**：
  - 手机竖屏模式：上下滑动快速切集，长按屏幕任意区域触发临时 3 倍速快进，轻点即时启停；
  - 横屏影院模式：左右滑动手势调节进度，上下滑动手势调节亮度与音量；
- **系列多季聚拢与快速切换（Multi-Season Engine）**：智能识别剧集季数信息，详情页与播放器选集列表全景展示多季胶囊，无缝换季起播；
- **画质增强引擎**：Windows 桌面端内置定制化 Shader 增强链路（自动 / 省电 / 清晰优先），显著提升大屏观感；
- **智能预热与秒开连播**：换集前轻量预热下一集连接与直链，实现换集平滑秒开。

### 📥 离线缓存与分集下载
- **分集多选与批量队列**：支持从详情页或播放页直接勾选多集，后台并发调度下载；
- **断点续传与完整校验**：本地高性能下载引擎驱动，网络波动自动重试并支持断点续传；
- **一键更新本剧**：追剧更新时，一键自动扫描并补全缺失或新增的分集；
- **本地零流量播放**：已下载内容完全离线可播，支持导出与本地清理；
- **常亮防息屏**：支持在下载时保持屏幕常亮，防止批量下载中断。

### 🔒 隐私安全与私密空间
- **九宫格手势锁**：支持为应用设置九宫格图形解锁，切至后台自动加锁防窥；
- **后台高斯模糊虚化**：应用切入后台或多任务预览界面时，自动触发高斯模糊遮罩；
- **独立私密短剧库**：专属密码保护的私密空间，私密收藏与专属浏览记录不进入常规历史，全方位守护隐私。

---

## 目录结构概览

```
THLRedLook
├── lib/                   # Flutter 跨平台业务逻辑、响应式 UI、播放器控制器、CatPawOpen JS 运行时沙箱
├── android/               # Android 原生平台工程与清单配置
├── ios/                   # iOS 原生平台工程、Podfile 与签名配置
├── macos/                 # macOS 桌面端平台工程与权限配置
├── windows/               # Windows 桌面端 Runner 与 CMake 构建系统
├── tvos/                  # Apple tvOS 原生独立工程（SwiftUI + AVKit + Focus Engine）
├── fastlane/              # 自动化构建与分发工作流脚本
└── scripts/               # 工程工具链与辅助脚本
```

---

## 开发与本地构建

### 环境准备
- **Flutter SDK**：3.47.x+（推荐使用 `fvm`）
- **Python**：3.10+（用于运行工程工具链脚本）
- **平台依赖**：
  - Android：JDK 17+、Android SDK 36
  - iOS / macOS / tvOS：macOS 系统、Xcode 16+、CocoaPods
  - Windows：Visual Studio 2022 C++ 桌面开发套件

### 运行与调试
本项目基于纯 Dart 核心调度引擎与 CatPawOpen JS 运行时沙箱，一键拉取依赖即可运行：

```bash
# 获取 Flutter 依赖
flutter pub get

# 启动本地调试（全平台支持）
flutter run
```

---

## 🚀 GitHub Actions 平台解耦自动化打包与发布 (CI/CD)

项目已配置完全解耦的 GitHub Actions 持续集成与多端自动化打包流水线，修改不同代码按需独立触发，避免全平台重复打包：
- **Flutter 多端流水线（`.github/workflows/build-flutter.yml`）**：
  - **触发机制**：仅在修改 Flutter 跨平台业务代码或各端原生配置（`lib/`、`assets/`、`android/`、`windows/`、`macos/`、`ios/` 等）时触发；支持 `workflow_dispatch` 手动精准单选平台；
  - **Android**：自动编译输出全架构发布 APK（`arm64-v8a`、`armeabi-v7a`、`x86_64`）；
  - **Windows**：自动在 Windows runner 编译并生成免安装绿色便携完整包（含 Shader 画质滤镜与运行环境）；
  - **macOS**：自动编译并生成原生的 `*.dmg` 磁盘镜像安装包（支持直接拖拽至 Applications 目录完成安装）；
  - **iOS**：自动编译打包并上传至 Apple TestFlight；
  - **自动 Release**：Android、Windows 与 macOS 产物自动汇总并创建/更新 GitHub Release 发布页。
- **Apple tvOS 专属流水线（`.github/workflows/build-tvos.yml`）**：
  - **触发机制**：仅在修改 `tvos/` 大屏原生工程或相关脚本时独立触发；
  - **Apple tvOS**：自动归档打包原生 tvOS 独立版 IPA，配置证书后自动上传至 Apple TestFlight。

