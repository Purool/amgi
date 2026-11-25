# Amgi Lite —— iOS 14 / UIKit 实施方案

一个独立 App：复用 Rust 引擎与 Swift 引擎桥，不碰 `AmgiFeatures` / `AmgiUI`，
UI 全部用 UIKit 在 iOS 14 方言下重写。

**定位**：卡组 → 复习 → 浏览，加上 **卡片与模板编辑（含卡片文字）、牌组选项、FSRS 参数优化**。

`AmgiLite/` 是**自包含目录**：代码、计划、文档都在这里，整体移出仓库后
`./scripts/verify.sh` 仍然成立。上层目录只作只读输入——`../Sources` 是引擎副本的同步来源，
`../anki-bridge-rs` + `../anki-upstream` 只用于重编 `Frameworks/` 里的 xcframework。
**不要修改上层目录，也不要把 Lite 的文档写进 `../Documentation`。**

## 现状

| 阶段 | 内容 | 状态 |
|---|---|---|
| Phase 0 | Rust 按 14.0 重编、Tuist 工程、引擎切片、冒烟测试 | 已落地 |
| Phase 1 | 服务层、设计系统、`CardWebView`、shell | 已落地 |
| Phase 2 | Decks / Review / Browse | 已落地 |
| Phase 3 | Onboarding / Settings（AnkiWeb 登录、同步、`.apkg` 导入）/ 收尾 | 已落地 |
| **Phase 4** | **卡片模板编辑、卡片文字编辑、牌组选项、FSRS 优化** | **P0 已落地**；P1 见 §5.2 与 `AMGI_LITE_PHASE4_PLAN.md` |
| Phase 5 | 测试补齐、真机回归、AppIcon、TestFlight | 未开始 |

当前代码：`Features/Decks`（diffable 卡组列表 + 计数徽章 + Deck Options 长按菜单）、
`Features/Review`（Q/A 切换、四键评分、撤销、结束态）、`Features/Browse`（搜索 +
笔记列表/详情 + 模态编辑）、`Features/Settings`（AnkiWeb 登录/同步、`.apkg` 导入、
Note Types、关于）、`Features/Onboarding`（创建 collection / 导入 / 登录，可跳过）、
`Features/DeckOptions`（预设、限制、顺序、高级、FSRS 与权重屏）、
`Features/Templates`（笔记类型列表、模板编辑器、预览、校验）、
`Features/NoteEditor`（字段/标签、删除、未保存预览）。测试 56 个用例
（引擎冒烟 1 + 服务 7 + 同步 5 + Phase 4 引擎级 14 + 纯逻辑 29）。

验收命令只有一个：

```bash
cd AmgiLite && ./scripts/verify.sh --test
```

## 1. 目标与非目标

**做**

- 首次启动三选一：创建 collection、导入 `.apkg`、登录 AnkiWeb 同步
- 卡组列表（new / learn / due 计数）→ 进入复习
- 复习：取卡 → 正面 → 显示答案 → Again/Hard/Good/Easy → 下一张；撤销；结束态
- 浏览：搜索 + 笔记列表/详情
- **卡片文字编辑**：编辑笔记字段与标签、删除笔记、未保存预览（Phase 4）
- **卡片模板编辑**：笔记类型列表、模板（正面/背面/样式）、字段插入、预览、校验（Phase 4）
- **牌组选项**：预设切换/新建/重命名/删除、每日上限、新卡/遗忘/埋藏/顺序/高级（Phase 4）
- **FSRS 参数优化**：单预设优化、全部预设优化、权重与期望保留率（Phase 4）
- 设置：collection 信息、同步、导入、关于
- 深色模式、动态字体、基础 VoiceOver、iPhone 竖屏

**不做（明确砍掉）**

- 统计图表、热力图
- EPUB 阅读器、离线词典
- 小组件、Apple Watch、Live Activity、App Intents
- iPad / 横屏专门布局
- 图像遮挡编辑器、`ChangeNotetype`、恢复原生模板
- 笔记类型的新建/复制/删除、字段管理、新建笔记（Phase 4 的 P1，默认不进本轮）
- FSRS 模拟器、最优保留率扫描、`fsrsReschedule`
- 笔记里的媒体插入（桥接没有 `storeMediaFile`；只能编辑已有文本）

