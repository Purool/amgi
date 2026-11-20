# Amgi Lite —— iOS 14 / UIKit 基础版实施方案

一个独立 App：复用 Rust 引擎与 Swift 引擎桥，不碰 `AmgiFeatures` / `AmgiUI`，
UI 全部用 UIKit 在 iOS 14 方言下重写。目标功能只有三块：**卡组 → 卡片浏览 → 到期复习**。

> **Phase 0 状态（已落地）**：`AmgiLite/` 已可独立构建——Rust 引擎按 14.0 重编、
> 引擎源码已复制进 `AmgiLite/Engine/`（不引用外层 `Sources/`）、`AnkiRustLib`
> 已嵌入且 `MinimumOSVersion 14.0`、引擎冒烟测试通过。
> 验收命令：`cd AmgiLite && ./scripts/verify.sh --test`。

## 1. 目标与非目标

**做**

- 首次启动：创建 collection、导入 `.apkg`、或登录 AnkiWeb 同步
- 卡组列表（new / learn / due 计数）→ 进入复习
- 复习：取卡 → 正面 → 显示答案 → Again/Hard/Good/Easy → 下一张；撤销；结束态
- 浏览：搜索 + 笔记/卡片只读列表
- 设置：collection 信息、同步、导入、关于
- 深色模式、动态字体、基础 VoiceOver、iPhone 竖屏

**不做（v1 明确砍掉）**

- 卡片/模板编辑、牌组选项编辑、FSRS 参数优化
- 统计图表、热力图
- EPUB 阅读器、离线词典
- 小组件、Apple Watch、Live Activity、App Intents
- iPad / 横屏专门布局

## 2. 复用与依赖策略

Lite 用**引擎切片**：相同的源码文件，在新的 Tuist 工程里用不同 target 名编译。

| Lite target | 源码 | 依赖 | 备注 |
|---|---|---|---|
| `LiteProto` | `Sources/AnkiProto/**` | SwiftProtobuf | 生成代码 |
| `LiteKit` | `Sources/AnkiKit/**` | — | 纯 Foundation |
| `LiteBackend` | `Sources/AnkiBackend/**`（排除 `AnkiBackendDependency.swift`） | AnkiRustLib.xcframework, LiteProto, Logging | 见下 |
| `LiteBridge` | `Sources/AnkiProtoBridge/**` | LiteBackend, LiteKit, LiteProto | |
| `LiteSync` | `Sources/AnkiSync/**` | LiteKit | Darwin/Security，iOS 14 可用 |
| `LiteCardWeb` | `Sources/AmgiCardWeb/**` | — | 纯 Foundation，无 WebKit |
| `LiteApp` | `AmgiLite/Sources/**` | 以上全部 | 单一 app target |

所有引擎 target 必须带与主工程相同的 Swift 设置
（`-package-name AnkiBridge`、`AccessLevelOnImport`、`InternalImportsByDefault` 等），
直接复用 `Tuist/ProjectDescriptionHelpers/AmgiModule+SwiftSettings.swift`。

**第三方依赖只有 SwiftProtobuf 和 swift-log。** 这是刻意的：

- `swift-dependencies` 1.17.1 要求 iOS 15（1.10 及以前才是 iOS 13）。
  `AnkiServices` 重度使用 `@DependencyClient`，所以 Lite **不复用** `Sources/AnkiServices`，
  改为新建 `LiteServices`（自注入 `AnkiBackend`，无 DI 宏）。8 个服务文件是参考，不是直接编译。
- `swift-sharing` / `swift-navigation` / `swift-case-paths` / `swift-perception` 全部 iOS 15+，不引入。
- `hoshidicts`（iOS 18）、`EPUBKit`、`ZipArchive`：`AnkiClients` 才需要，整个跳过。
  `.apkg` 的 zip 解析由 Rust 完成，不需要 ZipArchive。

**对既有代码的唯一改动**：`Sources/AnkiBackend/AnkiBackend.swift` 里的
`Synchronization.Mutex`（iOS 18）换成 `NSLock`。主 App 同受影响但语义不变。

