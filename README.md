# 糖葫芦果鉴 (THLRedLook)

> ⚠️ **免责声明**：本项目源码来自网上大名鼎鼎的**鱼佬**（原作者）。我只是把它拿来打包、测试着玩，方便自己用，**不保证任何可用性，随时可能删库**。

**糖葫芦果鉴**（工程标识：`THLRedLook`，包名 / Application ID：`com.never88gone.redlook`）是一款基于 **Flutter + 纯 Dart 高性能核心引擎** 打造的全平台独立流媒体与短剧聚合应用。

站源请求、协议解析、动态取流、在线播放与离线下载均在设备本地端侧闭环完成，全平台实现真正一键构建与零配置运行；无需搭建任何远程中转或中心化代理服务，兼具极致的启动速度、数据私密性与多端一致的使用体验。

---

## 界面预览

### 🖥️ 桌面端宽屏与分栏视窗 (Windows / macOS)

| 桌面端宽屏分栏全景 | 桌面端高清播放与选集 |
| :---: | :---: |
| ![桌面端全景](assets/screenshots/desktop_overview.png) | ![桌面端播放器](assets/screenshots/desktop_player.png) |

### 📱 移动端核心观影体验 (iOS / Android)

| 首页发现与分类 | 搜索与关键词联想 | 热播短剧排行榜 |
| :---: | :---: | :---: |
| <img src="assets/screenshots/mobile_home.png" width="260" alt="首页发现" /> | <img src="assets/screenshots/mobile_search.png" width="260" alt="搜索联想" /> | <img src="assets/screenshots/mobile_rankings.png" width="260" alt="短剧榜单" /> |

| 剧集详情与选集 | 竖屏沉浸式播放 | 横屏全屏影院模式 |
| :---: | :---: | :---: |
| <img src="assets/screenshots/mobile_detail.png" width="260" alt="剧集详情" /> | <img src="assets/screenshots/mobile_player_portrait.png" width="260" alt="竖屏播放" /> | <img src="assets/screenshots/mobile_player_fullscreen.png" width="360" alt="横屏播放" /> |

### 🗂️ 追剧、历史、离线缓存与插件管理

| 我的追剧收藏 | 最近观看（单源隔离） | 离线下载管理 | JS 数据源插件管理 |
| :---: | :---: | :---: | :---: |
| <img src="assets/screenshots/mobile_follow.png" width="200" alt="我的追剧" /> | <img src="assets/screenshots/mobile_history.png" width="200" alt="最近观看" /> | <img src="assets/screenshots/mobile_downloads.png" width="200" alt="离线下载" /> | <img src="assets/screenshots/mobile_js_sources.png" width="200" alt="JS数据源管理" /> |

### 🔒 隐私安全与私密保险箱

| 九宫格手势锁 | 隐私模式与私密设置 | 独立私密短剧库 |
| :---: | :---: | :---: |
| <img src="assets/screenshots/privacy_lock.png" width="260" alt="九宫格手势锁" /> | <img src="assets/screenshots/privacy_settings.png" width="260" alt="隐私设置" /> | <img src="assets/screenshots/privacy_vault.png" width="260" alt="私密短剧库" /> |

### 📺 Apple tvOS 客厅大屏原生端

| tvOS 首页瀑布流 | tvOS 剧集详情与选集 |
| :---: | :---: |
| ![tvOS首页](assets/screenshots/tvos_home.png) | ![tvOS详情](assets/screenshots/tvos_detail.png) |

| tvOS 热播排行榜 | tvOS 全屏播放与控制层 |
| :---: | :---: |
| ![tvOS榜单](assets/screenshots/tvos_rankings.png) | ![tvOS播放器](assets/screenshots/tvos_player.png) |

---

## 平台支持矩阵

应用深度适配移动端、桌面端与客厅大屏，覆盖以下操作系统与形态：

| 平台 | 形态与特性 | 构建与运行方式 |
| :--- | :--- | :--- |
| **Android** | 适配手机与折叠屏，支持竖屏短剧滑动手势、画中画（PiP）浮窗、arm64-v8a / armeabi-v7a / x86_64 三架构 | 原生 Flutter + NDK 编译，输出 APK / AAB |
| **Android TV** | 自动识别大屏电视模式，锁定横屏影院布局，完整适配遥控器方向键与焦点移动 | 共用 Flutter 源码，自适应电视 UI 布局 |
| **iOS** | 适配 iPhone / iPad，支持深色模式自适应、原生手势返回与后台低功耗下载 | Xcode 签名，输出 IPA 归档 |
| **macOS** | 桌面端大屏响应式三栏/分栏布局，键盘方向键与快捷键全面支持 | macOS App / PKG 安装包 |
| **Windows** | 基于 `media_kit` / libmpv 硬件解码，独家集成专属 Shader 画质增强滤镜 | 独立免安装绿色包 / 便携目录（含完整 DLL 与环境） |
| **Apple tvOS** | 独立原生工程（`tvos/`），纯 SwiftUI + Siri Remote 焦点引擎 + AVKit 原生渲染打造。支持纯净模式引导、JS 插件网络导入、12 项业务页面闭环及单源严格隔离，具备完整客厅大屏交互与原生影院体验 | 独立 Xcode 工程，输出 tvOS IPA |

