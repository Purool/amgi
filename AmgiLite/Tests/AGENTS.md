# Tests

```bash
cd AmgiLite
./scripts/verify.sh --test
```

测试跟着 `verify.sh` 走，不要单独跑 `xcodebuild test` 换成别的 destination：
脚本固定了 `ARCHS=arm64` 和 `IPHONEOS_DEPLOYMENT_TARGET=14.0`，这两条是这个
target 能编过的前提。

## 现有内容

- `AmgiLiteTests/EngineSmokeTests.swift` —— Phase 0 的门禁。它只做一件事：
  构造 `AnkiBackend`、在临时目录里建一个 collection、校验 media 路径、关闭。
  它证明的是「Rust dylib 在 iOS 14 部署目标下能加载、SQLite 能落盘」，
  不是业务正确性。**不要删它**，也不要用 mock 替掉。

## 规则

1. **用真引擎，不 mock。** 引擎本身就是被测对象；mock 掉之后这个测试就没有意义了。
   每个用例在 `FileManager.default.temporaryDirectory` 下建独立目录，结束删除。
2. **不联网。** 同步相关的用例要用本地假服务端或纯解码路径，不要在 CI 里打
   AnkiWeb。
3. **每个用例自清理。** 共用临时根目录会让并行执行互相污染。
4. **断言行为，不断言文案。** 不要断言 `String` 的本地化输出；需要时断言状态或
   错误类型（`LiteError`）。
5. **不写 UI 快照测试。** 布局靠人看；UIColor/字体断言在 Lite 里没有自动化版本。
   真要加 UI 测试，单开一个 `.uiTests` target，别塞进 `AmgiLiteTests`。

## 该测什么

| 层 | 测点 |
|---|---|
| 服务实现（Phase 1 S1） | `Contracts` 每个方法的成功路径 + 错误路径；deck tree 展平顺序与 depth；`Rating` 映射；collection 未打开时的 `LiteError.collectionNotOpen` |
| 导入 | 空包、缺 media、损坏 zip 的错误分支 |
| ViewModel（Phase 2） | 状态机迁移（loading → content / empty / error），不碰 UIKit |
| 引擎冒烟 | 打开/关闭 collection；渲染一张卡返回非空 `frontHTML` |

## 模拟器现实

- Xcode 26 只装了最新系统的 runtime，**没有 iOS 14 模拟器**。测试跑在最新模拟器上，
  但产物是按 14.0 编的——这能覆盖 API 可用性（编译期），覆盖不了 iOS 14 的运行时
  行为（WebKit 内核、SQLite、内存）。真机（iPhone 6s/7）才是那一层。
- 沙箱环境里测试会因为伪终端分配失败报 `Pseudo Terminal Setup Error`，与代码无关；
  在普通终端或 CI 里正常。

## Phase 4 的引擎级用例

- `Phase4ServiceTests.swift` —— 真引擎覆盖 notetype（改名/模板 round-trip、非法模板、
  新增字段 ord）、deck options（context 形状、保存上限与步骤、`limits` 保真、预设
  新建/删除、默认预设拒删、无历史优化返回 0）、notes（新增/编辑 round-trip、字段数
  不足抛错、删除后搜不到）。`TestCollection.swift` 提供每个用例独立临时库。
- 纯逻辑不碰引擎：`DeckOptionsDraftTests`（步骤/权重解析、apply 只改暴露字段、
  权重写回规则、保留率 override、预设名去重）、`TemplateValidationTests`
  （校验 + structural change）、`NoteDraftTests`（字段对齐、标签规整、sfld/csum 不动）。

## 命名

`<被测对象>Tests.swift`，用例名写清前置条件与期望，例如
`testAnswerRejectsWhenCollectionClosed()`。一个文件对应一个被测类型，不要按 Phase
或 shard 编号建文件。