**Rust 侧**：`scripts/build-xcframework.sh` 里 `IPHONEOS_DEPLOYMENT_TARGET=14.0`，
只保留 iOS device + simulator 两个切片（删掉 watchOS 的 nightly/build-std 部分）。
产出提交到 `lite` 分支——`.gitignore` 默认忽略 `AnkiRustLib.xcframework`，必须 `git add -f`，
否则 Shard 的每个 worktree 都没有引擎、每个 shard 都要重编 20 分钟。

## 3. 工程结构

```
AmgiLite/
  Project.swift                  # 全部 target 定义（scaffold 独占）
  Sources/
    App/                         # AppDelegate / SceneDelegate / AppContainer / Router / Composition
    DesignSystem/                # AmgiColor / AmgiTypography / AmgiSpacing / 通用控件
    Support/                     # CardWebView / CardAssetScheme / Async / Alert
    Services/                    # Contracts.swift + 各服务实现
    Features/Decks|Review|Browse|Onboarding|Settings/
  Tests/
scripts/lite-verify.sh           # Shard 的统一验收脚本（scaffold 独占）
```

单一 `LiteApp` target + `Sources/**` glob：**加文件不需要改 `Project.swift`**，
这是让多个 agent 并行不打架的前提。引擎 target 也全部用 glob 指向 `../Sources/...`。

`tuist generate --path AmgiLite --no-open` 独立生成，不复用 `AnkiBridge.xcodeproj`。

## 4. UIKit / iOS 14 技术选型

| 需求 | 选型（最低版本） | 不要用 |
|---|---|---|
| 列表 | `UICollectionViewCompositionalLayout.list` (14) + `UICollectionViewDiffableDataSource` (13) | `UICollectionViewListCell` 的 iOS 15 风格配置 |
| 行内容 | `UIListContentConfiguration` (14)、`UIBackgroundConfiguration` (14) | `UIButton.Configuration` (15) |
| 搜索 | `UISearchController` + `searchResultsUpdater` (8) | `.searchable` |
| 刷新 | `UIRefreshControl` | `.refreshable` |
| 导入 | `UIDocumentPickerViewController(forOpeningContentTypes:)` (14) | |
| 菜单 | `UIMenu`/`UIAction` (14)、`UIContextMenuInteraction` (13) | |
| 卡片 | `WKWebView` + `WKURLSchemeHandler` (11)，复用 `AmgiCardWeb.CardAssetPath` | |
| 颜色 | `UIColor(dynamicProvider:)` (13) + `traitCollectionDidChange` | `Color` / 资源目录里的 SwiftUI 色 |
| 字体 | `UIFontMetrics` (11) | `.dynamicTypeSize` |
| 触感 | `UIImpactFeedbackGenerator` | `.sensoryFeedback` |
| 异步 | `async/await`（回部署到 iOS 13）+ `@MainActor` + `backendOffload` | Combine 非必需 |
| 弹层 | `present(_:animated:)` + 自定义高度/全屏 | `UISheetPresentationController` (15) |
| 空态/错误 | 自绘 `EmptyStateView`（图标 + 标题 + 说明 + 主按钮） | `ContentUnavailableView` (17) |

`LiteApp` 用 **Swift 5 语言模式**（`SWIFT_VERSION=5`，`-strict-concurrency=minimal`），
引擎模块保持 Swift 6 严格并发——跨模块混用合法，能把并发噪音砍掉一半。

## 5. 里程碑与 Shard 划分

每个 Phase 跑一次 Shard，Phase 之间人工合并、打 tag。跨 phase 是串行依赖，
一把梭会让 planner 拆出互相引用的任务，反而更难合并。

### Phase 0 —— 脚手架（串行，~1 周，不并行）

