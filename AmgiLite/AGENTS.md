# AmgiLite

iOS 14 / UIKit 基础版：**卡组 → 卡片浏览 → 到期复习**，其余都不做。
与主 App（iOS 18 / SwiftUI）不共享源码——引擎是 `Engine/` 下的副本，二进制是
`Frameworks/` 下的 xcframework。整个目录可以整体移出仓库，移走后
`./scripts/verify.sh` 仍然成立。

阶段划分与 Shard 分工见 `Documentation/AMGI_LITE_IOS14_PLAN.md`。
现状：Phase 1 完成——服务层（Collections/Decks/Review/Browse/Import）、设计系统、
卡面 WebView 已就绪；Decks/Browse 仍是占位页，由 Phase 2 填充。

## 目录

| 路径 | 作用 |
|---|---|
| `Project.swift` | Tuist 清单：1 个 app target + 6 个引擎 target + 1 个测试 target |
| `Tuist.swift` / `Tuist/` | 让本目录成为独立 Tuist root；`Tuist/Package.swift` 是依赖清单 |
| `Info.plist` | scene manifest、竖屏、arm64 |
| `Engine/` | 主仓 `Sources/` 的副本，见 `Engine/AGENTS.md` |
| `Frameworks/` | `AnkiRustLib.xcframework`，按 iOS 14.0 构建，已提交 |
| `Sources/App/` | AppDelegate / SceneDelegate / AppContainer / Router / Composition |
| `Sources/DesignSystem/` | `AmgiColor` / `AmgiTypography` / `AmgiSpacing`（纯 UIKit） |
| `Sources/Services/` | `Contracts.swift`（协议）+ `Live*Service` 实现 + `CollectionSession` |
| `Sources/Support/` | `CardViewHosting` 等跨屏接缝 |
| `Sources/Features/` | 每个 screen 一个子目录，由 Phase 2 的 shard 填充 |
| `Tests/AmgiLiteTests/` | 引擎冒烟测试，见 `Tests/AGENTS.md` |
| `scripts/verify.sh` | 唯一验收命令 |
| `scripts/build-engine.sh` | 重编 `Frameworks/`（仅限在 monorepo 内执行） |

## Targets

`Project.swift` 是唯一事实来源；下表只解释角色。

| Target | 角色 |
|---|---|
| `AmgiLite` | app（Swift 5 语言模式，`Sources/**` 单 glob） |
| `AnkiKit` | 纯 Swift 领域类型 |
| `AnkiProto` | SwiftProtobuf 生成代码 |
| `AnkiBackend` | C FFI 包装、`Request<R>` 分发、`backendOffload` |
| `AnkiProtoBridge` | protobuf ↔ Swift 镜像边界，`Request<R>` 工厂 |
| `AnkiSync` | Keychain 等同步侧基础件 |
| `AmgiCardWeb` | 卡面 HTML 重写 / 资源路径（不含 WebKit） |
| `AmgiLiteTests` | 单元测试 |

## 构建与验收

```bash
cd AmgiLite
./scripts/verify.sh            # tuist install → generate → build（部署目标 14.0）
./scripts/verify.sh --test     # 再加单元测试
```

`verify.sh` 是"能不能构建"的唯一判据。它固定了 `ARCHS=arm64`
（引擎没有 x86_64 切片）和 `IPHONEOS_DEPLOYMENT_TARGET=14.0`，不要绕开它手搓
`xcodebuild` 后得出"没问题"的结论。生成产物（`AmgiLite.xcodeproj`、
`.xcworkspace`、`Derived/`、`.build/`、`Tuist/.build/`）全部被 gitignore，
`Project.swift` 才是你要编辑的地方。

沙箱环境下有两个已知限制，与代码无关：

- `tuist install` / `tuist generate` 通过 `sandbox-exec` 编译清单，在文件沙箱内
  会报 `sandbox_apply: Operation not permitted`，需在沙箱外执行。
