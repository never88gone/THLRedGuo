# 糖葫芦Haw (THLRedLook)

> ⚠️ **免责声明**：本项目仅供编程学习与个人技术研究使用。代码中所有接口与解析逻辑均在设备端侧沙箱中独立执行，请勿用于任何商业用途。

**糖葫芦Haw**（工程标识：`THLRedLook`，包名 / Application ID：`com.never88gone.redlook`）是一款基于 **Flutter + 纯 Dart 高性能核心调度引擎** 与 **Apple tvOS 原生 SwiftUI** 打造的全平台独立流媒体与短剧聚合应用。

站源请求、协议解析、动态取流、在线播放、实时弹幕与离线下载均在设备本地端侧闭环完成，全平台实现真正一键构建与零配置运行；无需搭建任何远程中转或中心化代理服务，兼具极致的启动速度、数据私密性与多端一致的使用体验。

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
- **开源 CatPawOpen 规范**：预置官方规范短剧数据源脚本，采用通用 `spider` 规范（`init`, `home`, `category`, `detail`, `play`, `search`），开箱即用；
- **JavaScript 运行时沙箱**：基于 `flutter_js` 深度封装 `CatPawJsRuntime`，在端侧沙箱内原生执行 JS 脚本，注入完整异步 `fetch` 网络客户端、纯 JS 轻量 DOM 解析引擎以及标准控制台与异常隔离机制；
- **单源上下文与数据闭环**：应用所有功能逻辑均运行于当前激活的数据源上下文，包括分类浏览、搜索联想、剧集详情、排行榜、我的追剧与离线下载；
- **多沙箱端侧并发看护**：基于运行时池与并发队列调度，支持异步超时熔断与多级优雅降级保底；
- **插件管理与自定义导入**：设置页提供专属【JS 数据源插件管理】控制面板，支持查看已装载插件列表、重新扫描重载，以及导入符合规范的 JS Spider 脚本。

### ⚡ 影院级视听、弹幕与多端交互
- **自适应清晰度与端侧超分增强**：支持 1080P 超清、720P 高清与 360P 标清平滑切换，优先协商高画质媒体流；集成端侧样条插值超分辨率与 Sigmoid 抗锯齿锐化，显著提升在大屏与高分屏上的观影质感；
- **实时弹幕互动**：接入官方真实弹幕协议，支持毫秒级时间轴随播滚动、动态时间窗预取、去重与本地开关记忆，带来沉浸式互动观剧体验；
- **系列多季聚拢与快速切换（Multi-Season Engine）**：智能识别剧集多季信息，详情页与播放器选集列表全景展示多季胶囊，无缝换季起播；
- **沉浸式手势操作**：
  - 手机竖屏模式：上下滑动快速切集，长按屏幕任意区域触发临时 3 倍速快进，轻点即时启停；
  - 横屏影院模式：左右滑动手势调节进度，上下滑动手势调节亮度与音量；
- **智能预热与秒开连播**：换集前轻量预热下一集连接与流地址，实现分集平滑秒开。

### 📥 离线缓存与分集下载
- **分集多选与批量队列**：支持从详情页或播放页直接勾选多集，后台并发调度下载；
- **断点续传与完整校验**：本地高性能下载引擎驱动，网络波动自动重试并支持断点续传；
- **一键更新本剧**：追剧更新时，一键自动扫描并补全缺失或新增的分集；
- **本地零流量播放**：已下载内容完全离线可播，支持导出与本地清理；
- **常亮防息屏**：支持在下载时保持屏幕常亮，防止批量下载中断。

### 🗂️ 本地追剧收藏与播放历史
- **本地收藏与追剧管理**：支持一键收藏短剧，支持“在追”、“想看”状态管理与多维度筛选；
- **精准断点续播**：自动记录每部剧、每一集的播放进度与播放偏好，再次进入直接无缝续播；
- **按站源隔离与安全清理**：历史记录支持按当前激活源独立管理与确认清空，不影响其他数据。

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
- **Flutter SDK**：3.44.x+（推荐使用 `fvm`）
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

