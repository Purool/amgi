# AmgiLite

iOS 14 / UIKit 独立版：**卡组 → 复习 → 浏览**，加上 **卡片模板编辑、卡片文字编辑、
牌组选项、FSRS 参数优化**。与主 App（iOS 18 / SwiftUI）不共享源码——引擎是 `Engine/`
下的副本，二进制是 `Frameworks/` 下的 xcframework。

**这个目录是自包含的**：代码、计划、文档、改动都在这里；整体移出仓库后
`./scripts/verify.sh` 仍然成立。上层目录（`../Sources`、`../anki-bridge-rs`、
`../anki-upstream`）**只作只读输入**：

- `../Sources/…` 是 `Engine/…` 副本的同步来源；
- `../anki-bridge-rs` + `../anki-upstream` 只用于重编 `Frameworks/`。

不要修改上层任何文件，也不要把 Lite 的文档写进 `../Documentation`。
计划以本目录的 `AMGI_LITE_IOS14_PLAN.md` + `AMGI_LITE_PHASE4_PLAN.md` 为准。

## 现状

| 阶段 | 内容 | 状态 |
|---|---|---|
| Phase 0 | 14.0 引擎、Tuist 工程、引擎切片、冒烟测试 | 完成 |
| Phase 1 | 服务层、设计系统、`CardWebView`、shell | 完成 |
| Phase 2 | Decks / Review / Browse | 完成 |
| Phase 3 | Onboarding / Settings（AnkiWeb 登录、同步、`.apkg` 导入）/ 收尾 | 完成 |
| Phase 4 | 卡片模板、卡片文字、牌组选项、FSRS 优化 | **已规划，未开工**：`AMGI_LITE_PHASE4_PLAN.md` |
| Phase 5 | 测试补齐、真机回归、AppIcon、TestFlight | 未开始 |

当前代码：`Features/Decks`（diffable 卡组列表 + 计数徽章）、`Features/Review`
（Q/A 切换、四键评分、撤销、结束态）、`Features/Browse`（搜索 + **只读**笔记列表/详情）、
`Features/Settings`（AnkiWeb 登录/同步、`.apkg` 导入、关于）、`Features/Onboarding`
（创建 collection / 导入 / 登录，可跳过）。同步在
`Sources/Services/LiveSyncService.swift`（Keychain 存凭据，`SyncServicing` 为此新增
`fullSync` / `mediaSyncStatus` / `cancel` 等成员）。测试 13 个用例
（引擎冒烟 1 + 服务 7 + 同步 5）。

## 目录

| 路径 | 作用 |
|---|---|
| `Project.swift` | Tuist 清单：1 个 app target + 6 个引擎 target + 1 个测试 target |
| `Tuist.swift` / `Tuist/` | 让本目录成为独立 Tuist root；`Tuist/Package.swift` 是依赖清单 |
| `Info.plist` | scene manifest、竖屏、arm64 |
| `Engine/` | `../Sources` 的副本，见 `Engine/AGENTS.md` |
| `Frameworks/` | `AnkiRustLib.xcframework`，按 iOS 14.0 构建，已提交 |
| `Sources/App/` | AppDelegate / SceneDelegate / AppContainer / Router / Composition |
| `Sources/DesignSystem/` | 颜色 / 字体 / 间距 / 通用控件 / 表单行 |
| `Sources/Services/` | `Contracts.swift`（协议）+ `Live*Service` + `CollectionSession` |
| `Sources/Support/` | `CardWebView`、scheme handler、alert、进度卡、错误文案 |
| `Sources/Features/` | 每个 screen 一个子目录 |
| `Sources/Features/DeckOptions/` | 牌组选项 + 预设 + FSRS 权重（Phase 4 规划，尚未创建） |
| `Sources/Features/Templates/` | 笔记类型列表 + 模板编辑器 + 预览（Phase 4 规划，尚未创建） |
| `Sources/Features/NoteEditor/` | 笔记字段/标签编辑 + 新建笔记（Phase 4 规划，尚未创建） |
| `Tests/AmgiLiteTests/` | 真引擎单测，见 `Tests/AGENTS.md` |
| `scripts/verify.sh` | 唯一验收命令 |
| `scripts/build-engine.sh` | 重编 `Frameworks/`（仅 monorepo 内可执行） |
| `scripts/install-device.sh` | 签名并安装到已连接真机 |
| `AMGI_LITE_IOS14_PLAN.md` | 总计划：定位、依赖策略、iOS 14 选型、阶段、排期 |
| `AMGI_LITE_PHASE4_PLAN.md` | 当前阶段（Phase 4）实施细节 |
| `README.md` | 对外说明 |