## 2. 复用与依赖策略

### 2.1 target 与源码

Lite 用**引擎切片**：相同的源码文件，在新的 Tuist 工程里用不同 target 名编译。

| target | 源码 | 依赖 | 备注 |
|---|---|---|---|
| `AmgiLite` | `Sources/**`（单 glob） | 下列全部 | app，Swift 5 语言模式 |
| `AnkiKit` | `Engine/AnkiKit/**` | — | 纯 Foundation 领域类型 |
| `AnkiProto` | `Engine/AnkiProto/**` | SwiftProtobuf | 生成代码 |
| `AnkiBackend` | `Engine/AnkiBackend/**` | `AnkiProto`、`AnkiRustLib.xcframework`、swift-log | C FFI + `Request<R>` 分发 |
| `AnkiProtoBridge` | `Engine/AnkiProtoBridge/**` | `AnkiKit`、`AnkiBackend`、`AnkiProto` | protobuf ↔ 镜像边界 |
| `AnkiSync` | `Engine/AnkiSync/**` | `AnkiKit` | Keychain 等同步基础件 |
| `AmgiCardWeb` | `Engine/AmgiCardWeb/**` | — | 卡面 HTML 重写 / 资源路径，无 WebKit |
| `AmgiLiteTests` | `Tests/**` | app + 上述引擎 target | 单元测试 |

引擎 target 必须带与主仓相同的 Swift 设置（`-package-name AnkiBridge`、
`AccessLevelOnImport`、`InternalImportsByDefault` 等），由
`Tuist/ProjectDescriptionHelpers/LiteModule.swift` 统一配置。
`Sources/**` 单 glob 意味着**加文件不用改 `Project.swift`**。

### 2.2 引擎副本与 iOS 14 补丁

`Engine/` 是 `../Sources/` 的副本。与上游的差异只有 4 处，其余模块逐字节一致：

| 位置 | 差异 | 原因 |
|---|---|---|
| `Engine/AnkiBackend/AnkiBackend.swift` | `import Synchronization` 去掉；`Mutex` 换成 `NSLock` + `withStateLock`；类改为 `@unchecked Sendable` | `Synchronization.Mutex` 是 iOS 18 |
| `Engine/AnkiBackend/AnkiBackendDependency.swift` | 删除 | `@DependencyClient` 依赖 `swift-dependencies`（1.17 起 iOS 15） |
| `Engine/AmgiCardWeb/NativeCardContent.swift` | 删除 | 基于 `AttributedString`（iOS 15） |
| `Engine/AmgiCardWeb/CardAssetPath.swift` | `url.path(percentEncoded: true)` → `url.path` | 前者是 iOS 16 |

`AnkiKit` / `AnkiProto` / `AnkiProtoBridge` / `AnkiSync` 与主仓**相同**。
**主仓没有被 Lite 改动**——补丁只存在于副本里。

同步流程与补丁重打步骤见 `Engine/AGENTS.md`；`Engine/README.md` 记录同一份差异清单。
漏掉补丁的典型报错：`cannot find 'Mutex' in scope`、
`'path(percentEncoded:)' is only available in iOS 16.0 or newer`、
`'AttributedString' is only available in iOS 15.0 or newer`。

### 2.3 第三方依赖

**只有 SwiftProtobuf 和 swift-log**（`Tuist/Package.swift`：`swift-protobuf` 1.28+、
`swift-log` 1.0+）。这是刻意的：

| 包 | 版本门槛 | 为什么不在 Lite 里 |
|---|---|---|
| `swift-dependencies` | 1.17 起 iOS 15 | `AnkiServices` 重度使用 `@DependencyClient`；Lite 的服务层用显式构造注入 |
| `swift-sharing` / `swift-navigation` / `swift-case-paths` / `swift-perception` | iOS 15 | SwiftUI 时代的 state/navigation，UIKit 版不需要 |
| `hoshidicts` | iOS 18 | 只服务阅读器/词典 |
| `EPUBKit` / `ZipArchive` | iOS 17 / 15.5 | 只服务阅读器；`.apkg` 的 zip 解析在 Rust 里 |

