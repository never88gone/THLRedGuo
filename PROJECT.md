# Project: 真果·鉴 CatPawOpen 标准站源协议全量重构与真实 JS 运行时沙箱

## Architecture
- **JS 运行时与沙箱层 (CatPawJsRuntime & Pool)**:
  - 核心文件: `lib/catpaw_js_runtime.dart`
  - 底层引擎: 基于 `flutter_js: ^0.8.7`，macOS/iOS 原生链接 JavaScriptCore，Android/Windows 链接 QuickJS。
  - 禁用内置脆弱的 `xhr: true`，采用 `xhr: false` 避免无 UI 测试环境下 Asset 依赖异常。
  - 沙箱全局注入:
    - `globalThis.__evalAsync(fn)`: 统一调度同步/异步 Spider 函数，在 Dart 端通过 `_rt.handlePromise` 推进微任务决议；
    - `globalThis.fetch(url, opts)`: 纯 JS 异步网络请求垫片，通过 `onMessage("__fetch__")` 桥接至 Dart 的 `http.Client`，支持注入 `MockClient` 拦截请求实现 100% 离线确定性测试；
    - `globalThis.html.parse(str)`: 纯 JS 轻量 DOM 查询引擎，支持标签、类、ID 选择器、`.text()` 提取与 `.attr()` 读取；
    - `globalThis.console.log`: 安全调试日志垫片。
  - 隔离资源池 (`CatPawRuntimePool`): 按 `sourceId` 创建独立沙箱实例，支持脚本热重载并加入 `_isDisposed` 状态位防范野指针段错误 (SIGSEGV)。
- **数据源规范层 (CatPawOpen Spider Presets)**:
  - 核心文件: `lib/js_source_presets.dart` 与 `assets/sources/hongguo.js`
  - 接口规范: 全面导出标准 Spider 对象 `var spider = { meta, init, home, homeVod, category, detail, play, search }`。
  - 彻底清除旧私有协议特有函数名 (`getCategories`, `getCatalog`, `getDetail`, `getPlayUrl`, `getSuggestions`)。
  - 脚本独立性: 可脱离本项目直接在猫爪 (CatPaw)、MiraPlay 等播放器中开箱即用。
  - 开源版本默认仅内置官方红果短剧源，支持用户通过插件管理导入外部自定义 CatPawOpen Spider 脚本。
- **核心业务调度层 (DartCoreEngine ↔ Models)**:
  - 核心文件: `lib/dart_core_engine.dart`
  - 单例统一门面: `Future<Map<String, dynamic>> dispatch(Map<String, dynamic> input)`
  - 废弃静态假数据逻辑，集成 `CatPawRuntimePool` 驱动 Spider 脚本执行真实解析。
  - 双向透明模型转换:
    - 分类: `spider.home()` -> `CatalogCategory` 列表；
    - 列表与搜索: `spider.category()` / `spider.search()` -> `vod_*` 字段转换为 `Drama`；
    - 选集: `spider.detail()` -> `vod_play_url` 规范串 (`线路$$$第1集$url1#第2集$url2`) 切分为 `chapters` 并将参数保存在 `episode.raw` 中；
    - 播放: `spider.play()` -> 解析直链与防盗链 Headers，生成 `PlaybackPlan`；
    - 高可用降级: 内存缓存 -> 推荐列表附加 warning -> fallback 播放。
- **应用交互与展示层 (Flutter UI & Repositories)**:
  - 核心文件: `lib/core_bridge.dart` (`NativeRepository`), `lib/catalog_screen.dart`, `lib/player_screen.dart`, `lib/search_screen.dart`
  - 保持现有 UI 页面与业务 Service 的调用契约不变，实现零侵入平滑升级。