| ID | 任务 | 产出 | 验收 |
|---|---|---|---|
| M0.1 | Rust 14.0 重编（iPhone 两切片） | `AnkiRustLib.xcframework` 提交到 `lite` 分支 | `otool -l` 里 `minos 14.0` |
| M0.2 | Lite Tuist 工程 + 引擎切片 + 空壳 App | `AmgiLite/Project.swift` | `xcodebuild build` 部署目标 14.0 通过 |
| M0.3 | 接口冻结 | `Services/Contracts.swift`、`App/AppContainer.swift`、`App/Router.swift`、`DesignSystem/Tokens.swift`、`Support/CardWebView.swift`（协议 + 假实现） | 全工程编译 |
| M0.4 | 引擎冒烟单测 | `Tests/EngineSmokeTests.swift`：打开 collection → `fetchTree` → `getQueuedCards` → `renderCard` → `answerReviewCard` | `./scripts/lite-verify.sh` 绿 |
| M0.5 | 真机验证 | iPhone 6s/7 上能起、能列出卡组 | 手动 |

**Gate：M0.5 不过就不要开 Shard。** iOS 14 模拟器 runtime 在 Xcode 26 已经没有，
真机是唯一能验证 WebKit / SQLite / 内存行为的地方。

### Phase 1 —— 并行 3 个 shard（~1.5 周）

| Shard | 目标 | 独占文件 | 依赖 | 验收 |
|---|---|---|---|---|
| S1 `services` | 实现 `Contracts` 的 6 个服务：Collection/Decks/Review/Notes/Import/Sync，全部走 `backendOffload` | `AmgiLite/Sources/Services/**`（`Contracts.swift` 除外） | M0 | 单测覆盖每个方法的成功 + 错误路径 |
| S2 `design-system` | 色板（从 `AmgiUI/Sources/Theme` 抄十六进制，不 import）、字号、间距、主按钮、空态/加载/错误视图 | `AmgiLite/Sources/DesignSystem/**`（`Tokens.swift` 除外） | M0 | 一个 demo VC 截图；深色模式两套 |
| S3 `card-web` | `CardWebView`：WKWebView + `WKURLSchemeHandler`（media/assets/card 三个 host）+ 高度自适应 + 加载/失败态 | `AmgiLite/Sources/Support/**`（`CardWebView` 协议除外） | M0 | 用固定 HTML fixture 渲染出正面/背面 |
| S4 `shell` | AppDelegate/SceneDelegate、TabBar、`Router` 落地、占位页接线 | `AmgiLite/Sources/App/**`（`AppContainer`/`Router`/`Composition` 除外） | M0 | 三个 tab 能切换，占位页正常 |

> `CardAssetScheme` 不能直接复制——它 `import AnkiClients` + `Dependencies`。
> 参考实现，用 `CardAssetPath` + 一个 `() -> URL?` 的 media 闭包重写。

### Phase 1.5 —— 集成（串行，2 天）

| ID | 任务 | 独占文件 |
|---|---|---|
| S5 `integration-1` | 在 `Composition.swift` 里把 S1/S2/S3 接进 shell；卡组列表先用临时列表 | `AmgiLite/Sources/App/Composition.swift` |

### Phase 2 —— 并行 3 个 shard（~2 周）

| Shard | 目标 | 独占文件 | 依赖 |
|---|---|---|---|
| S6 `decks` | 卡组列表页：diffable、计数徽章、下拉刷新、空态、进入复习 | `Sources/Features/Decks/**` | S5 |
| S7 `review` | 复习页：取卡、Q/A 切换、四键评分（含学习步长）、撤销、结束态、进度 | `Sources/Features/Review/**` | S5 |
| S8 `browse` | 浏览页：`UISearchController`、笔记/卡片行、只读详情、分页 | `Sources/Features/Browse/**` | S5 |

### Phase 2.5 —— 集成（串行，2 天）

| S9 `integration-2` | 三个页面接进 `Router`，去掉占位页 | `Sources/App/Composition.swift` |

### Phase 3 —— 并行 2 个 shard + 收尾（~1.5 周）