`Sources/AnkiServices`、`Sources/AnkiClients` 只作参考，不编译。

### 2.4 Rust 二进制

`Frameworks/AnkiRustLib.xcframework` 按 `IPHONEOS_DEPLOYMENT_TARGET=14.0` 构建，
只有 device + simulator 两个切片（没有 watchOS），**已提交**：worktree 和"移出仓库的
AmgiLite"都不需要 20 分钟 Rust 构建才能编译 App。

重编只能在 monorepo 内执行：

```bash
cd AmgiLite && ./scripts/build-engine.sh          # 全量
cd AmgiLite && ./scripts/build-engine.sh --sim-only
```

`build-engine.sh` 读上层的 `anki-bridge-rs/`、`anki-upstream/` 和 `scripts/patches/`，
产出写回 `AmgiLite/Frameworks/`。仓库 `.gitignore` 默认忽略 xcframework，提交时必须
`git add -f`，否则每个 worktree 都没有引擎。

## 3. 工程结构

```
AmgiLite/
  AGENTS.md                       # agent 规则（本目录自包含）
  AMGI_LITE_IOS14_PLAN.md         # 本文件：总计划
  AMGI_LITE_PHASE4_PLAN.md        # Phase 4 实施细节（当前阶段）
  README.md                       # 对外说明
  Project.swift                   # 全部 target（scaffold 独占）
  Tuist.swift / Tuist/            # 独立 Tuist root + 依赖清单
  Info.plist                      # scene manifest、竖屏、arm64
  Engine/                         # 主仓 Sources/ 的副本，见 Engine/AGENTS.md
  Frameworks/                     # AnkiRustLib.xcframework（产物，已提交）
  Sources/
    App/                          # AppDelegate / SceneDelegate / AppContainer / Router / Composition
    DesignSystem/                 # 颜色 / 字体 / 间距 / 通用控件 / 表单行
    Services/                     # Contracts.swift + Live*Service + CollectionSession
    Support/                      # CardWebView、scheme handler、alert、进度卡、错误文案
    Features/Decks|Review|Browse|Onboarding|Settings/
    Features/DeckOptions|Templates|NoteEditor/   # Phase 4 新增（规划）
  Tests/AmgiLiteTests/            # 真引擎单测
  scripts/verify.sh               # 唯一验收命令
  scripts/build-engine.sh         # 重编 Frameworks/（仅 monorepo 内）
  scripts/install-device.sh       # 签名 + 装到已连接的真机
```

`tuist generate --path AmgiLite --no-open` 独立生成，不复用 `AnkiBridge.xcodeproj`。
生成产物（`AmgiLite.xcodeproj`、`.xcworkspace`、`Derived/`、`.build/`、`Tuist/.build/`）
全部被 gitignore，`Project.swift` 才是要编辑的地方。

## 4. UIKit / iOS 14 技术选型

