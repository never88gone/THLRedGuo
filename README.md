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

---

## 📝 版本更新记录

### v1.0.0 (2026-10-16)
- **Apple tvOS 客厅大屏端遥控器焦点体验全面重构与多季全链路闭环**：
  - **多季选择行焦点穿透彻底修复**：重构 `TVSeasonCapsuleCard` 架构，内嵌 Label 结构自主读取 `@Environment(\.isFocused)`；横向容器引入 `.focusSection()` 空间隔离，彻底杜绝 tvOS 焦点引擎向下碰撞时纵向跳过多季行的缺陷。
  - **全链路确定性双向焦点回弹**：打通【顶部播放按钮】<->【多季选择行】<->【选集分段 Tab】<->【集数网格第一排】的全闭环定向焦点导航，无论是按 Down 下落还是按 Up 回弹均 100% 稳定着陆。
  - **换季平滑过渡与焦点稳固锁定**：优化详情页加载条件，换季时原地保留已有季列表并即时刷新当前季高亮，避免全屏 ProgressView 卸载重构销毁焦点；优化季数正则剥离算法，确保多季选择行常驻不闪烁、不丢失。
  - **选集分段 Tab（1-50, 51-100...）与集数 4 态矩阵**：重塑分段胶囊与选集按钮在未选聚焦（Hover）、选中聚焦（Selected & Hover）、选中未聚焦（Selected Idle）及普通状态下的高对比度大屏视觉（纯白高光底+纯黑粗字+鲜艳红框+外发光）。
  - **搜索卡片自感知焦点**：修复海报卡片因外层环境注入与系统白光屏蔽导致的无焦点样式问题，提供 4.0pt 鲜艳主题红外框与悬浮放大高亮。
- **全面排查与修复部分剧集无法播放的问题**：
  - **支持官方 App API 双轨详情解析**：在数据源中内置纯 JS 字节跳动 Gorgon 签名算法，优先通过官方 App 详情接口（`/novel/player/video_detail/v1/`）获取 100% 完整权威的分集列表及真实 `vid`，彻底解决网页版缺少分集或 404 时无法播放的问题。
  - **增强真实流解析与 Base64 自动解码**：取流时支持从播放页中自动识别并 Base64 解码真实的播放流地址，提供高清直接流播放能力。
  - **严防伪链接与大整数截断**：全面消除将 `series_id` 当作单集 `vid` 生成 404 伪媒体流的缺陷；强化大整数防溢出处理，杜绝 ID 尾号精度丢失被截断为 `000` 造成的失效。
  - **多季占位与下架识别**：准确识别全 0 集或未上映占位季，提供友好交互提示，防止误切崩溃。
- **Flutter 源码架构分层系统化整理（模块化按文件夹规范存放）**：
  - **根目录彻底整洁纯净**：彻底清理移除了 `lib/` 根目录下原先散乱平铺的 80 余个 Dart 源码文件，`lib/` 根目录仅保留标准应用入口 `main.dart`。
  - **职责单一的五大标准分层体系**：
    - `lib/pages/`：页面与路由级视图（详情页、下载页、局域网页、用户配置页、排行榜页、推荐页、数据源页、设置页、播放页、首页、私密空间页、关于页等）；
    - `lib/core/`：核心架构与引擎底层（Dart核心调度引擎、JS沙箱运行时、原生桥接、本地存储/书架、播放器控制器、剧集与选集算法、弹幕逻辑、画质增强、局域网共享与同步、后台下载队列、媒体库导出合并、分类维护等）；
    - `lib/views/`：可复用界面小部件与视图组件（分集浏览器、分类筛选栏、搜索输入框、源切换弹窗、底部导航条、下载选集浮层、电视遥控交互组件、通用图标、播放器面板/顶栏/底栏/视口、剧集封面等）；
    - `lib/utils/`：工具类与平台辅助（日记与日志服务、封面解码、视频输出尺寸计算、屏幕方向与自适应布局、数据源门控、配置中心、构建变量、冒烟测试、主题管理等）；
    - `lib/models/`：业务领域数据模型（公共剧集与分类模型、弹幕模型、局域网同步模型、私密保险箱模型、排行榜模型等）。
  - **统一模块化包导入与零错误严苛验收**：全面升级所有内部依赖为 `package:THLRedLook/...` 规范导入路径，通过 `flutter analyze` 静态分析（0 error / 0 warning / 0 info，`No issues found!`），并通过全部 44 项单元测试以及真机模拟器端到端 UI 自动化测试。