## Targets

`Project.swift` 是唯一事实来源；下表只解释角色。引擎 target 沿用上游名字。

| Target | 角色 |
|---|---|
| `AmgiLite` | app（Swift 5 语言模式，`Sources/**` 单 glob） |
| `AnkiKit` | 纯 Swift 领域类型 |
| `AnkiProto` | SwiftProtobuf 生成代码 |
| `AnkiBackend` | C FFI 包装、`Request<R>` 分发、`backendOffload` |
| `AnkiProtoBridge` | protobuf ↔ Swift 镜像边界、`Request<R>` 工厂 |
| `AnkiSync` | Keychain 等同步侧基础件 |
| `AmgiCardWeb` | 卡面 HTML 重写 / 资源路径（不含 WebKit） |
| `AmgiLiteTests` | 单元测试 |

## 构建与验收

```bash
cd AmgiLite
./scripts/verify.sh            # tuist install → generate → build（部署目标 14.0）
./scripts/verify.sh --test     # 再加单元测试
```

`verify.sh` 是"能不能构建"的唯一判据。它固定了 `ARCHS=arm64`（引擎没有 x86_64 切片）
和 `IPHONEOS_DEPLOYMENT_TARGET=14.0`，不要绕开它手搓 `xcodebuild` 后得出"没问题"的结论。
生成产物（`AmgiLite.xcodeproj`、`.xcworkspace`、`Derived/`、`.build/`、`Tuist/.build/`）
全部被 gitignore，`Project.swift` 才是你要编辑的地方。

沙箱环境下的两个已知限制（与代码无关）：

- `tuist install` / `tuist generate` 通过 `sandbox-exec` 编译清单，在文件沙箱内会报
  `sandbox_apply: Operation not permitted`，需在沙箱外执行。
- `xcodebuild test` 启动模拟器需要分配伪终端，沙箱内报 `Pseudo Terminal Setup Error`。

## 硬规则

1. **只改 `AmgiLite/` 内的文件。** 上层目录（`../Sources`、`../Documentation`、
   `../anki-upstream` …）一律只读：不修改、不新增、不删除。计划与文档也只写在本目录。
2. **依赖白名单：SwiftProtobuf + swift-log，仅此而已。** 不要引入
   `swift-dependencies`（1.17 起要求 iOS 15）、`swift-sharing`、`swift-navigation`、
   `swift-case-paths`、`swift-perception`、`hoshidicts`、`EPUBKit`、`ZipArchive`。
   服务层用显式注入，不要用 `@DependencyClient`。
3. **不用 SwiftUI。** `import SwiftUI` 出现在这里就是设计走偏；iOS 14 的 SwiftUI
   也装不下主 App 的那套写法。
4. **引擎只能从 `Sources/Services/`、`Sources/App/AppContainer.swift`、
   `Sources/App/Composition.swift` 里 import。** 屏幕代码只见 `Contracts.swift` 与
   `AnkiKit` 的公开类型。`AppContainer` 是唯一创建 `AnkiBackend` 的地方。
5. **`Engine/` 只读，而且不在这里补能力。** 需要新的引擎 RPC 时先确认——那属于上层改动
   （`../Sources`），按 `Engine/AGENTS.md` 同步回来。本目录只消费现有工厂。
6. **`Frameworks/` 是产物。** 不要手改 plist 或二进制；要重编跑 `scripts/build-engine.sh`。
7. **新增文件放进 `Sources/` 的对应目录即可**，`Sources/**` glob 会自动纳入，
   不需要改 `Project.swift`。只有新增 target 才改清单。