| Shard | 目标 | 独占文件 | 依赖 |
|---|---|---|---|
| S10 `onboarding` | 首次启动引导、`.apkg` 导入（进度/错误/取消）、collection 创建 | `Sources/Features/Onboarding/**` | S9 |
| S11 `settings-sync` | 设置页、AnkiWeb 登录、同步（进度/冲突提示）、关于 | `Sources/Features/Settings/**` | S9 |
| S12 `polish`（串行） | 深色模式回归、动态字体、VoiceOver 标签、错误文案、内存/性能 | 全仓小改 | S10/S11 |

### Phase 4 —— 交付（串行，~1 周）

S13 测试补齐（服务层 + 路由）、真机回归、TestFlight、`Documentation/` 更新。

## 6. Shard 使用方式

```toml
# shard.toml
[agent]
backend = "claude-code"
max_concurrent = 3          # Xcode 编译很吃内存，4 个 agent 同时 xcodebuild 会 swap
stagger_delay_s = 5.0

[timeouts]
per_task_s = 1800           # tuist + xcodebuild 一次要几分钟
global_s = 28800             # 一个 phase
output_stall_s = 600
commit_stall_s = 900

[test]
runner = "bash"
args = ["scripts/lite-verify.sh"]
```

运行节奏：

```bash
shard plan -p "$(cat prompts/phase1.txt)"   # 先看 planner 给的 file ownership，改到与下表一致再跑
shard run  -p "$(cat prompts/phase1.txt)" --agents 3 --max-cost 30
```

写 prompt 的要点（planner 是 LLM，给它边界，不要让它自己想架构）：

1. 粘贴本 Phase 的 shard 表格，明确「每个 task 只能改它独占的文件」。
2. 粘贴 `Contracts.swift` 的接口定义，说明「不得修改协议，只能实现」。
3. 说明「新文件放在自己的目录下，不需要改 `Project.swift`」。
4. 验收命令固定为 `./scripts/lite-verify.sh`。
5. 明确禁止：改 `Sources/` 下的既有引擎代码（除 M0 的 Mutex 修复）、改 `AmgiLite/Project.swift`。

## 7. 风险清单

| 风险 | 影响 | 对策 |
|---|---|---|
| `AnkiRustLib.xcframework` 被 gitignore | 每个 worktree 没引擎，shard 全挂 | 14.0 产物 `git add -f` 提到 `lite` 分支；或 `scripts/lite-setup.sh` 从共享目录软链 |
| `Tuist/.build` 被 gitignore | 每个 worktree 重新 `tuist install`（慢、要网络） | 首次安装后软链 `Tuist/.build` 到各 worktree |
| `anki-upstream` 是 submodule | worktree 里为空 | Lite 构建不需要它，prompt 里禁止 `git submodule update` |
| iOS 14 模拟器 runtime 不存在 | 无法自动化验证 14 | 真机 iPhone 6s/7；CI 只做 14.0 编译 + 15/16 模拟器测试 |
| Shard 的 planner 自行拆任务、交叉引用 | 合并冲突 | 每 phase 单独跑；先 `shard plan` 审 ownership |
| Swift 6 严格并发 + UIKit | 大量隔离告警 | App target 用 Swift 5 模式 |
| `.apkg` 导入内存峰值 | 大包 OOM | 导入走后台线程 + 进度回调；v1 限制 500MB |
| iOS 14 WebKit 不支持 `:has()` / `aspect-ratio` | 少数牌组样式崩 | 接受；文档里说明 |
| 大 collection（10 万卡）列表 | 卡顿 | 浏览分页（每页 200）+ 搜索在 Rust 侧 |

## 8. 排期

| 阶段 | 串行 | 并行后 |
|---|---|---|
| Phase 0 | 1 周 | 1 周 |
| Phase 1 + 1.5 | 2 周 | 1.5 周 |
| Phase 2 + 2.5 | 2.5 周 | 2 周 |
| Phase 3 | 2 周 | 1.5 周 |
| Phase 4 | 1 周 | 1 周 |
| **合计** | **~8.5 周** | **~7 周（含 buffer 8 周）** |

并行收益没有想象中大：Xcode 编译是瓶颈，而且每个 phase 都要串行集成。
真正的加速点在 Phase 2（三个页面完全独立）。
