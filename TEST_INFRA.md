# E2E Test Infra: 真果·鉴 (Duanju App) macOS 桌面端

## Test Philosophy
- 需求驱动与黑盒验证：完全基于 `ORIGINAL_REQUEST.md` 与用户端使用场景，不依赖内部临时实现细节。
- 综合测试方法体系：采用等价类划分（Category-Partition）+ 边界值分析（BVA）+ 成对组合测试（Pairwise）+ 真实业务负载测试（Workload Testing）。
- 渐进式可测试性：基础交互与状态切换不强依赖复杂站源；真实网络与播放验证独立分层。

## Feature Inventory
| # | Feature | Source (requirement) | Tier 1 | Tier 2 | Tier 3 |
|---|---------|---------------------|:------:|:------:|:------:|
| 1 | macOS 平台构建与原生核心加载 | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 2 | 桌面窗口与响应式布局渲染 | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 3 | 红果源站分类浏览与分页 | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 4 | 红果源站智能搜索与关键词联想 | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 5 | 红果剧集详情、选集切换与清晰度选择 | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 6 | 播放器真实流媒体拉流起播与进度渲染 | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |

## Test Architecture
- **测试运行入口**:
  - 单元与组件测试: `fvm flutter test`
  - 端到端与集成测试: `fvm flutter test integration_test/` (或通过真实桌面端执行脚本)
  - 判定准则: 全部测试用例退出码为 0，无未捕获异常，无布局 Overflow 告警。
- **目录规划**:
  - `test/unit/`: 数据模型、解析算法、参数签名与 FFI 状态测试
  - `test/widget/`: 桌面宽屏窗口 (1280x720 / 1280x800) 下分类、搜索、选集与播放界面组件渲染与交互测试
  - `integration_test/`: 真实网络红果端到端浏览、搜索、选集与播放器起播验证

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | 冷启动 -> 原生初始化 -> 首页红果分类浏览 -> 下拉/翻页加载更多 | F1, F2, F3 | Medium |
| 2 | 搜索输入 -> 关键词联想防抖 -> 结果列表渲染 -> 点击进入剧集详情 | F2, F4, F5 | Medium |
| 3 | 剧集详情 -> 选集切换 (第1集->第2集) -> 清晰度切换 (高清->超清) | F2, F5 | High |
| 4 | 真实红果视频起播 -> 缓冲状态转换 -> 播放进度持续递增 -> 暂停与恢复 | F1, F5, F6 | High |
| 5 | 桌面端全屏切换 -> 窗口缩放 -> 异常断网兜底重试 | F1, F2, F6 | High |

## Coverage Thresholds
- Tier 1: ≥5 用例/功能（共计 6 项功能，最低 30 个基准用例）
- Tier 2: ≥5 用例/功能（边界与异常，最低 30 个边界用例）
- Tier 3: 覆盖核心成对交互组合
- Tier 4: ≥5 个真实业务场景端到端验证