## 当前修复与验证状态（2026-10-18）

版本保持 `1.0.0`，保留既有构建号；源码直接在 `main` 维护。登录、扫码登录和官方账号同步继续暂缓，收藏与历史使用本地记录。

针对《满院亲戚全是上古大妖》第五季切换第四季的播放失败，本轮修复：

- 长数字 ID 保护改为识别 JSON 字符串边界，不再改写字符串内部的分页游标、嵌套 JSON 或数字文本；Flutter 与 tvOS 同步修复。
- 加密流播放失败时，先使用已取得的准确分集地址和密钥进行端内缓存解密，再尝试备用地址；缓存与换线路共用恢复次数上限，重新取流保留失败上下文并延迟重试。
- 旧季空闲播放器退出和新播放器首次加载不再全局取消站源请求，减少切季时误取消新季取流的情况。
- 音频设备初始化失败会触发恢复，不能仅凭画面进度继续就判定播放正常；播放日志记录剧集、分集、阶段、错误码和原因，并隐藏签名地址与凭据。

| 验证范围 | 本轮状态 |
| :--- | :--- |
| Flutter iOS 27 模拟器，真实搜索与第五季切换第四季 | 已通过；第五季第 1、4、112、222 集，第四季第 1、4、78、155 集实际起播，验证视频尺寸、进度、音轨与缓存恢复 |
| 同一分集仅有一个有效加密地址 | 已通过；验证时禁用 Web 备用取流，取得第四季地址后拒绝后续取流，仍能用当前地址恢复，刷新接口调用为 0 |
| iOS 搜索分页、连播、弹幕与长视频跳播 | 5 项通过；三组关键词各两页搜索、选集、上下集、自动连播、返回、真实弹幕时间窗及跳播后恢复、缓存清理，47 分钟视频跳播 |
| 离线自动化回归 | 61 项通过，覆盖长整数解析、取消请求、切季加载、错误恢复、缓存清理、弹幕、本地记录与局域网契约 |
| Flutter 静态检查与格式 | `flutter analyze --no-pub` 无问题，修改的 Dart 文件格式检查通过 |
| tvOS JSON 解析与构建 | 原生核心合成数据检查通过，tvOS 27 模拟器构建通过 |
| tvOS 27 遥控操作，真实搜索与第五季切换第四季 | 已通过；第五季第 1 集起播后返回详情切换第四季，验证详情选第 4 集、抽屉选第 7 集、上下集、第 7 集跳至片尾自然结束后接播第 8 集，再切回第五季；抽屉、详情、搜索结果的返回与焦点恢复正常 |
| tvOS 27 原生首帧、音轨与连续播放 | 已通过；第五季第 1 集、第四季第 4 集确认首帧就绪、视频轨、音轨及播放进度，第四季第 4 集跳至片尾自然结束后接播第 5 集并确认首帧、音轨 |
| Android、Windows、macOS、Android TV | 本轮未重新进行设备验证 |

iOS 验证关闭远程海报请求，并保留已有安装与应用数据。当前模拟器的 libmpv 库未编译音频输出后端，已验证遇到该错误后转入 AVPlayer 播放解密缓存；音轨存在和播放进度检查不等同于人工听音验收。端内缓存仍受剩余空间、单集 512 MiB 和下载超时限制；抽样通过不代表官方全片库逐集验收或接口永久可用。

tvOS 本轮使用官方 App 片库真实数据、`XCUIRemote` 遥控按键和界面焦点快照验证，关闭远程海报请求，保留模拟器安装与已有数据，未测试真机。在当前 `main` 上未复现这两季新的播放故障，本轮补充验证记录，不改变播放逻辑、应用版本或构建号。

后续优先级：继续跟进明确失败的剧集及网络重试；按安排集中验证 Android 手机与 Windows，再验证 Android TV，最后补充 iOS 真机及其他平台验证。当前不安排真机测试。