| 需求 | 选型（最低版本） | 不要用 |
|---|---|---|
| 列表 | `UICollectionViewCompositionalLayout.list` (14) + `UICollectionViewDiffableDataSource` (13) | iOS 15+ 的 list cell 便捷 API |
| 行内容 | `UIListContentConfiguration` (14)、`UIBackgroundConfiguration` (14) | `UIButton.Configuration` (15) |
| 行的尾部控件 | `UICellAccessory.customView` (14)（`UISwitch` / `UIStepper` / `UITextField`） | 自绘整行 |
| 分区头/脚注 | `UICollectionLayoutListConfiguration.headerMode = .supplementary` (14) | — |
| 菜单 | `UIMenu` / `UIAction` (14)、`showsMenuAsPrimaryAction` (14)、`UIContextMenuInteraction` (13) | — |
| 行重排 | diffable `reorderingHandlers` (14) | 手写拖拽 |
| 搜索 | `UISearchController` + `searchResultsUpdater` (8) | `.searchable` |
| 刷新 | `UIRefreshControl` (6) | `.refreshable` |
| 导入 | `UIDocumentPickerViewController(forOpeningContentTypes:)` (14) | — |
| 卡片 | `WKWebView` + `WKURLSchemeHandler` (11)，复用 `AmgiCardWeb.CardAssetPath` | — |
| 文本编辑 | `UITextView` + 自定义 `inputAccessoryView`；关 `smartQuotes` / `smartDashes` / 自动纠错 | `NSAttributedString` 的 HTML 导入（易崩） |
| 等宽字体 | `UIFont.monospacedSystemFont(ofSize:weight:)` (13) + `UIFontMetrics` | `.monospaced` 的 SwiftUI 修饰符 |
| 颜色 | `UIColor(dynamicProvider:)` (13) + `traitCollectionDidChange` | `Color` / 资产目录里的 SwiftUI 色 |
| 字体 | `UIFontMetrics` (11) | `.dynamicTypeSize` |
| 键盘避让 | `keyboardWillChangeFrameNotification` + `contentInset` | `UIKeyboardLayoutGuide` (15) |
| 触感 | `UIImpactFeedbackGenerator` (10) | `.sensoryFeedback` |
| 异步 | `async/await` + `@MainActor` + `backendOffload` | Combine 非必需 |
| 弹层 | `present(_:animated:)` + 自定义高度/全屏 | `UISheetPresentationController` (15) |
| 空态/错误 | 自绘 `LoadingStateView` / `EmptyStateView` / `ErrorStateView` | `UIContentUnavailableConfiguration` (17) |

`AmgiLite` 用 **Swift 5 语言模式**（`SWIFT_VERSION=5.0`、`-strict-concurrency=minimal`），
引擎 target 保持 Swift 6 严格并发。跨模块混用合法，能把 UIKit 侧的一半并发噪音砍掉。

## 5. 里程碑与 Shard 划分

每个 Phase 跑一次 Shard，Phase 之间人工合并、打 tag。跨 phase 是串行依赖。

### 5.1 Phase 0–3（已落地）

| Phase | Shard | 结果 |
|---|---|---|
| 0 脚手架 | M0.1–M0.5 | 14.0 引擎、Tuist 工程、契约冻结、冒烟测试、真机起得来 |
| 1 基础层 | S1 `services` / S2 `design-system` / S3 `card-web` / S4 `shell` | 6 个服务走 `backendOffload`；色板/字号/间距/状态视图；`CardWebView` + `amgi-asset://`；三个 tab |
| 1.5 集成 | S5 `integration-1` | `Composition.swift` 接进 shell |
| 2 三个页面 | S6 `decks` / S7 `review` / S8 `browse` | diffable 卡组列表、Q/A + 四键 + 撤销、搜索 + 只读详情 |
| 2.5 集成 | S9 `integration-2` | 三页接进 `Router` |
| 3 收尾 | S10 `onboarding` / S11 `settings-sync` / S12 `polish` | 首次启动三选一；AnkiWeb 登录/同步/`fullSync`/媒体进度；导入；深色/动态字体/VoiceOver |

### 5.2 Phase 4 —— 卡片与模板编辑、牌组选项、FSRS（P0 已落地）

| ID | 内容 | 依赖 | 人日 |
|---|---|---|---|
| M4.0a `services` | `DeckOptionsServicing` / `NotetypeServicing` / `NoteEditingServicing` + `LiteServices` 装配 + `DeckRow.isFiltered` + 引擎级单测 | — | 4 |
| M4.0b `forms` | 表单行（switch/stepper/text/menu/disclosure/slider/action/info）、`AmgiTypography.mono`、键盘避让、调试画廊 | — | 3 |
| M4.1 `deck-options` | 牌组选项屏 + 预设 CRUD + FSRS 段 + 权重屏（含优化与"全部预设"） | M4.0 | 6 |
| M4.2 `templates` | 笔记类型列表 + 模板编辑器 + 预览 + 校验 + 字段插入 | M4.0 | 6 |
| M4.3 `note-editor` | 编辑笔记字段/标签、删除、预览（新建笔记为 P1，+2 天） | M4.0 | 3.5 |
| M4.4 `integration` | `Router` / `Composition` / 卡组上下文菜单 / Settings「Note Types」/ 浏览与详情入口 | M4.1–M4.3 | 2.5 |
| M4.5 `polish` | 错误文案、动态字体/深色/VoiceOver、真机回归、文档 | M4.4 | 4 |