---

## 核心功能特性

### 🧩 CatPawOpen 标准规范与真实 JS 运行时沙箱 (v1.0.2)
- **全面拥抱开源 CatPawOpen 协议**：站源协议全量升级为 CatPawOpen 标准规范（CatVodOpen 架构），预置官方首发红果免费短剧数据源脚本，采用通用 `spider` 规范（`init`, `home`, `category`, `detail`, `play`, `search`），可直接在端侧沙箱及第三方播放器中开箱即用；
- **真实 JavaScript 运行时沙箱**：基于 `flutter_js` 深度封装 `CatPawJsRuntime`，在端侧沙箱内原生执行 JS 脚本，注入完整异步 `fetch` 网络客户端、纯 JS 轻量 DOM 解析引擎（`html.parse`）以及标准控制台与异常隔离机制；
- **全功能业务数据完全闭环**：
  - **单源上下文锁定**：应用所有功能逻辑均严格运行于红果数据源上下文；
  - **最近播放独立**：【最近观看】记录播放记录与续播进度，支持单项删除与一键清空；
  - **追剧、下载与榜单管理**：【我的追剧】、【离线下载】、【分类浏览】、【搜索联想】及【排行榜单】（含移动端、桌面端与 tvOS 电视端）均高效稳定呈现；
- **多沙箱纯端侧高并发与生命周期看护**：基于 `CatPawRuntimePool` 运行时池与并发队列调度，杜绝并发死锁与野指针崩溃，支持 15s 异步超时熔断与多级优雅降级保底；
- **插件管理与自定义导入**：设置页提供专属【JS 数据源插件管理】控制面板，支持查看已装载插件列表、重新扫描重载，以及通过本地文件、远程订阅链接或剪贴板直接导入第三方符合 CatPawOpen 规范的 JS Spider 脚本；

### ⚡ 影院级视听与交互
- **自适应清晰度与线路切换**：支持流畅、高清、超清、1080P 及蓝光原画无感平滑切换，支持加密流端侧实时解密与防盗链请求头自动适配；
- **沉浸式播放手势**：
  - 手机竖屏模式：上下滑动快速切集，长按屏幕任意区域触发临时 3 倍速快进，轻点屏幕即时启停；
  - 横屏影院模式：支持左右滑动手势调节进度、上下滑动调节亮度与音量；
- **实时在线弹幕**：在线播放支持实时弹幕上屏与侧边栏弹幕设置；
- **系列多季聚拢与快速切换（Multi-Season Engine）**：
  - 智能解析短剧标题中的季数（中文“第N季/部/篇/卷/期”、英文“Season N/S N”、罗马数字“II/III”、纯数字“(2)”及续集词缀），自动清洗“4K超清”、“全集”等噪声；
  - 详情页展示“系列多季”卡片栏，清晰标注当前浏览、观看历史进度与新季未读提醒；
  - 播放器半屏抽屉、移动端底栏选集与桌面端选集列表均支持全景展示多季胶囊，轻点任一季即刻无缝换季起播，并自动接续历史进度；
- **画质增强引擎**：Windows 桌面端内置定制化 Shader 增强链路（自动 / 省电 / 清晰优先），显著提升大屏观感。

### 📥 离线缓存与分集下载
- **分集多选与批量队列**：支持从详情页或播放页直接勾选多集，后台并发调度下载；
- **断点续传与完整校验**：本地高性能下载引擎驱动，网络波动自动重试并支持断点续传；
- **一键更新本剧**：追剧更新时，一键自动扫描并补全缺失或新增的分集；
- **本地零流量播放**：已下载内容完全离线可播，支持导出与本地清理；
- **禁止自动锁屏（Keep Screen On）**：设置与下载偏好中支持开启屏幕常亮，防止批量下载与离线挂机时设备自动息屏休眠中断下载进程。

### 🔒 隐私安全与私密保险箱
- **九宫格手势锁（Pattern Lock）**：支持为应用设置九宫格图形解锁，切至后台自动加锁防窥；
- **后台高斯模糊虚化（Background Blur）**：应用切入后台或多任务预览界面时，自动触发高斯模糊虚化遮罩，杜绝屏幕卡片泄露敏感画面；
- **隐私数据源模式（Private Sources）**：支持将任意数据源设置为隐私模式，切换该数据源需输入密码校验，且未解锁时彻底隐匿对应数据源记录；
- **独立私密短剧库（Privacy Vault）**：专属密码保护的私密空间，私密收藏与专属浏览记录不进入常规历史，全方位守护隐私。