- `xcodebuild test` 启动模拟器需要分配伪终端，沙箱内报 `Pseudo Terminal Setup Error`。

## 硬规则

1. **只改 `AmgiLite/` 内的文件。** 任何 `../Sources/...`、`../AmgiFeatures/...`
   的路径都不许出现在 `Project.swift` 里。要改引擎行为，回主仓改 `Sources/`，
   再按 `Engine/AGENTS.md` 同步。
2. **依赖白名单：SwiftProtobuf + swift-log，仅此而已。** 不要引入
   `swift-dependencies`（1.17 起要求 iOS 15）、`swift-sharing`、`swift-navigation`、
   `swift-case-paths`、`swift-perception`、`hoshidicts`、`EPUBKit`、`ZipArchive`。
   服务层用显式注入，不要用 `@DependencyClient`。
3. **不用 SwiftUI。** `import SwiftUI` 出现在这里就是设计走偏；iOS 14 的 SwiftUI
   也装不下主 App 的那套写法。
4. **引擎只能从 `Sources/Services/`、`Sources/App/AppContainer.swift`、
   `Sources/App/Composition.swift` 里 import。** 屏幕代码只见
   `Contracts.swift` 与 `AnkiKit` 的公开类型。`AppContainer` 是唯一创建
   `AnkiBackend` 的地方。
5. **`Engine/` 只读。** 那里的三处改动是移植补丁，不是可编辑区，详见
   `Engine/AGENTS.md`。
6. **`Frameworks/` 是产物。** 不要手改 plist 或二进制；要重编跑
   `scripts/build-engine.sh`。
7. **新增文件放进 `Sources/` 的对应目录即可**，`Sources/**` glob 会自动纳入，
   不需要改 `Project.swift`。只有新增 target 才改清单。
8. **引擎 target 的 `SWIFT_VERSION` 保持 6.0**，app target 保持 5.0。混用是合法的，
   反过来会把 `public import` / `package import` 的副本源码打挂。

## Shard 分工约定

- 一个 app target + `Sources/**` 单 glob，是多个 agent 并行不改清单的前提。
- `Sources/App/Composition.swift` 是**唯一接线点**：功能 shard 只写自己的目录，
  接线由每个 Phase 末尾的集成 shard 单独修改这一个文件。
- `Sources/Services/Contracts.swift` 是契约，只增不改；实现方按协议补全。
- 每个 shard 的验收都是 `./scripts/verify.sh`（必要时加 `--test`），各自在自己的
  worktree 里跑，互不依赖。
- `Frameworks/` 已提交，所以每个 worktree 不需要重编 Rust。

## 已知坑

- **没有 iOS 14 模拟器 runtime。** Xcode 26 只带新系统；`verify.sh --test` 跑在最新
  模拟器上，但**部署目标仍是 14.0**，真机验证只能靠 iPhone 6s/7。
- **引擎只有 arm64 切片**，`xcodebuild` 的 `generic/platform=iOS Simulator` 默认会
  连带编 x86_64，所以脚本里钉了 `ARCHS=arm64`。
- **`MemberImportVisibility` 在 Lite 引擎 target 里是关掉的**：副本大量依赖
  Foundation 成员却没有逐文件 import，打开它就要改几十个文件、同步就失去意义。
- **`AnkiBackend` 是 `@unchecked Sendable`**，内部靠 `NSLock` 保护路径状态。
  不要拆掉锁，也不要把 `@unchecked` 当装饰品删掉。
- **app 没有 AppIcon**（`ASSETCATALOG_COMPILER_APPICON_NAME` 为空），Phase 4 再补。

## 主仓关系

- 计划：`Documentation/AMGI_LITE_IOS14_PLAN.md`
- 引擎同步：`Engine/AGENTS.md`
- 主仓规则：根 `AGENTS.md`、`Sources/AGENTS.md`（副本的源头，仍然适用其接口约定）