引擎侧**不需要任何改动**——所需的 13 个 RPC 在 `Engine/AnkiProtoBridge` 里都已有 `public`
工厂。字段/模板/笔记/牌组选项的语义陷阱、契约、界面与测试细节见
**`AMGI_LITE_PHASE4_PLAN.md`**（本阶段的唯一实施依据）。

**as-built（2026-11）**：M4.0a–M4.4 的 P0 全部落地，M4.0b 的调试画廊与
M4.1/4.2/4.3 的 P1 项（字段管理、新建笔记、新建/复制笔记类型、复习屏菜单）没有做。
`./scripts/verify.sh --test` 在 iPhone 17 模拟器上 56/56 通过；部署目标仍是 14.0。
实施偏差见 `AMGI_LITE_PHASE4_PLAN.md` §10。

### 5.3 Phase 5 —— 交付（串行，~1 周）

测试补齐（服务层 + 视图模型状态机）、真机回归（iPhone 6s/7，iOS 14.x）、
AppIcon、TestFlight、文档收尾。

## 6. Shard 使用方式

```toml
# shard.toml
[agent]
backend = "claude-code"
max_concurrent = 2          # Xcode 编译很吃内存；4 个同时 xcodebuild 会 swap
stagger_delay_s = 5.0

[timeouts]
per_task_s = 1800           # tuist + xcodebuild 一次要几分钟
global_s = 28800            # 一个 phase
output_stall_s = 600
commit_stall_s = 900

[test]
runner = "bash"
args = ["scripts/verify.sh"]
```

运行节奏：

```bash
shard plan -p "$(cat prompts/phase4.txt)"   # 先看 planner 给的 file ownership，改到与下表一致再跑
shard run  -p "$(cat prompts/phase4.txt)" --agents 2 --max-cost 30
```

写 prompt 的要点（planner 是 LLM，给它边界，不要让它自己想架构）：

1. 粘贴本 Phase 的 shard 表格，明确「每个 task 只能改它独占的文件」。
2. 粘贴 `Contracts.swift` 的接口定义，说明「不得修改协议，只能实现」。
3. 说明「新文件放在自己的目录下，不需要改 `Project.swift`」。
4. 验收命令固定为 `./scripts/verify.sh`（必要时 `--test`）；沙箱里跑不了 tuist/xcodebuild
   是已知限制，不要手搓 xcodebuild 交差。
5. 明确禁止：改 `Engine/`、改 `Project.swift`、改上层任何目录、引入新依赖、用 SwiftUI。

## 7. 风险清单

| 风险 | 影响 | 对策 |
|---|---|---|
| `AnkiRustLib.xcframework` 被 gitignore | 每个 worktree 没引擎，shard 全挂 | 产物 `git add -f`；或从共享目录软链 |
| `Tuist/.build` 被 gitignore | 每个 worktree 重新 `tuist install`（慢、要网络） | 首次安装后软链到各 worktree |
| `anki-upstream` 是 submodule | worktree 里为空 | Lite 构建不需要它；prompt 里禁止 `git submodule update` |
| 没有 iOS 14 模拟器 runtime | 无法自动化验证 14 | 真机 iPhone 6s/7；CI 只做 14.0 编译 + 新模拟器测试 |
| Shard 的 planner 自行拆任务、交叉引用 | 合并冲突 | 每 phase 单独跑；先 `shard plan` 审 ownership |
| Swift 6 严格并发 + UIKit | 大量隔离告警 | app target 用 Swift 5 模式 |
| `.apkg` 导入内存峰值 | 大包 OOM | 导入走后台 + 进度回调；v1 限制 500MB |
| iOS 14 WebKit 不支持 `:has()` / `aspect-ratio` | 少数牌组样式崩 | 接受；文档说明 |
| 大 collection（10 万卡）列表 | 卡顿 | 浏览分页（每页 200）+ 搜索在 Rust 侧 |
| 字段/模板结构变更触发 full sync | 大库上突然全量同步 | 保存前提示，见 Phase 4 文档 |
| 牌组选项数值越界被静默重置 | 用户输入被悄悄改掉 | 控件夹在引擎值域内 |
| FSRS 优化无法中断 | 大库上像卡死 | 进度遮罩 + 诚实的"放弃等待"文案 |
| 删字段/删笔记/删预设不可撤销 | 数据丢失 | 破坏性操作必须二次确认并说明后果 |