- **自动化测试与工程一致性校验 (Testing & Sync)**:
  - 核心文件: `test/` (特别是 `test/multi_js_sources_validation_test.dart`、`test/catpaw_js_runtime_test.dart`、`test/dart_core_engine_protocol_mapping_test.dart`)
  - 版本规范: 遵循 `AGENTS.md`，递增 `pubspec.yaml` 版本号至 `1.0.2+19`。
  - 交付收尾: 执行 `python3 scripts/finish_task.py --message "..."` 完成干净源码同步到 `../guoapp` 镜像并校验 Git 状态。

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | CatPawJsRuntime 异步调度与 Promise 决议 | 实现 `__evalAsync` 调度器与 Dart 端 `handlePromise`，抹平同步/异步 Spider 接口并解决 `JSON.stringify(Promise)` 返回空字典问题 | M1 | Survey R1 |
| 2 | 全局 API 垫片内联注入 (fetch/html/console) | 注入纯 JS 异步 `fetch` 垫片（通过 `onMessage` 桥接 `http.Client`）、轻量 DOM 查询引擎 `html.parse` 与安全日志 | M1 | Survey R1 |
| 3 | 独立沙箱隔离池 (CatPawRuntimePool) 与生命周期防崩溃 | 按数据源隔离 JS 上下文，支持实例池化、热重载与 `_isDisposed` 防野指针段错误保护 | M1 | Survey R1 |
| 4 | CatPawJsRuntime 独立单元测试套件 | 编写 `test/catpaw_js_runtime_test.dart`，验证沙箱隔离、垫片注入、异步决议与 MockClient 支持 | M1 | Survey R1, R4 |
| 5 | 红果短剧改写为标准 CatPawOpen Spider 格式 | 改写 `hongguo.js` 与 `lib/js_source_presets.dart`，实现标准 home/category/detail/play/search，清除旧函数名 | M2 | Survey R2 |
| 6 | 开源版本数据源隔离与合规 | 开源版本仅保留红果单一数据源，私有数据源剥离至独立仓库 | M2 | Survey R2 |
| 7 | 开放 JS 扩展插件架构 | 支持从外部导入与动态执行任意标准 CatPawOpen Spider 插件 | M2 | Survey R2 |
| 8 | 插件独立性与跨端沙箱安全 | 确保 Spider 脚本导出规范对象，在 QuickJS/JSC 沙箱中安全隔离运行 | M2 | Survey R2 |
| 11 | DartCoreEngine 集成 CatPawRuntimePool | 引入运行时池，将 `categories`, `catalog`, `detail`, `resolve` 调度平滑替换为调用 Spider 实例 | M3 | Survey R3 |
| 12 | CatPawOpen 数据模型双向透明映射 | 实现 `vod_*` 字段转 `Drama`、`vod_play_url` 切分为章节与 `episode.raw`、`play()` 转 `PlaybackPlan` | M3 | Survey R3 |
| 13 | 核心调度引擎多级容错与高可用降级 | 实现数据源异常、网络超时及格式不符时的多级自动回退（缓存/保底列表/降级播放），杜绝白屏崩溃 | M3 | Survey R3 |
| 14 | DartCoreEngine 协议适配单元测试套件 | 编写 `test/dart_core_engine_protocol_mapping_test.dart`，验证模型转换、选集切分与降级逻辑 | M3 | Survey R3, R4 |
| 15 | 既有测试断言与 Mock 差异适配 | 更新 `test/multi_js_sources_validation_test.dart`，移除旧私有函数名断言，适配 CatPawOpen 规范 | M4 | Survey R2, R3, R4 |
| 16 | 全量自动化测试回归校验 (100% 通过) | 运行 `fvm flutter test`，确保全工程单元测试、Widget 测试无回归失败与运行时异常 | M4 | Survey R4 |
| 17 | 版本递增与工程收尾同步 | 递增 `pubspec.yaml` 至 `1.0.2+19`，执行 `scripts/finish_task.py` 同步到 `../guoapp` 并完成 Git 验证 | M4 | AGENTS.md, R4 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1: 集成真实 JS 运行时与执行沙箱 (CatPawJsRuntime & Pool) | Features 1, 2, 3, 4 | none | DONE |
| 2 | M2: 全量重构 5 大内置数据源脚本为 CatPawOpen 标准规范 | Features 5, 6, 7, 8, 9, 10 | M1 | DONE |
| 3 | M3: 改造核心调度引擎 DartCoreEngine 实现协议适配与数据映射 | Features 11, 12, 13, 14 | M1, M2 | DONE |
| 4 | M4 (Final): 全量测试套件闭环、版本递增与工程同步 | Features 15, 16, 17 | M1, M2, M3 | DONE |