### 📡 局域网无感互联 (LAN Sync)
- **免登录跨设备同步**：基于本地 mDNS / DNS-SD 广播（`_zgj-link._tcp`）自动感知同局域网设备；
- **安全指纹配对**：首连设备握手校验安全证书指纹，杜绝未经授权的局域网串流；
- **双向追剧同步与接续播放**：自动同步追剧进度、观看历史与收藏列表，支持一键将播放流推送至大屏设备接续播放。

---

## 现代化 CI/CD 与自动化交付

项目已全面配置 **Fastlane** 自动化套件与 **GitLab CI / GitHub Actions** 持续集成流水线：

```
THLRedLook
├── fastlane/              # 根目录全局 Fastlane 编排与多端聚合 Lane
├── android/fastlane/      # Android 专用 Fastlane（构建 APK/AAB）
├── ios/fastlane/          # iOS 专用 Fastlane（构建 IPA、证书签名、上传 TestFlight/App Store）
├── macos/fastlane/        # macOS 专用 Fastlane（构建 Mac App、打包 PKG 与交付）
├── tvos/fastlane/         # tvOS 专用 Fastlane（Apple TV 原生应用构建与上传）
└── .gitlab-ci.yml         # 跨平台自动化 CI/CD 流水线定义
```

- **自动化构建**：推送代码或打标签时，流水线自动触发多平台并行编译；
- **动态版本管控**：编译号根据发版时间戳自动计算并对齐（如 `1.0.1+YYYYMMDDHHMM`）；
- **App Store / TestFlight 自动直连**：配置 App Store Connect API Key，支持一键完成签名、归档、校验并直传 TestFlight。

---

## 目录结构概览

```
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
本项目全线基于纯 Dart 核心调度引擎与 CatPawOpen JS 运行时沙箱，**无需预编译任何外部二进制文件**，一键拉取依赖即可运行：

```bash
# 获取 Flutter 依赖
flutter pub get

# 启动本地调试（全平台支持）
flutter run
```

---

## 插件系统与功能状态

- **红果开源首发站源**：出厂内置开源合规的红果免费短剧官方站源，即开即用；
- **CatPawOpen 插件扩展**：支持通过设置面板导入第三方符合 CatPawOpen 规范的 JS Spider 脚本，支持端侧沙箱独立执行；
- **真实数据与零降级逻辑**：彻底清除全工程所有假剧目、写死集数及兜底测试视频流；源站不可达或无内容时如实返回空态视图，严禁使用任何降级假数据；
- **视觉增强与海报 Hero 桥接**：详情页与播放器页面视口引入海报毛玻璃托底（`DramaBackdrop`），营造环境流光溢彩氛围；支持从列表卡片到详情页封面、再到播放器中央封面的全链路 Hero 共享元素飞行动画；底部导航栏去除选中背景边框胶囊，采用现代纯色高亮指示；
- **详情页淡化与防闪烁**：`DramaBackdrop` 增加 `fadeBottom` 渐变遮罩消除底部分割线，`CachedCoverImage` 增加平滑淡入（`AnimatedOpacity`）彻底消除页面进入时的背景闪烁；
- **全屏播放手势避让**：播放控制器与进度条集成底部安全区域（`SafeArea`）避让，杜绝竖屏全屏滑动进度条时误触系统返回与主屏手势；
- **下一集智能预热与秒开连播**：`PlaybackPreloader` 缩短防抖并引入轻量 GET Range 连接预热，当播放进度达 35% 或剩余小于 25 秒提前解析下一集直链并完成 CDN/TLS 握手，换集静默起播零等待；
- **纯粹精简与架构去冗余**：彻底剥离多用户管理模式与 Profiles 切换；清理无效的弹幕开关；完全移除 Emby 导出相关功能与残留文案，本地媒体专注合并成品播放；下线旧局域网/追剧同步入口与遗留的原生内核展示；
- **iOS 沙盒路径友好展示**：存储设置中自动将 iOS 系统冗长私有沙盒路径替换为易读的相对路径（`应用沙盒：Documents/downloads`），符合苹果安全设计规范；
- **全平台原生启动图与深色冷启动过渡**：iOS 重构 `LaunchScreen.storyboard` 采用居中应用品牌 Logo 与 `#101114` 典雅深色背景，补齐 1x/2x/3x 高清启动图，彻底消除冷启动闪白；Android 规范化适配多密度启动图与 Android 12+ 系统级 `SplashScreen` API；macOS / Windows 桌面端实现原生窗口类深色初始画刷，实现全平台秒开深色无缝过渡。