8. **引擎 target 的 `SWIFT_VERSION` 保持 6.0**，app target 保持 5.0。混用是合法的，
   反过来会把 `public import` / `package import` 的副本源码打挂。
9. **引擎调用一律走 `backendOffload`**，主线程上不做阻塞 FFI（`Live*Service` 已经这样写）。
10. **写用户数据的操作必须可确认。** 删字段、删模板、删笔记、删预设、启用 FSRS 都要
    二次确认并说明后果（丢内容 / 影响多少卡片 / 触发 full sync）。不做静默写入。
11. **不要把"不可取消"伪装成可取消。** FSRS 优化没有中断 RPC，取消只能"放弃等待"；
    进度卡与按钮文案要说实话。
12. **UI 只用 DesignSystem 的 token 与行控件。** 颜色/字体/间距不许就地写死；
    Phase 4 起表单行统一用 `Amgi*RowCell`，不要每个屏自己拼一套。

## Shard 分工约定

- 一个 app target + `Sources/**` 单 glob，是多个 agent 并行不改清单的前提。
- `Sources/App/Composition.swift` 是**唯一接线点**：功能 shard 只写自己的目录，
  接线由每个 Phase 末尾的集成 shard 单独修改这一个文件。
- `Sources/Services/Contracts.swift` 是契约，只增不改；实现方按协议补全。
- 每个 shard 的验收都是 `./scripts/verify.sh`（必要时加 `--test`），各自在自己的
  worktree 里跑，互不依赖。
- `Frameworks/` 已提交，所以每个 worktree 不需要重编 Rust。
- 并行上限 **2 个 agent**（Xcode 链接很吃内存，更多会 swap）。

## 已知坑

- **没有 iOS 14 模拟器 runtime。** Xcode 26 只带新系统；`verify.sh --test` 跑在最新
  模拟器上，但**部署目标仍是 14.0**，真机验证只能靠 iPhone 6s/7。
- **引擎只有 arm64 切片**，`xcodebuild` 的 `generic/platform=iOS Simulator` 默认会
  连带编 x86_64，所以脚本里钉了 `ARCHS=arm64`。
- **`MemberImportVisibility` 在 Lite 引擎 target 里是关掉的**：副本大量依赖
  Foundation 成员却没有逐文件 import，打开它就要改几十个文件、同步就失去意义。
- **`AnkiBackend` 是 `@unchecked Sendable`**，内部靠 `NSLock` 保护路径状态。
  不要拆掉锁，也不要把 `@unchecked` 当装饰品删掉。
- **app 没有 AppIcon**（`ASSETCATALOG_COMPILER_APPICON_NAME` 为空），Phase 5 再补。
- **改字段/模板的结构强制 full sync**：字段或模板增、删、重排会
  `set_schema_modified()`。保存前提示，别让用户在 10 万卡的库上"顺手改一下"。
- **牌组选项的值域越界会被静默重置**（不是报错）：每日上限 0–9999、最大间隔
  1–36500、期望保留率 0.70–0.99 等。控件要在范围内夹取。
- **`limits` 必须原样回传**：`updateDeckConfigs` 传空会清掉卡组级每日上限。
- **模板预览用的是已保存的 notetype**：CSS 由客户端替换；新增字段要保存后才预览得到。
- **笔记字段数必须等于 notetype 字段数**：少一个 `updateNote` 就报错。
- **全空笔记能存进去但不生成卡**：保存前必须校验首字段非空。
- **筛选卡组没有牌组选项**（`deck.normal()` 会报错），入口处按 `DeckRow.isFiltered` 拦掉。
- **沙箱里的编译限制**见上文「构建与验收」。

## 文档索引

| 文件 | 内容 |
|---|---|
| `AMGI_LITE_IOS14_PLAN.md` | 总计划与排期 |
| `AMGI_LITE_PHASE4_PLAN.md` | 当前阶段实施细节（契约、UI、测试、风险） |
| `README.md` | 对外说明 |
| `Engine/AGENTS.md` / `Engine/README.md` | 引擎副本的差异与同步流程 |
| `Sources/AGENTS.md` | 应用层分层、屏幕约定、iOS 14 基线 |
| `Tests/AGENTS.md` | 测试规则 |