## Interface Contracts
### CatPawJsRuntime ↔ JavaScript Spider
- 沙箱环境提供:
  ```javascript
  globalThis.fetch(url, opts) -> Promise<{ status: number, ok: boolean, body: string, text: () => Promise<string>, json: () => Promise<any> }>
  globalThis.html.parse(htmlString) -> { find(selector), text(), attr(name), eq(idx), length }
  globalThis.console.log(...args)
  ```
- Spider 导出规范:
  ```javascript
  var spider = {
    meta: { id, name, version, description },
    init: function(ext) {},
    home: function(filter) -> { class: [{ type_id, type_name }], filters: {} },
    category: function(tid, pg, filter, extend) -> { page, pagecount, limit, total, list: [ { vod_id, vod_name, vod_pic, vod_remarks, vod_content } ] },
    detail: function(id) -> { list: [ { vod_id, vod_name, vod_pic, vod_content, vod_play_from, vod_play_url } ] },
    play: function(flag, id, flags) -> { parse: 0/1, url, header: {} },
    search: function(wd, quick, pg) -> { list: [ { vod_id, vod_name, vod_pic, vod_remarks, vod_content } ] }
  };
  ```
- 选集格式:
  `vod_play_url` 规范为 `"第1集$url1#第2集$url2"` 或 `"线路1$$$第1集$url1#第2集$url2"`。

### DartCoreEngine ↔ NativeRepository (保持现有契约)
- `dispatch({'action': 'categories', 'source': '...'}) -> {'ok': true, 'categories': [{'id': '...', 'name': '...'}]}`
- `dispatch({'action': 'catalog', 'source': '...', 'category': '...', 'page': 1}) -> {'ok': true, 'dramas': [Drama Map], 'hasMore': bool}`
- `dispatch({'action': 'search', 'source': '...', 'query': '...'}) -> {'ok': true, 'dramas': [Drama Map]}`
- `dispatch({'action': 'detail', 'source': '...', 'dramaId': '...'}) -> {'ok': true, 'drama': Drama Map, 'chapters': [Chapter Map]}`
- `dispatch({'action': 'resolve', 'source': '...', 'dramaId': '...', 'chapter': '...'}) -> {'ok': true, 'plan': PlaybackPlan Map}`

## Code Layout
- `lib/catpaw_js_runtime.dart`: 真实 JS 运行时与执行沙箱封装、沙箱资源池
- `lib/js_source_presets.dart`: 5 大内置数据源脚本定义与预设配置
- `assets/sources/*.js`: 独立静态 JS Spider 脚本文件 (hongguo, hanxiaoquan, yeguo, huangdou, dsd)
- `lib/dart_core_engine.dart`: 核心调度引擎、协议映射器与容错降级
- `lib/models.dart`: 核心业务数据模型 (Drama, Episode, PlaybackPlan 等)
- `lib/core_bridge.dart`: 仓储契约与 UI 接入层 (NativeRepository)
- `test/catpaw_js_runtime_test.dart`: M1 运行时沙箱单元测试
- `test/dart_core_engine_protocol_mapping_test.dart`: M3 调度与映射单元测试
- `test/multi_js_sources_validation_test.dart`: M2/M4 数据源规范验证测试
- `pubspec.yaml`: 项目版本号与依赖定义
- `scripts/finish_task.py`: 干净源码同步与镜像验证脚本
