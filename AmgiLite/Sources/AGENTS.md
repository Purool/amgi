# Sources（应用层）

iOS 14 的 UIKit 应用代码。**没有 SwiftUI，没有 storyboard，没有 xib。**
app target 是 Swift 5 语言模式（`-strict-concurrency=minimal`），引擎 target 是
Swift 6 严格并发——混用是刻意的，不要把 app target 也改成 6。

## 分层

```
Features/ ──► Services/Contracts.swift ──► Services/ 实现 ──► AnkiBackend ──► Rust
    │                  │
    └──────────────────┴──► AnkiKit（公开领域类型）
```

- **屏幕代码（`Features/`）只 import `Contracts` 和 `AnkiKit`。**
  不许 import `AnkiBackend`、`AnkiProtoBridge`、`AnkiProto`——出现即为越层。
- **引擎只允许出现在三个地方**：`Services/` 的服务实现、`App/AppContainer.swift`、
  `App/Composition.swift`。`AppContainer` 是唯一创建 `AnkiBackend` 的地方。
- 所有引擎调用都是同步 FFI，服务把它包成 `async throws`，内部用
  `backendOffload { ... }` 跳出主线程（`AnkiBackend` 的全局锁 + SQLite 调用不能
  压在 main 上）。屏幕侧直接 `try await`，不要在 `viewDidLoad` 里阻塞。
- 服务通过初始化器注入：`Composition` 组装 → `AppContainer` 持有 → 屏幕的
  `init(viewModel:)` 接收。不要单例，不要 `@Dependency`。

## 目录职责

| 目录 | 放什么 | 不放什么 |
|---|---|---|
| `App/` | 生命周期、Tab、Router、Composition、占位/错误页 | 业务逻辑 |
| `DesignSystem/` | 颜色、字体、间距、圆角、通用控件 | 具体屏幕的布局 |
| `Services/` | `Contracts.swift` + 各服务实现 | UIKit import |
| `Support/` | 跨屏接缝：`CardViewHosting`、WKWebView 实现、通用 alert/loading | 屏幕 |
| `Features/<Screen>/` | `XxxViewController` + `XxxViewModel` + `XxxCell` | 别的屏幕的文件 |

新文件放进对应目录即可，`Sources/**` glob 自动纳入，不需要改 `Project.swift`。

## 屏幕约定

- 一个屏幕一个目录：`DecksViewController`（布局、绑定、导航）、
  `DecksViewModel`（`@MainActor final class`，状态机 + 调服务）、
  `DeckCell`（`UICollectionViewListCell` 子类）。
- ViewModel 对外只暴露只读状态和意图方法；变更通过 `onStateChange` 闭包回调，
  由 ViewController 在 `MainActor` 上刷新 diffable snapshot。Combine 可用但非必需。
- 列表一律 `UICollectionView` + `UICollectionViewDiffableDataSource`
  + `UICollectionViewCompositionalLayout.list`（iOS 14）。不要 `UITableView` 新代码，
  也不要 `UICollectionViewFlowLayout` 手算。
- 导航走 `Router.push(_:from:)`；不要 segue，不要从 cell 里直接 `present`。
- 每个异步入口都要有 loading / empty / error 三态；错误用 `LiteError` 映射成
  `UIAlertController`，不要静默吞掉。

## iOS 14 UIKit 基线

| 需求 | 用（最低版本） | 不要用（更高版本） |
|---|---|---|
| 列表 | `UICollectionViewCompositionalLayout.list`(14) + diffable(13) + `CellRegistration`(14) | iOS 16 的 list cell 便捷 API |
| 行内容 | `UIListContentConfiguration` / `UIBackgroundConfiguration`(14) | `UIButton.Configuration`(15) |
| 搜索 | `UISearchController` + `searchResultsUpdater`(8) | — |
| 下拉刷新 | `UIRefreshControl`(6) | — |
| 文件导入 | `UIDocumentPickerViewController(forOpeningContentTypes:)`(14) | — |
| 菜单 | `UIMenu` / `UIAction`(14)、`UIContextMenuInteraction`(13) | `UIEditMenuInteraction`(16) |
| 弹层 | `present(_:animated:)` + 自定义高度 | `UISheetPresentationController`(15) |
| 键盘避让 | 监听 `keyboardWillChangeFrameNotification` | `UIKeyboardLayoutGuide`(15) |
| 触感 | `UIImpactFeedbackGenerator`(10) | — |
| 动态色 | `UIColor(dynamicProvider:)`(13) | — |
| 字体缩放 | `UIFontMetrics`(11)，配合 `adjustsFontForContentSizeCategory` | — |
| 图标 | `UIImage(systemName:)`(13) | — |
| 卡面 | `WKWebView` + `WKURLSchemeHandler`(11) | — |
| 异步 | `async/await`（回部署 13） | — |

新增 API 前先查最低版本；拿不准就用 `-target arm64-apple-ios14.0-simulator` 单独
typecheck 一次。

## 设计系统

- 颜色只用 `AmgiColor.*`，字体只用 `AmgiTypography.*`，间距/圆角只用
  `AmgiSpacing` / `AmgiRadius`。十六进制字面量只允许出现在
  `DesignSystem/AmgiColor.swift`。
- 主仓的 `DesignConformanceTests` 那套 ratchet 在 Lite 里没有自动化版本，
  所以靠人守。深色模式用动态色，不要在 `traitCollectionDidChange` 里手工换色。
- 图标按钮必须给 `accessibilityLabel`；纯装饰的 `UIImageView` 设
  `isAccessibilityElement = false`。

## 表单与编辑器（Phase 4）

- **表单行统一用 `DesignSystem/AmgiFormCells.swift`**：switch / stepper / text /
  menu / disclosure / slider / action / info。不要在屏幕里再拼一套标题+控件的行。
- **宽度敏感的控件放 `contentView`，不要放 custom accessory**：iOS 14 的
  `UICellAccessory.customView` 在窄屏上会把 stepper / 菜单按钮排到 cell 右边界之外，
  `+` 点不到、长标题被截断。`AmgiStepperRowCell` / `AmgiTextRowCell` /
  `AmgiMenuRowCell` 都是内容区横向栈，照这个写。
- **源码编辑器（模板、CSS、权重、字段）关掉智能标点与自动更正**。HTML/CSS 里的引号
  被替换是真事故；字段编辑器顶部要说明「按存储原样保存 HTML」。
- **预览统一用 `Support/CardPreviewViewController`**，调用方先渲染好 `RenderedCard`。
  模板预览必须用 draft CSS 覆盖引擎返回的 `cardCSS`（E4）；新增字段要保存后才可见。
- **笔记编辑器是模态**：有未保存改动时设置 `navigationController?.isModalInPresentation
  = true`，否则下滑手势会绕过 Discard 确认。
- **模板/笔记的 dirty 拦截**复用同一套「Discard / Cancel」alert；不要在 `viewWillDisappear`
  里静默丢弃。

## 卡片渲染

`Support/CardViewHosting` 是 Phase 0 留下的接缝：审查页只依赖这个协议。

- HTML 来自 `ReviewServicing.render(cardID:)`，返回 `frontHTML` / `backHTML` /
  `cardCSS`。
- 资源（音频、图片）走自定义 scheme：路径解析用
  `AmgiCardWeb.CardAssetPath.resolve(url:mediaRoot:bundleRoot:)`，`mediaRoot` 来自
  `CollectionServicing.mediaFolderPath`。
- 现在 `CardPlaceholderView` 只是把 HTML 显示成文本；Phase 1 的 S3 会换成
  `WKWebView`，协议不变。
