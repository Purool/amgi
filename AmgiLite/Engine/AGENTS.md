# Engine（引擎副本）

`Sources/` 里 6 个引擎模块的**副本**，存在的唯一理由是：`AmgiLite/` 要能整体移出
仓库。它们是编译输入，不是开发区——新增能力回主仓改，不要在这里加文件。

## 模块与依赖

| 目录 | 上游 | 依赖 |
|---|---|---|
| `AnkiKit/` | `Sources/AnkiKit` | 无（纯 Swift） |
| `AnkiProto/` | `Sources/AnkiProto` | SwiftProtobuf |
| `AnkiBackend/` | `Sources/AnkiBackend` | `AnkiProto`、`AnkiRustLib`（`Frameworks/`） |
| `AnkiProtoBridge/` | `Sources/AnkiProtoBridge` | `AnkiKit`、`AnkiBackend`、`AnkiProto`、SwiftProtobuf |
| `AnkiSync/` | `Sources/AnkiSync` | `AnkiKit`（Darwin / Security） |
| `AmgiCardWeb/` | `Sources/AmgiCardWeb` | 仅 Foundation |

注意 `AmgiCardWeb` 名字里有 Web，但**不含 WebKit**：它是卡面 HTML 重写、资源路径
解析和原生文本降级。真正的 `WKWebView` 在 `../Sources/Support/`。

## 与上游的差异（共 5 处）

1. **`AnkiBackend/AnkiBackendDependency.swift` 被删除。** 该文件只负责
   `@DependencyClient` 注入，而 `swift-dependencies` 从 1.17 起要求 iOS 15。
   Lite 的服务层用显式构造注入（`AppContainer` 创建 `AnkiBackend` 并传给服务）。
2. **`AnkiBackend/AnkiBackend.swift` 顶部改用 `NSLock`。**
   `Synchronization.Mutex` 是 iOS 18。路径状态改由 `stateLock` + `withStateLock`
   保护，类因此标记为 `@unchecked Sendable`——编译器看不到锁，这是刻意的。
3. **`AmgiCardWeb/NativeCardContent.swift` 被删除。** 它基于
   `AttributedString`（iOS 15）。Lite 不提供“原生渲染”分支，卡面统一走 WebView。
4. **`AmgiCardWeb/CardAssetPath.swift` 里 `url.path(percentEncoded: true)` 改成
   `url.path`。** 前者是 iOS 16。
5. **Lite 引擎 target 不启用 `MemberImportVisibility`**（见
   `../Tuist/ProjectDescriptionHelpers/LiteModule.swift`）。副本里大量文件使用
   Foundation 成员但没有逐文件 `import Foundation`，开启它就要改几十个文件，
   同步也就失去意义。这是诊断级开关，无语义影响。

任何一处改动都要在 `Engine/README.md` 的说明里同步更新，否则下一次 rsync 会静默
覆盖，而 `verify.sh` 会以 `Synchronization` / `path(percentEncoded:)` /
`AttributedString` 的编译错误把问题顶出来。

## 为什么没有 AnkiServices / AnkiClients

- `AnkiServices` 整层依赖 `@DependencyClient`，被上面的 iOS 15 限制挡在门外。
  Lite 的服务实现在 `../Sources/Services/`，协议是 `Contracts.swift`。
- `AnkiClients` 会把 `Reader` / `ReaderEPUB` 拖进来，进而拉上 `hoshidicts`
  （iOS 18）和 `ZipArchive`（iOS 15.5）。基础版不需要，整条链都不引入。

## `-package-name AnkiBridge`

引擎 target 统一用 `-package-name AnkiBridge`，因为副本里存在跨模块的 `package`
声明（`AnkiProtoBridge` → `AnkiBackend`、`AnkiKit`）。**新增引擎侧 target 必须用
同一个 package name**，否则这些声明直接不可见。

app target 不在这个 package 内，只能用 `public` API。好消息是 `Request<R>` 的工厂
方法都是 `public`，所以服务实现可以放在 app target 里调用
`backend.invoke(Request.xxx(...))`——已实测（Swift 5 模式 + typed throws 都成立）。

## 同步上游

在 `AmgiLite/` 目录下执行；`rsync --delete` 会清掉副本里多余的文件：

```bash
rsync -a --delete ../Sources/AnkiKit/        Engine/AnkiKit/
rsync -a --delete ../Sources/AnkiProto/      Engine/AnkiProto/
rsync -a --delete ../Sources/AnkiProtoBridge/ Engine/AnkiProtoBridge/
rsync -a --delete ../Sources/AnkiSync/       Engine/AnkiSync/

rsync -a --delete ../Sources/AnkiBackend/    Engine/AnkiBackend/
rm Engine/AnkiBackend/AnkiBackendDependency.swift

rsync -a --delete ../Sources/AmgiCardWeb/    Engine/AmgiCardWeb/
rm Engine/AmgiCardWeb/NativeCardContent.swift
```

然后重打两处补丁（`NSLock` 块、`url.path`），再跑 `./scripts/verify.sh`。
漏掉补丁的典型报错：`cannot find 'Mutex' in scope`、
`'path(percentEncoded:)' is only available in iOS 16.0 or newer`、
`'AttributedString' is only available in iOS 15.0 or newer`。

## 二进制

`../Frameworks/AnkiRustLib.xcframework` 由 `../scripts/build-engine.sh` 生成
（`IPHONEOS_DEPLOYMENT_TARGET=14.0`，device + simulator，无 watchOS 切片）。
它是**产物**：不要改 plist、不要手动塞切片。重编需要 monorepo 里的
`anki-bridge-rs/` 和 `anki-upstream/`，移出仓库后只能消费，不能重建。