## 8. 排期

| 阶段 | 串行 | 2 个 agent 并行 |
|---|---|---|
| Phase 0 | 1 周 | 1 周 |
| Phase 1 + 1.5 | 2 周 | 1.5 周 |
| Phase 2 + 2.5 | 2.5 周 | 2 周 |
| Phase 3 | 2 周 | 1.5 周 |
| Phase 4 | P0 已落地（P1 顺延） | — |
| Phase 5 | 1 周 | 1 周 |
| **合计** | **~14.5 周** | **~11 周（含 buffer 12 周）** |

并行收益没有想象中大：Xcode 编译是瓶颈，而且每个 phase 都要串行集成。
Phase 4 是三个相对独立的屏幕，是继 Phase 2 之后第二个真正的加速点。

## 9. 与最初计划的偏离（as-built）

记录下来，避免后人按旧表找文件：

| 最初计划 | 实际 |
|---|---|
| target 叫 `LiteProto` / `LiteKit` / `LiteBackend` / `LiteBridge` / `LiteSync` / `LiteCardWeb` / `LiteApp` | 直接沿用上游名字：`AnkiProto` / `AnkiKit` / `AnkiBackend` / `AnkiProtoBridge` / `AnkiSync` / `AmgiCardWeb`，app 叫 `AmgiLite` |
| 验收脚本 `scripts/lite-verify.sh` | `scripts/verify.sh` |
| 引擎 target 用 glob 指向 `../Sources/...` | 副本在 `Engine/`，`Project.swift` 里不存在任何 `../` 路径 |
| "对既有代码的唯一改动：`Mutex` → `NSLock`，主 App 同受影响" | 主仓未改；补丁只在 `Engine/` 副本里（共 4 处，见 §2.2） |
| `CardAssetScheme` 的 media/assets/card 三 host | 实际 `media` + `assets`（MathJax）两个 host；`card` 只作 base URL（返回 204） |
| Phase 1 之后 Docs 里写"计划在 `Documentation/`" | 计划与文档全部收进 `AmgiLite/`（本文件、Phase 4 文档、AGENTS、README） |
| Phase 4 = 交付 | Phase 4 = 功能（本文件 §5.2），交付顺延为 Phase 5 |
| Phase 4 的 P1 与本轮一起做 | 先交付 P0；P1 无 UI 入口，引擎能力已由测试覆盖 |

## 10. 文档索引

| 文件 | 内容 |
|---|---|
| `AGENTS.md` | agent 硬规则、目录职责、shard 约定、已知坑 |
| `AMGI_LITE_IOS14_PLAN.md` | 本文件：定位、依赖策略、iOS 14 选型、阶段、排期 |
| `AMGI_LITE_PHASE4_PLAN.md` | 当前阶段实施细节：引擎语义、契约、UI、测试、风险 |
| `README.md` | 对外说明：功能、构建、真机、依赖、已知限制 |
| `Engine/AGENTS.md` / `Engine/README.md` | 引擎副本的差异与同步流程 |
| `Sources/AGENTS.md` | 应用层分层与屏幕约定 |
| `Tests/AGENTS.md` | 测试规则 |
