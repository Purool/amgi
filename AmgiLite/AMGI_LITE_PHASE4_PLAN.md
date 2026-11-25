# Amgi Lite Phase 4 —— 卡片模板编辑、卡片文字编辑、牌组选项、FSRS 参数优化

> 状态：**P0 已落地（2026-11）**。基线：Phase 0–3 已落地，
> `cd AmgiLite && ./scripts/verify.sh --test` 是唯一验收命令；本轮在 iPhone 17
> 模拟器上 56/56 通过，部署目标仍是 14.0。P1 项见 §10。
>
> 本文件在 `AmgiLite/` 内，属于自包含目录的一部分。**上层目录只读**：
> `../Sources`、`../anki-bridge-rs`、`../anki-upstream` 只作为输入，不要修改，
> 也不要把本文档的内容写进 `../Documentation`。
>
> 上游/邻居文档：`AMGI_LITE_IOS14_PLAN.md`（总计划）、`AGENTS.md`（规则）、
> `Engine/AGENTS.md`（引擎副本同步）、`Sources/AGENTS.md`（应用层约定）。

## 0. 结论先行

1. **引擎零改动。** 本轮需要的 13 个 RPC（外加只有 P1 才用的 `removeNotetype`），
   在 `Engine/AnkiProtoBridge` 里都已有 `public` 工厂（`AnkiKit` / `AnkiProtoBridge`
   与主仓逐字节一致）。不需要重编 `Frameworks/AnkiRustLib.xcframework`，不需要动
   `Engine/`，也不需要改上层目录。
2. 工作量集中在 **UIKit 表单基础设施**（iOS 14 没有 `Form`、`UIButton.Configuration`、
   `UIContentUnavailableConfiguration`）和 **三个新屏幕**：牌组选项、模板编辑器、笔记编辑器。
   服务实现是薄封装，约 370 行。
3. 建议 **1 轮 Phase / 2 个 agent 并行 / 约 4 周**（单人串行约 6 周 / 29 人日）。
4. 四个语义陷阱必须在实现时就处理掉，否则是数据问题不是 UI 问题：
   - 字段/模板的**增、删、重排** → 引擎 `set_schema_modified()` → 下次同步**强制 full sync**；
   - `render_uncommitted_card` 用的是**库里已保存**的 notetype，CSS 预览要客户端替换，
     新增字段的预览必须保存后才对；
   - 笔记字段数**必须精确等于** notetype 字段数，否则 `updateNote` 直接报错；
   - 牌组选项的 `limits` 必须原样回传，传空会清掉卡组级每日上限。

## 1. 范围

### 1.0 先把词钉死

| 计划里的词 | 本方案落成的 Anki 概念 |
|---|---|
| 卡片/模板编辑 | 两块：**卡片模板**（笔记类型：字段列表、模板、样式、预览）与 **卡片文字**（笔记字段值 + 标签） |
| 牌组选项编辑 | 每个**预设（deck preset / `DeckConfig`）** 的学习选项，以及「切换/新建/删除预设」 |
| FSRS 参数优化 | `computeFsrsParams`（单预设）+ `updateDeckConfigs(mode: .computeAllParams)`（全部预设） |

### 1.1 卡片模板（笔记类型）

**做**

- 笔记类型列表：`getNotetypeNames`；点进去是模板编辑器。
- 模板编辑：多模板切换、模板重命名、正面 / 背面 / 样式（CSS）三段源码编辑。
- 字段：编辑器里可插入 `{{Field}}`、`{{FrontSide}}`；字段列表只读展示（P1 增删改排序）。
- 预览：正面/背面；优先用「进入时的当前笔记」，否则 `mid:<id>` 搜索第一条，否则空字段。
- 校验：正面必须引用至少一个字段；引用的字段必须存在；cloze 类型必须含 `{{cloze:…}}`。
  客户端预检 + 引擎 `check_templates` 错误兜底（两边都要，文案不同）。
- 保存：`updateNotetype`；保存成功后**重新拉取**再重置 baseline（引擎不回填 ord）。
- 未保存更改拦截；字段/模板结构变化时的 full-sync 提示条。

**不做（本轮）**

- 新建 / 复制 / 删除笔记类型 —— 缺 `AddNotetype` 工厂，见 §2.3。
- 图像遮挡编辑器、`ChangeNotetype`、恢复原生模板（`RestoreNotetypeToStock`）。
- 模板渲染引擎覆盖（主仓的 R2 特性）。

### 1.2 卡片文字（笔记编辑器）

**做**

- 编辑已有笔记：按 notetype 字段名展示每个字段，编辑字段值；编辑标签。
- 保存：`updateNote`；保存成功即回到详情页并刷新。
- 预览：用**未保存的字段值**渲染首张模板的正面/背面（`renderUncommittedCard` 接受字段数组）。
- 删除笔记：`removeNote`，确认框里带上「会删掉 N 张卡片」（`cardIDsOfNote` 取数量）。
- 未保存更改拦截；错误 alert 用 `ErrorMessages`。
- 新建笔记（**P1**，2 天）：选 notetype、选 deck、填字段与标签，`newNote` + `addNote`。

**字段编辑的形态（技术选型）**

- 字段按**存储原样**编辑（就是 `flds` 里那段 HTML 文本），不做所见即所得。
  理由：`NSAttributedString` 的 HTML 导入/回写既慢又丢结构（主仓的
  `RichNoteFieldEditor` 也明确放弃了这条路）。所见即所得是另一个项目。
- 每个字段一个 `UITextView`（自动增高，超过约半屏后内部滚动），
  头顶是字段名，键盘上方是插入栏：`<b></b>` `<i></i>` `<u></u>` `<br>` `{{c1::…}}`。
- 标签：一个文本框，空格分隔；保存前按引擎规则规整（去首尾空白、去空项）。
- 编辑区顶部一条说明：「字段以 HTML 源码保存；保存后按 Anki 的规则渲染」。
  避免用户以为 `<b>` 是可见文字。

**不做（本轮）**

- 富文本/所见即所得、媒体插入（桥接没有 `storeMediaFile`）、批量编辑、
  查找替换（`findAndReplace` 工厂有，但不在本轮）、`ChangeNotetype`。
- 加图片/录音：需要媒体上传 RPC，属于另一轮。

### 1.3 牌组选项

**做**

- 入口：卡组列表长按上下文菜单；复习屏右上「…」菜单（P1）。
- 预设：当前预设（含被几个卡组使用的计数）、切换、新建、重命名、删除、应用到子卡组。
- 每日上限、新卡（学习步骤/毕业间隔/插入顺序/聚集顺序/排序）、遗忘（重学步骤/leech）、
  埋藏（新卡/复习/跨天学习）、顺序（复习顺序/混合）、高级（最大间隔/间隔倍数/难度倍数）。
- FSRS 段：启用开关（**集合级**，需二次确认）、期望保留率、历史保留率、权重（披露到子屏）、
  参数搜索、健康检查开关、优化全部预设、上次优化距今天数。
- 保存：`updateDeckConfigs`，`normal` 或 `applyToChildren`；未暴露字段原样回写。

**不做（本轮）**

- 计时器、自动前进、音频、Easy Days（P1）、自定义调度 `cardStateCustomizer`（只透传）。
- 卡组级每日上限覆盖（`limits` 只**原样回传**，不编辑）、`fsrsReschedule`。

### 1.4 FSRS 参数优化

**做**

- 单预设「Optimize Weights」：`computeFsrsParams`，阻塞进度 + 放弃等待；
  按 `trainingItemCount == 0` 判「历史不足」，按 `healthCheck == .failed` 给警告，
  成功则把权重填回权重文本（**不自动保存**，用户点 Save 才落库）。
- 「Optimize All Presets」：`updateDeckConfigs(mode: .computeAllParams, fsrs: true)`，完成后重载上下文。
- 权重文本编辑 + 解析校验（只校验「能解析成浮点数组」，长度交给引擎 `FSRS::new` 判）。
- 保存规则：**只在权重被改过或刚优化过时**写 `fsrsParams6`；否则 `fsrsParams4/5/6` 原样保留。
  FSRS 关闭时也**不清空**权重（避免关一下开关就把优化结果丢了）。

**不做（本轮）**

- FSRS 模拟器（`simulateFsrsReview` / `simulateFsrsWorkload`）、最优保留率扫描
  （`getRetentionWorkload`）、忽略某个日期前的复习（`ignoreRevlogsBefore`）、
  引擎进度百分比（FFI 没有进度回调，只有 spinner + 阶段文案）。

### 1.5 已评估但明确另起

| 候选 | 现状 | 成本 | 结论 |
|---|---|---|---|
| 新建/复制笔记类型 | 缺 `AddNotetype` 工厂 | 0.5 天 + 引擎同步 | 另起（见 §2.3） |
| 新建笔记 | 工厂齐（`newNote` + `addNote`） | 2 天 | 本轮的 P1，建议排进来 |
| 字段管理（增删改排序） | 工厂齐（`updateNotetype` 带字段数组） | 2 天 | 本轮的 P1 |
| FSRS 模拟器 / 最优保留率 | 工厂齐 | 1 周 | 另起 |
| 笔记媒体插入 | 缺 `storeMediaFile` 桥接 | 3 天 + 引擎改动 | 另起 |

## 2. 引擎核查（先证后做）

### 2.1 需要的调用全都已在 `Engine/` 的副本里

| 用途 | `Request` 工厂 | 位置（`Engine/AnkiProtoBridge/`） |
|---|---|---|
| 笔记类型列表 | `.notetypeNames` | `Requests/NotetypeRequests.swift` |
| 读笔记类型 | `.notetype(for:)` | 同上 |
| 存笔记类型 | `.updateNotetype(_:)` | 同上 |
| 删笔记类型（P1） | `.removeNotetype(id:)` | 同上 |
| 未提交模板预览 | `.renderUncommittedCard(notetypeId:template:cardOrd:sampleFields:)` | `Requests/CardRenderingRequests.swift` |
| 牌组选项上下文 | `.deckConfigsForUpdate(deckId:)` | `Requests/DeckConfigRequests.swift` |
| 单个预设 | `.deckConfig(for:)` | 同上 |
| 保存选项 / 预设 / 全部优化 | `.updateDeckConfigs(_:)` | 同上 |
| FSRS 权重优化 | `.computeFsrsParams(_:)` | `Requests/SchedulerRequests.swift` |
| 新建笔记模板 | `.newNote(notetypeId:)` | `Requests/NotesRequests.swift` |
| 新增笔记 | `.addNote(template:deckId:)` | 同上 |
| 保存笔记 | `.updateNote(_:)` | 同上 |
| 删除笔记 | `.removeNote(id:)` | 同上 |
| 笔记的卡片 id（删除确认） | `.cardIDsOfNote(id:)` | 同上 |

核实方式（四个 diff 都应无输出）：

```bash
cd AmgiLite
for f in NotetypeRequests DeckConfigRequests SchedulerRequests NotesRequests; do
  diff "../Sources/AnkiProtoBridge/Requests/$f.swift" "Engine/AnkiProtoBridge/Requests/$f.swift"
done
```

### 2.2 必须遵守的引擎语义（都在 upstream 里核实过）

| # | 语义 | 依据 | 对实现的约束 |
|---|---|---|---|
| E1 | 字段靠 `ord` 判「重命名/删除」；`ord == nil` 的字段按数组位置**追加** | `../anki-upstream/rslib/src/notetype/mod.rs:479`（`prepare_for_update`）、`:530`（`renamed_and_removed_fields`） | 改名字段必须保留原 `ord`；新增字段 `ord = nil` 且追加到末尾；字段/模板的最终 ord 就是数组下标（`../anki-upstream/rslib/src/storage/notetype/mod.rs:166,220`） |
| E2 | 字段或模板**增、删、重排** → `set_schema_modified()` → 下次同步强制 full sync | `../anki-upstream/rslib/src/notetype/mod.rs:164` 的 doc comment | 保存前提示；文档写清「编辑模板结构 = 一次 full sync」 |
| E3 | `update_notetype` 不把新 ord 回填给你 | `../anki-upstream/rslib/src/notetype/mod.rs:151` | 保存后必须重新 `getNotetype`，再重置 dirty baseline |
| E4 | `render_uncommitted_card` 只接受**未提交的 template**；字段与 CSS 取自库里已保存的 notetype | `../anki-upstream/rslib/src/notetype/render.rs:72` | CSS 预览由客户端把 draft CSS 换进 `RenderedCard.cardCSS`；**新增字段**的预览要保存后才正确 |
| E5 | 上下文里的 `fsrs_params_6` 已从 6/5/4 回填 | `../anki-upstream/rslib/src/deckconfig/update.rs:92` | 权重基线优先读 6；不要制造「6 空、5 有值」 |
| E6 | `update_deck_configs`：`configs` 不能为空；`.computeAllParams` 要求 `fsrs == true`，并自动补齐未提供的预设 | `../anki-upstream/rslib/src/deckconfig/update.rs:159`、`:351` | 全部优化必须 `fsrs: true` + 带当前预设 |
| E7 | **`limits` 会无条件覆盖卡组级覆盖值** | `../anki-upstream/rslib/src/deckconfig/update.rs:422` `update_deck_limits`；`../anki-upstream/rslib/src/deckconfig/service.rs:170` `limits: c.limits.unwrap_or_default()` | 保存/切预设/新建/删预设**必须**把 `context.currentDeck?.limits` 原样传回；`currentDeck == nil` 时直接报错，不要发请求 |
| E8 | 预设 id `1` 不能删 | `../anki-upstream/rslib/src/deckconfig/mod.rs:209` | UI 禁用删除；服务层再挡一次 |
| E9 | 值域超界**静默重置为默认值**（不报错） | `../anki-upstream/rslib/src/deckconfig/mod.rs:220` | 控件必须在范围内夹取：new/reviews 0–9999、最大间隔/毕业间隔 1–36500、leech 1–9999、desired 0.70–0.99、historical 0.70–0.97、interval×0.5–2.0、hard×0.5–1.3、easy×1.0–5.0 |
| E10 | 没有中断 RPC（`abortSync`/`abortMediaSync` 只对同步有效） | 桥接里没有 interrupt 工厂 | 优化/保存的「取消」= 放弃等待，按钮文案要诚实 |
| E11 | 零训练样本时 `compute_params` 不报错，返回当前参数 + `fsrs_items = 0` | `../anki-upstream/rslib/src/scheduler/fsrs/params.rs:101` | 「历史不足」用 `trainingItemCount == 0` 判断，别用 `weights.isEmpty` |
| E12 | 预设有重名时引擎不拦 | `../anki-upstream/rslib/src/deckconfig/mod.rs:146` 无唯一性检查 | 客户端做去重（`Name 2`），与主仓行为一致 |
| E13 | 笔记字段数**必须精确等于** notetype 字段数，否则报错 `note has N fields, expected M` | `../anki-upstream/rslib/src/notes/mod.rs:193`（`prepare_for_update` 的 `require!`） | 编辑器必须按 notetype 字段数补齐/截断，并且 notetype 变了要重载 |
| E14 | 引擎自己重算 `sfld` / `csum`（按 notetype 的 sort field） | `../anki-upstream/rslib/src/notes/mod.rs:483` 调用 `prepare_for_update` | 客户端**不要**复刻排序字段/校验和；桥接的 `NoteRecord` 里 `sfld` 只是首字段、`csum` 恒为 0，不可当真 |
| E15 | 全空笔记也能添加成功，只是**生成 0 张卡** | `../anki-upstream/rslib/src/notetype/cardgen.rs:217`（`cards.is_empty()` 返回 `Ok(0)`） | 客户端必须校验「首字段非空」，否则会留下无卡笔记 |
| E16 | 桥接没有 `storeMediaFile` | `Requests/MediaRequests.swift` 只有 check/trash 系列 | 本轮不做媒体插入，编辑区不提供图片/录音按钮 |
| E17 | `addNote` 桥接丢弃新笔记 id（响应解成 `Void`） | `Requests/NotesRequests.swift` `addNote` | 新建后回列表刷新，不承诺「跳到新卡片」 |
| E18 | 标签由引擎 canonify；空标签安全 | `../anki-upstream/rslib/src/notes/mod.rs:483`（`canonify_note_tags`） | 客户端只需 trim + 去空项，不必模拟引擎的排序/大小写规则 |

### 2.3 如果要把「新建/复制笔记类型」也做了（P1）

需要 `AddNotetype`（当前只有 get/update/remove/names），这一步**要改上层目录**，
不在本目录的自包含范围内：

1. `../Sources/AnkiProtoBridge/ServiceCatalog.swift`：`NotetypesMethod.addNotetype = 0`。
2. `../Sources/AnkiProtoBridge/Requests/NotetypeRequests.swift`：
   `Request<NotetypeID>.addNotetype(_ notetype: Notetype)`，解码 `OpChangesWithId`。
3. 按 `Engine/AGENTS.md` 的 rsync 流程同步 `Engine/AnkiProtoBridge/`，重打两处移植补丁，
   跑 `./scripts/verify.sh --test`。

这是**唯一**需要返回上层才能做的改动。做之前先确认：自包含优先，还是功能优先。

### 2.4 开工前 30 分钟 spike（先花小钱排除大风险）

照 `Tests/AmgiLiteTests/EngineSmokeTests.swift` 的建库流程加一个临时用例（spike 完删掉），
用真实 backend 依次调通四组：

```swift
// 1) notetype 组
let names: [NotetypeNameId] = try backend.invoke(.notetypeNames)
let nt: Notetype = try backend.invoke(.notetype(for: names[0].id))
var edited = nt
edited.templates[0].config.aFormat += " "          // 只改内容，不改结构
try backend.invoke(.updateNotetype(edited))
let again: Notetype = try backend.invoke(.notetype(for: nt.id))
XCTAssertEqual(again.templates[0].config.aFormat, edited.templates[0].config.aFormat)

// 2) deckConfig 组
let ctx: DeckConfigsForUpdate = try backend.invoke(.deckConfigsForUpdate(deckId: deckID))
let current = ctx.allConfig.first { $0.config.id == ctx.currentDeck?.configID }!.config
try backend.invoke(.updateDeckConfigs(UpdateDeckConfigsRequest(
    targetDeckID: deckID,
    configs: [current],
    limits: ctx.currentDeck?.limits,          // E7：必须原样回传
    fsrs: ctx.fsrs,
    fsrsHealthCheck: ctx.fsrsHealthCheck
)))

// 3) 笔记组
var template: NewNoteTemplate = try backend.invoke(.newNote(notetypeId: nt.id))
template.fields[0] = "hello"
try backend.invoke(.addNote(template: template, deckId: deckID))
let found: [NoteID] = try backend.invoke(.searchNoteIds(query: "hello"))
let note: NoteRecord = try backend.invoke(.getNote(id: found[0]))
var editedNote = note
editedNote.flds = editedNote.flds.replacingOccurrences(of: "hello", with: "hello 2")
try backend.invoke(.updateNote(editedNote))

// 4) FSRS 组（新库应返回 0 条训练样本而不是崩）
let result: FsrsOptimizeResult = try backend.invoke(.computeFsrsParams(
    FsrsOptimizeRequest(
        search: "",
        currentWeights: FsrsWeights(current.config.fsrsParams6),
        relearningStepsPerDay: 1,
        runHealthCheck: false
    )
))
XCTAssertEqual(result.trainingItemCount, 0)
```

目的：确认 app target（Swift 5 模式）能用这些 `public` 工厂、`BridgeDecodable` 的
`package` 边界不挡路（`LiveDeckService` 已经证明 `.deckTree()` 可行，但 notetype /
deckConfig / notes 这三组没人在 Lite 里跑过）。跑不通就先按 §2.3 的思路评估，
不要带着不确定开工。

## 3. 分层与契约

```
Sources/Features/DeckOptions|Templates|NoteEditor   ← 只 import Contracts + AnkiKit 公开类型
                 │
                 ▼
Sources/Services/Contracts.swift                    ← 只增不改：+3 协议 +1 选项结构
                 │
                 ▼
Sources/Services/Live{DeckOptions,Notetype,NoteEditing}Service.swift
                 │  backendOffload { backend.invoke(.xxx) }
                 ▼
Engine/AnkiProtoBridge.Request.*                    ← 已存在，不改
```

### 3.1 `Contracts.swift`（只增不改）

```swift
/// 一次牌组选项保存要带的选择项。`DeckConfig` 只装预设本身；
/// 这几个是 `updateDeckConfigs` 的请求级开关。
public struct DeckOptionsSaveOptions: Sendable, Equatable {
    public var applyToChildren: Bool
    public var fsrsEnabled: Bool
    public var ignoreReviewLimit: Bool
    public var applyAllParentLimits: Bool
    public var runHealthCheck: Bool

    public init(
        applyToChildren: Bool = false,
        fsrsEnabled: Bool = false,
        ignoreReviewLimit: Bool = false,
        applyAllParentLimits: Bool = false,
        runHealthCheck: Bool = false
    ) { … }
}

public protocol DeckOptionsServicing: Sendable {
    /// 预设列表 + 当前卡组 + 集合级 FSRS 开关；屏幕一次加载全部。
    func context(deckID: DeckID) async throws -> DeckConfigsForUpdate
    /// 当前卡组正在用的预设（context 里找不到时回退 `deckConfig(for:)`）。
    func config(for deckID: DeckID) async throws -> DeckConfig
    func save(deckID: DeckID, config: DeckConfig, options: DeckOptionsSaveOptions) async throws
    /// 切到已有预设（保留 preset.id，引擎按 id 复用而不是新建）。
    func switchPreset(deckID: DeckID, to preset: DeckConfig, applyToChildren: Bool) async throws
    func renamePreset(deckID: DeckID, preset: DeckConfig, to name: String, applyToChildren: Bool) async throws
    /// `base.id` 会被重置为 0；名字由调用方保证唯一。
    func createPreset(deckID: DeckID, from base: DeckConfig, name: String, applyToChildren: Bool) async throws
    /// 删掉 `id` 并把卡组指到 `fallback`。id 0/1 直接抛错。
    func deletePreset(deckID: DeckID, id: DeckConfigID, fallback: DeckConfig, applyToChildren: Bool) async throws
    func optimizeWeights(_ request: FsrsOptimizeRequest) async throws -> FsrsOptimizeResult
    /// `updateDeckConfigs` + `.computeAllParams` + `fsrs: true`。
    func optimizeAllPresets(deckID: DeckID, current: DeckConfig) async throws
}

public protocol NotetypeServicing: Sendable {
    func names() async throws -> [NotetypeNameId]
    func notetype(id: NotetypeID) async throws -> Notetype
    func save(_ notetype: Notetype) async throws
    func remove(id: NotetypeID) async throws
    /// 用未保存的模板 + 已保存的 notetype 渲染。`cardOrd` 决定 ordinal。
    func preview(
        notetypeID: NotetypeID,
        template: Notetype.Template,
        cardOrd: Int,
        sampleFields: [String]
    ) async throws -> RenderedCard
}

public protocol NoteEditingServicing: Sendable {
    /// 空白笔记模板（字段数正确、guid 已生成）。`NewNoteTemplate` 的
    /// `init` 是 package 级，所以只能由服务创建、由屏幕改 `fields` / `tags`。
    func newNoteTemplate(notetypeID: NotetypeID) async throws -> NewNoteTemplate
    func addNote(_ template: NewNoteTemplate, to deckID: DeckID) async throws
    /// 只写字段与标签；排版字段/校验和由引擎重算（E14）。
    func save(_ note: NoteRecord) async throws
    func delete(id: NoteID) async throws
    /// 删除确认里展示「会删掉几张卡」。返回非空即为删除入口可点。
    func cardIDs(of noteID: NoteID) async throws -> [CardID]
}
```

`LiteServices` 增三个字段并按现有 `.live(backend:)` 装配：

```swift
public let deckOptions: any DeckOptionsServicing
public let notetypes: any NotetypeServicing
public let noteEditing: any NoteEditingServicing
```

另外给 `DeckRow` 补一个 `isFiltered: Bool = false`（`LiveDeckService.flatten` 把
`DeckTreeNode.isFiltered` 透出来）。原因：筛选卡组（filtered deck）没有预设，
`get_deck_configs_for_update` 对它直接报错（`deck.normal()?`），菜单要在入口就拦住。
默认值 `false` 保证现有调用点不用改。

### 3.2 服务实现要点

`LiveDeckOptionsService.swift`（新，约 170 行）：

- 每个方法：`requireCollectionOpen(state)` → `try await backendOffload { try backend.invoke(…) }`，
  与 `LiveDeckService` 同构。
- `config(for:)`：先 `deckConfigsForUpdate`，用 `currentDeck.configID` 在 `allConfig` 里找；
  找不到再 `deckConfig(for: currentConfigID)`，再退 `defaults`，都没有就抛
  `BackendError(kind: .invalidInput, …)`。
- `save`：**内部重新拉 context**（不接受调用方传 context，避免脏读），拼
  `UpdateDeckConfigsRequest(targetDeckID:configs:[config]:mode:…:limits: context.currentDeck?.limits,
  cardStateCustomizer: context.cardStateCustomizer, …)`；`currentDeck == nil` → 抛错（E7）。
- `switchPreset` / `renamePreset` / `createPreset` / `deletePreset`：全部走同一个
  `makeUpdateRequest(context:configs:removed:mode:fsrs:)` 私有 helper；`renamePreset`
  就是把名字改掉后按 id 重发（引擎按 id 更新行）。
- `createPreset`：`var new = base; new.id = DeckConfigID(0); new.name = trimmed`，
  名字唯一化交给调用方（Draft 里有 `uniquePresetName`）；空名抛 `invalidInput`。
- `deletePreset`：`id.rawValue == 0 || == 1` 直接抛；`configs: [fallback]`、`removedConfigIds: [id]`。
- `optimizeAllPresets`：`configs: [current]`、`removed: []`、`mode: .computeAllParams`、`fsrs: true`。
- 错误：`BackendError` 原样抛（`ErrorMessages` 已认 `LocalizedError`）；文案映射见 §7。

`LiveNotetypeService.swift`（新，约 90 行）：

- `save`：`.updateNotetype(notetype)`；不吞错误。
- `preview`：`.renderUncommittedCard(...)`，`cardOrd` 夹到 `UInt32`。
- `remove`：`.removeNotetype(id:)`（P1 才用）。

`LiveNoteEditingService.swift`（新，约 110 行）：

- `newNoteTemplate` / `addNote` / `save` / `delete` / `cardIDs`：一对一映射到 §2.1 的工厂。
- `save`：传入前按 notetype 字段数补齐/截断是**调用方（Draft）**的职责；服务只做
  `note.flds` 与 `note.tags` 的透传（E13）。
- `delete`：`.removeNote(id:)`。

### 3.3 纯逻辑（可单测，不进服务）

| 文件 | 内容 |
|---|---|
| `Features/DeckOptions/DeckOptionsDraft.swift` | `DeckOptionsDraft`：以 `(DeckConfig, DeckConfigsForUpdate)` 初始化，暴露可编辑字段；`apply() -> DeckConfig`；`isDirty`；`uniquePresetName(_:)` |
| 同上（同文件或 `+Parsing.swift`） | `parseSteps` / `formatSteps` / `parseFloats` / `formatWeights` / `relearningStepsInDay` / `currentWeights`（从主仓 `AmgiFeatures/.../DeckConfigModel+Parsing.swift` 移植，保留「只有精确往返才用缩写」的注释） |
| `Features/Templates/TemplateValidation.swift` | `templateValidationMessage(for:)`（正则 + `{{cloze:…}}` 规则，从主仓 `TemplatesFeature/TemplateValidation.swift` 移植） |
| `Features/Templates/NotetypeDraft.swift` | 以 `Notetype` 为基线，暴露 templates/fields 编辑；`hasStructuralChange`（字段/模板数量或顺序变化 → full-sync 提示） |
| `Features/NoteEditor/NoteDraft.swift` | 以 `NoteRecord` + `Notetype` 初始化；`fields: [String]`（**长度等于 notetype 字段数**）、`tags: String`；`isDirty`；`validate()`（首字段非空、字段数匹配）；`apply() -> NoteRecord` |

Draft 必须从 context 带出这几个请求级开关，否则第一次保存就会把集合设置写反：

| Draft 字段 | 初值 |
|---|---|
| `fsrsEnabled` | `context.fsrs` |
| `runHealthCheck` | `context.fsrsHealthCheck` |
| `ignoreReviewLimit` | `context.newCardsIgnoreReviewLimit` |
| `applyAllParentLimits` | `context.applyAllParentLimits` |

`NoteDraft.apply()` 只改 `flds` 与 `tags`：**不要**碰 `sfld` / `csum`（E14），
也**不要**自己拼 `" \(tags) "`（E18）。

## 4. UI 方案（iOS 14 / UIKit）

### 4.1 共享表单件（`Sources/DesignSystem/`）

iOS 14 没有 SwiftUI `Form`，也没有 `UIButton.Configuration`。三个新屏幕的每一行都是
「标题 + 次要文字 + 尾部控件」，抽一层小控件包，避免各写一套：

| 类 | 用途 | 关键点 |
|---|---|---|
| `AmgiSwitchRowCell` | 开关行 | `UICollectionViewListCell` 子类；`accessories = [.customView(UISwitch)]`（iOS 14 ✓） |
| `AmgiStepperRowCell` | 数值行 | 尾部 `UIStepper` + 值 label；`range` 由调用方按 E9 给 |
| `AmgiTextRowCell` | 短文本行（步骤、参数搜索、标签） | 尾部 `UITextField`（`clearButtonMode`、`returnKeyType = .done`），`onChange` / `onCommit` 分开 |
| `AmgiMenuRowCell` | 枚举行 | 尾部 `UIButton` + `menu` / `showsMenuAsPrimaryAction`（iOS 14 ✓），或整行 `UIMenu` |
| `AmgiDisclosureRowCell` | 跳转行 | `.outlineDisclosure()` accessory（iOS 14 ✓） |
| `AmgiSliderRowCell` | 百分比行 | 标题 + 右侧值 + 第二行 `UISlider` |
| `AmgiActionRowCell` | 动作行（Optimize weights / Optimize all） | 主题色文字 + 可选 `UIActivityIndicatorView` |
| `AmgiInfoRowCell` | 说明/警告行 | 次要色、多行、`numberOfLines = 0` |
| `AmgiSectionHeaderView` | 分区头/脚注 | `UICollectionLayoutListConfiguration.headerMode = .supplementary` |

配套：

- `AmgiTypography.mono`（新增）：`UIFontMetrics(forTextStyle: .body).scaledFont(for:
  .monospacedSystemFont(ofSize: 15, weight: .regular))` —— 给模板/CSS/权重文本用。
  笔记字段用正文 `AmgiTypography.body`（字段多是自然语言）。
- 键盘避让：监听 `keyboardWillChangeFrameNotification` 调 `contentInset.bottom`
  （`UIKeyboardLayoutGuide` 是 15，不用）；一个 `KeyboardAvoidingListController` 基类或 helper 即可。
- 全部行 `adjustsFontForContentSizeCategory = true`；开关/步进器必须给 `accessibilityLabel`，
  值变化时更新 `accessibilityValue`。
- **不要**用：`UIButton.Configuration`(15)、`UIContentUnavailableConfiguration`(17)、
  `UIEditMenuInteraction`(16)、`UISheetPresentationController`(15)。

### 4.2 牌组选项屏（`Sources/Features/DeckOptions/`）

文件：

```
DeckOptionsViewController.swift     列表 + 保存/取消 + 未保存拦截 + 进度
DeckOptionsViewModel.swift          @MainActor 状态机（loading/content/error/saving）
DeckOptionsDraft.swift              纯模型 + 解析（§3.3）
DeckOptionsRow.swift                行的 enum（含 menu 选项与展示文案）
PresetPickerViewController.swift    切换/新建/重命名/删除
FsrsWeightsViewController.swift     权重全屏编辑 + Optimize + 结果
DeckOptionsCells.swift              只属于本屏的组合（如 preset 行）
```

分区与行（**只列本轮做的**）：

| 段 | 行 | 控件 | 写入（`DeckConfig.Config` 或 `options`） |
|---|---|---|---|
| Preset | Preset | 披露 → `PresetPicker` | `context.allConfig` 里按 `currentDeck.configID` 选 |
| Preset | Apply to subdecks | switch | `options.applyToChildren` |
| Daily limits | New cards/day | stepper 0–9999 | `newPerDay` |
| Daily limits | Maximum reviews/day | stepper 0–9999 | `reviewsPerDay` |
| Daily limits | New cards ignore review limit | switch | `options.ignoreReviewLimit` |
| New cards | Learning steps | text（`1m 10m`） | `learnSteps` |
| New cards | Graduating interval | stepper 1–36500 | `graduatingIntervalGood` |
| New cards | Easy interval | stepper 1–36500 | `graduatingIntervalEasy` |
| New cards | Insertion order | menu（Due / Random） | `newCardInsertOrder` |
| New cards | Gather order | menu（6 个 case） | `newCardGatherPriority` |
| New cards | Sort order | menu（5 个 case） | `newCardSortOrder` |
| Lapses | Relearning steps | text | `relearnSteps` |
| Lapses | Leech threshold | stepper 1–9999 | `leechThreshold` |
| Lapses | Leech action | menu（Suspend / Tag only） | `leechAction` |
| Burying | Bury new / review / interday | 3 × switch | `buryNew` / `buryReviews` / `buryInterdayLearning` |
| Order | Review order | menu（13 个 case） | `reviewOrder` |
| Order | New/review mix | menu | `newMix` |
| Order | Interday learning mix | menu | `interdayLearningMix` |
| Advanced | Maximum interval | stepper 1–36500 | `maximumReviewInterval` |
| Advanced | Interval multiplier | slider 50–200% | `intervalMultiplier` |
| Advanced | Hard interval | stepper 50–130% | `hardMultiplier` |
| Advanced | Easy bonus | stepper 100–500% | `easyMultiplier` |
| FSRS | Enable FSRS | switch + 确认 | `options.fsrsEnabled`（集合级） |
| FSRS | Desired retention | slider 70–99 | `desiredRetention` |
| FSRS | Historical retention | slider 70–97 | `historicalRetention` |
| FSRS | Weights | 披露 → `FsrsWeights` | `fsrsParams6`（见 §1.4 写回规则） |
| FSRS | Parameter search | text（占位 = `preset:"<name>" -is:suspended`） | `paramSearch` |
| FSRS | Health check | switch | `options.runHealthCheck` |
| FSRS | Optimize all presets | action | 服务 `optimizeAllPresets` |
| FSRS | Last optimized | info | `context.daysSinceLastFsrsOptimize` |

**不写回的字段一个字都别碰**：`initialEase`、`lapseMultiplier`、`newPerDayMinimum`、
`easyDaysPercentages`（Easy Days）、`ignoreRevlogsBeforeDate`、`other`，以及全部计时器/
自动前进/音频字段。`DeckOptionsDraft.apply()` 从**原始 `DeckConfig` 拷贝**再改暴露字段 ——
不要 `DeckConfig()` 新建，否则会把 Easy Days 之类静默清空。

交互要点：

- 进入即 `session.ensureOpen()` → 并行拉 `context` + `config` → 填 draft → 快照 baseline。
- 修改即更新 draft；`isDirty` 驱动 Save 可点 + 返回拦截。
- Save：`BlockingProgressView`（已有，注释里就写明「cancel = 停止等待」），成功后 pop。
- 错误：`ErrorMessages.text(for:)` + `Alerts`，不静默吞。
- 三种状态：`LoadingStateView` / `ErrorStateView(retry:)` / 正常列表。
- 「Enable FSRS」二次确认文案：说明它是**集合级**、已有卡片不会自动重排、`fsrsReschedule` 未实现。
- FSRS 关闭时：权重行、Optimize、Optimize All 置灰（与主仓一致）；期望/历史保留率、
  健康检查、参数搜索仍可编辑（保留率在 FSRS 打开后才生效）。

### 4.3 模板编辑器（`Sources/Features/Templates/`）

文件：

```
NotetypeListViewController.swift    笔记类型列表（diffable，按名称 localizedStandardCompare 排序）
TemplateEditorViewController.swift  主编辑器
TemplateEditorViewModel.swift       @MainActor 状态机
NotetypeDraft.swift                 模板/字段草稿 + structural change 判定
TemplateValidation.swift            客户端校验（纯逻辑）
TemplateSourceEditor.swift          UITextView 包装（mono / 关智能标点 / 字段插入栏）
TemplatePreviewViewController.swift 预览（CardWebView + 正/背切换）
NotetypeFieldsViewController.swift  P1：字段增删改排序
```

编辑器结构：

| 区域 | 内容 |
|---|---|
| 导航栏 | 左：Cancel（dirty 时确认丢弃）；右：Save（校验通过才可用）；P1：Fields |
| 模板选择 | 模板数 ≤ 4 用 `UISegmentedControl`，> 4 用 `UIMenu`；当前模板名可改 |
| 面板切换 | 正面 / 背面 / 样式（CSS）三段 |
| 编辑区 | `UITextView`，`AmgiTypography.mono`，`autocorrectionType = .no`、`autocapitalizationType = .none`、`smartQuotesType = .no`、`smartDashesType = .no`（HTML 里引号被替换是真事故） |
| 字段栏 | `inputAccessoryView`：每个 `{{Field}}` + `{{FrontSide}}`，插入到光标处/替换选中 |
| 提示条 | 校验错误（红）/ full-sync 警告（黄） |
| 底部 | Preview 按钮 |

预览（`TemplatePreviewViewController`，模态 + 自己的导航栏）：

1. 采样字段：优先 `previewNoteID`（从笔记详情/复习进入时带进来）→
   `browse.searchNotes("mid:\(notetypeID.rawValue)", limit: 1)` → `browse.note(id:)` →
   按 `\u{1F}` 切 `flds`；都没有就用 `[String](repeating: "", count: fields.count)`。
2. `notetypes.preview(notetypeID:template:cardOrd:sampleFields:)` 拿 `RenderedCard`；
   `cardOrd` 用模板在数组里的下标（`template.ord ?? index`）。
3. **用 draft CSS 覆盖**：`RenderedCard(frontHTML:backHTML:cardCSS: draftCSS)`
   （`RenderedCard.init` 是 public），再交给 `CardPageBuilder.page(for:side:isDark:)`
   → `CardWebView.load(html:baseURL:)`。（E4：引擎只给模板改动，CSS 得自己换。）
4. 正/背切换 + 深色跟随 `traitCollection.userInterfaceStyle`；空字段时提示
   「新增字段的预览需先保存」。

dirty / 保存：

- `Notetype` 是 `Hashable`，直接和 baseline 比；字段/模板**数量或顺序**与 baseline 不同 →
  `hasStructuralChange` → 顶部黄条 + 保存确认 alert（E2）。
- 保存前跑 `templateValidationMessage`；失败就在编辑器里标红，不发请求。
- 保存成功 → 重新 `notetype(id:)` → 重置 baseline 与编辑区（E3）。
- 引擎 `check_templates` 的错误也要弹（客户端规则是子集，引擎才是权威）。

P1 字段管理（`NotetypeFieldsViewController`）：列表 + `reorderingHandlers`（iOS 14 diffable 支持）
+ 新增（`ord: nil` 追加）/重命名（保留 ord）/删除（确认丢数据）；字段选项（字体、字号、
sticky、RTL）放二级屏。删除字段前必须提示：该字段在所有笔记里的内容会被丢弃，且触发 full sync。

### 4.4 笔记编辑器（`Sources/Features/NoteEditor/`）

文件：

```
NoteEditorViewController.swift   字段 + 标签 + 保存/删除/预览
NoteEditorViewModel.swift        @MainActor 状态机
NoteDraft.swift                  纯模型 + 校验（§3.3）
NoteFieldView.swift              单个字段块（field name + 自动增高 UITextView）
NotePreviewViewController.swift  预览（CardWebView + CardPageBuilder，正/背切换）
AddNoteViewController.swift      P1：notetype / deck 选择 + 空笔记
```

交互（编辑已有笔记）：

- 进入方式：笔记详情页「Edit」与列表行的滑/长按菜单，模态 `present` 一个
  `UINavigationController`。编辑是模态任务，与 `LoginViewController` 的呈现方式一致；
  `Router` 只负责 push 式导航，不为模态编辑加 route。
- 载入：`browse.note(id:)` + `notetypes.notetype(id: note.mid)`；按字段名建
  `[NoteFieldView]`；`flds` 按 `\u{1F}` 切分后**补齐/截断到 notetype 字段数**（E13）。
- 编辑：每个字段的 `UITextView` 直接编辑存储文本；插入栏给常用标签（§1.2）。
- 标签：一个文本框（空格分隔），旁边一行说明「空格分隔」。
- 预览：`notetypes.preview` 传**当前未保存的字段值**；模板取 `notetype.templates[0]`，
  `cardOrd = 0`（本轮固定首模板；按当前卡片 ord 预览是 P1）。CSS 不在这一屏改。
- 保存：`noteEditing.save(draft.apply())` → 成功后 pop；详情页在 `viewWillAppear` 重取，
  列表在返回后重跑搜索（不需要额外通知机制）。
- 删除：`cardIDs(of:)` 取数量 → 确认框「Delete note and N cards?」→ `delete(id:)` → pop 到列表并刷新。
- 未保存拦截：和模板编辑器同一套「Discard / Cancel」alert。

新建笔记（P1）：`AddNoteViewController` 在同一套 UI 上加两行：
Notetype（`AmgiMenuRowCell`，`notetypes.names()`）、Deck（`AmgiDisclosureRowCell`，非 filtered 的
`deckTree()` 扁平列表）；`newNoteTemplate(notetypeID:)` 拿空模板 → 填字段 → `addNote(_:to:)`；
校验「首字段非空」（E15）；成功后 dismiss 并刷新浏览列表（不定位到新笔记，E17）。

### 4.5 路由与入口

`Sources/App/Router.swift` 增（笔记编辑器是模态，不需要 route）：

```swift
enum Route: Equatable {
    case review(deckID: DeckID)
    case browseNote(noteID: NoteID)
    case deckOptions(deckID: DeckID, deckName: String)
    case notetypeList
    case templateEditor(notetypeID: NotetypeID, initialTemplate: Int, previewNoteID: NoteID?)
}
```

`Router` 加三个工厂闭包，`Composition.makeMainScreens` 里接线（唯一接线点，规则不变）。

入口：

| 入口 | 位置 | 优先级 |
|---|---|---|
| Deck Options | `DecksViewController` 的 `collectionView(_:contextMenuConfigurationForItemAt:point:)`（iOS 13 ✓；iOS 16 起的批量版不可用，编译会有 deprecation 警告，仓库没开 warnings-as-errors，可接受）；`row.isFiltered` 为 true 时不给这一项 | P0 |
| Note Types | `SettingsViewController` 的 Collection 段新增一行 → `notetypeList` | P0 |
| Edit Note | `NoteDetailViewController` 导航栏「Edit」；Browse 行的上下文菜单「Edit」 | P0 |
| Add Note | `BrowseViewController` 导航栏「+」 | P1 |
| 复习屏菜单 | `ReviewViewController` 右栏加「…」`UIMenu`：Deck Options / Edit This Card's Template | P1 |

复习屏定位 notetype（不需要新引擎接口）：`QueuedReviewCard.card` 有 `nid` + `ord`，
`browse.note(id:)` 给 `NoteRecord.mid` → `.templateEditor(notetypeID: mid,
initialTemplate: Int(ord), previewNoteID: nid)`。

## 5. 里程碑、shard 与排期

沿用现有节奏：每个 Phase 一串 shard，`Composition.swift` 只在集成 shard 改一次；
每个 shard 的验收都是 `./scripts/verify.sh`（必要时 `--test`）。**并行上限 2 个 agent**
（总计划的刻度是「4 个同时 `xcodebuild` 会 swap」，这三块屏更重，按 2 个排）。

| ID | 内容 | 独占文件 | 依赖 | 验收 | 人日 |
|---|---|---|---|---|---|
| **M4.0a** `services` | 三个协议 + 三个 `Live*` + `LiteServices` 字段 + `DeckRow.isFiltered` + 引擎级单测 | `Sources/Services/Contracts.swift`（只增）、`LiteServices.swift`、`LiveDeckOptionsService.swift`、`LiveNotetypeService.swift`、`LiveNoteEditingService.swift`、`LiveDeckService.swift`（透出 `isFiltered`）、`Tests/.../{DeckOptionsServiceTests,NotetypeServiceTests,NoteEditingServiceTests}.swift` | — | `verify.sh --test` 绿 | 4 |
| **M4.0b** `forms` | 表单件 + `AmgiTypography.mono` + 键盘 helper + 调试画廊（`-AmgiLiteFormGallery` 启动参数，与现有 `-AmgiLiteStartAtSettings` 同款） | `Sources/DesignSystem/AmgiFormCells.swift`、`AmgiSectionHeaderView.swift`、`AmgiTypography.swift`（追加）、`Sources/Support/KeyboardAvoiding.swift` | — | `verify.sh` + 深/浅两套截图 | 3 |
| **M4.1** `deck-options` | 牌组选项屏 + 预设 CRUD + FSRS 段 + 权重屏 | `Sources/Features/DeckOptions/**`、`Tests/.../DeckOptionsDraftTests.swift` | M4.0a/b | 构建 + 单测 + 截图 | 6 |
| **M4.2** `templates` | 笔记类型列表 + 模板编辑器 + 预览 + 校验 + 字段插入 | `Sources/Features/Templates/**`、`Tests/.../TemplateValidationTests.swift` | M4.0a/b | 构建 + 单测 + 预览截图 | 6 |
| **M4.3** `note-editor` | 笔记编辑器（字段/标签/删除/预览） | `Sources/Features/NoteEditor/**`、`Tests/.../NoteDraftTests.swift` | M4.0a/b | 构建 + 单测 + 截图 | 3.5（+2 若做 P1 新建笔记） |
| **M4.4** `integration` | 路由 + Composition + Decks 上下文菜单 + Settings 行 + Browse 入口 | `Sources/App/Router.swift`、`Sources/App/Composition.swift`、`Sources/Features/Decks/DecksViewController.swift`、`Sources/Features/Settings/{SettingsViewController,SettingsViewModel}.swift`、`Sources/Features/Browse/{BrowseViewController,NoteDetailViewController}.swift`、`Sources/Features/Review/ReviewViewController.swift`（P1） | M4.1–M4.3 | P0 入口可达 + `verify.sh` | 2.5 |
| **M4.5** `polish` | 错误文案、动态字体/深色/VoiceOver 回归、真机跑一遍、文档 | 全仓小改 + 本目录 `*.md` | M4.4 | 手动清单（§6.3） | 4 |

墙钟：

| 阶段 | 串行 | 2 个 agent 并行 |
|---|---|---|
| M4.0a + M4.0b | 7 天 | 4 天 |
| M4.1 ∥ M4.2 | 12 天 | 6 天 |
| M4.3 | 3.5 天 | 3.5 天 |
| M4.4 | 2.5 天 | 2.5 天 |
| M4.5 | 4 天 | 4 天 |
| **合计** | **~29 人日 / 6 周** | **~20 天 / 4 周（含 buffer 4.5 周）** |

shard 约束（写进 prompt，与现有约定一致）：

1. 只改自己的目录；`Contracts.swift` 只增不改；`Composition.swift` 只有 M4.4 能动。
2. 不 import `AnkiBackend` / `AnkiProtoBridge` / `AnkiProto`（屏幕层）；引擎只在 `Services/` 里出现。
3. 不引入依赖，不用 SwiftUI，不用 iOS 15+ API。
4. 新文件放进 `Sources/` 对应目录即可，**不改 `Project.swift`**。
5. 不改 `Engine/`、不改上层目录；验收只认 `./scripts/verify.sh [--test]`，
   沙箱里跑不了 tuist/xcodebuild 是已知限制，不要手搓 xcodebuild 交差。

## 6. 测试与回归

### 6.1 纯逻辑单测（无引擎、跑得快）

| 用例 | 断言 |
|---|---|
| 步骤解析/格式化 | `"1m 10m 1h 1d"` ↔ `[1,10,60,1440]`；只有精确往返才输出缩写（`formatSteps([0.001])` 回退成 `0.001m`，不会截成 `0s`） |
| 权重解析/格式化 | 逗号/空格/换行都认；`parseFloats(formatWeights(x))` 与 `x` 逐项误差 ≤ 5e-5；二次格式化幂等 |
| `DeckOptionsDraft.apply()` | 改 `newPerDay` 后其余字段逐一 equal 原 config（**尤其是 `easyDaysPercentages`、`other`**） |
| 权重写回规则 | 没改权重 → `fsrsParams6/5/4` 原样；改了 → 只写 6；FSRS 关闭且没改 → 不清空 |
| desired retention override | `context.currentDeck.limits.desiredRetention` 存在时优先显示它 |
| 模板校验 | 无字段引用 / 引用不存在字段 / cloze 缺 `{{cloze:…}}` 各报一条；正常模板返回 nil |
| `hasStructuralChange` | 只改模板文本为 false；加字段/删模板为 true |
| `NoteDraft` 字段对齐 | 字段数少于 notetype → 补 `""`；多于 → 截断；`apply()` 不碰 `sfld` / `csum` |
| `NoteDraft.validate()` | 首字段全空 → 拒绝（E15）；字段数不匹配但已补齐 → 通过 |
| 标签规整 | 多个空格 / 首尾空格 / 重复标签 → 规整成引擎可接受的形式 |

### 6.2 引擎级服务测试（复用 `LiteServicesTests` 的 `Workspace` 模式）

| 用例 | 断言 |
|---|---|
| `testNotetypeNamesOnFreshCollection` | 新库返回 6 个 stock 类型，含 `Basic`；`notetype(Basic)` 有 ≥1 字段 ≥1 模板 |
| `testUpdateTemplateRoundTrip` | 改一个模板的 `qFormat`/`aFormat`/`css` + 模板名 → save → 重新读逐项相等 |
| `testInvalidTemplateRejectedByEngine` | 模板引用不存在字段 → save 抛错（证明客户端校验是子集，错误要能弹出） |
| `testAddFieldAppendsOrdinal` | `fields.append(.init(name: "Extra"))` → save → 重取：`fields.last?.ord == count-1`（E1） |
| `testDeckOptionsContextShape` | 新库：`allConfig` 含 id 1、`currentDeck.configID != 0`、`defaults != nil`、`fsrs == false` |
| `testSaveDailyLimitsAndSteps` | 改 `newPerDay/reviewsPerDay/learnSteps` → save → 重取 context + config 全等 |
| `testDeckLimitsPreserved` | save 后 `context.currentDeck.limits` 不变 —— **防 E7 回归** |
| `testCreateAndDeletePreset` | 新建 → `allConfig` 2 个、卡组指向新 id；带 fallback 删除 → 回到 1 个 |
| `testDeleteDefaultPresetThrows` | id 1 → 抛错（E8） |
| `testOptimizeWithoutHistory` | 新库 `computeFsrsParams` → `trainingItemCount == 0`，不崩（E11） |
| `testAddAndEditNoteRoundTrip` | `newNoteTemplate` + 首字段 → `addNote` → 搜索到 → 改字段 → `save` → 重取，`flds` 一致 |
| `testNoteWithFewerFieldsThrows` | 故意少传一个字段 → `save` 抛错（E13 的引擎侧证据） |
| `testDeleteNoteRemovesCards` | `cardIDs(of:)` 非空 → `delete` → 搜索为空、卡片也没了（E17 的删除路径） |

> `verify.sh --test` 跑在最新模拟器上，部署目标仍是 14.0；引擎测试不需要真机。

### 6.3 手动回归（真机 iPhone 6s/7，iOS 14.x）

1. Note Types 列出 6 个 stock 类型；进 Basic 改正面模板 → 预览 → 保存 → 重进看是否落库。
2. 加一个字段 → 预览提示「需保存」→ 保存 → 预览出现 `{{NewField}}`；同步时看到 full-sync 提示。
3. 改 CSS → 预览立刻变色（draft CSS 生效）→ 保存。
4. 牌组长按 → Deck Options：改每日上限/学习步骤 → 保存 → 回卡组确认选项保持。
5. 新建预设 → 改名 → 切回 Default → 删除新预设；切换后各选项保持（`limits` 保真由 §6.2 单测守）。
6. FSRS 开 → 期望保留率 90 → 优化权重（新库应报「历史不足」）→ 有历史库上真跑一次，
   确认 UI 不冻结、放弃后不落库。
7. 笔记详情 → Edit：改字段 → 预览（未保存就应生效）→ 保存 → 回详情看到新内容；
   改标签 → 保存 → 列表/详情的标签同步。
8. 删除一张笔记：确认框显示卡片数 → 确认 → 列表少一条，复习队列不再出现。
9. 深色模式、最大动态字体、VoiceOver 走一遍三个新屏；键盘弹出不遮输入行。
10. 编辑中锁屏 / 切后台再回来：草稿与 Save 状态不丢；强杀重进不留下半保存状态。

## 7. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| E7：`limits` 传空 → 卡组级覆盖被清 | 用户"每日上限"回退，且难察觉 | 服务层强制从 context 取 `limits`；`currentDeck == nil` 直接抛；加回归测试 §6.2 |
| E2：改字段/模板 → full sync | 用户在大库上突然被要求全量上传/下载 | 保存前黄条 + 确认弹窗；文档写清；不改肉眼不可见的结构就不弹 |
| E9：值域越界被静默重置 | 用户填 0 / 填 99999 后被悄悄改回默认 | 控件按 E9 夹取，越界即时提示，不允许提交越界值 |
| E4：CSS/新字段预览与保存后不一致 | 用户以为改坏了 | 预览用 draft CSS；新增字段明确提示"保存后可见" |
| E10：优化无法真正取消 | 大库上优化几分钟，用户以为卡死 | `BlockingProgressView` + 明确文案（"完成后会丢弃结果"）；优化期间禁用其它入口 |
| 优化 / 启用 FSRS 耗时与 `AnkiBackend` 全局锁 | 期间所有引擎调用排队（切 tab 也慢） | 进度遮罩 + 文案；优化/启用期间禁止离开该屏；文档标注 |
| E13：字段数与 notetype 不一致 | `updateNote` 报错，用户丢改动 | Draft 补齐/截断 + notetype 变更后重载；错误文案映射 |
| E15：全空笔记添加成功但 0 张卡 | 留下无卡笔记，用户以为存上了 | 客户端校验首字段非空；保存按钮置灰 |
| E14：误以为要自己算 `sfld`/`csum` | 排序字段写坏、搜索不到 | 明确只写 `flds`/`tags`；单测断言 |
| 字段是 HTML 源码 | 用户看到 `<br>` 以为坏了 | 编辑区顶部说明 + 预览按钮 + 插入栏 |
| 删除笔记/字段无法撤销 | 数据丢失 | 二次确认 + 显示影响（N 张卡 / 全库该字段内容） |
| 引擎错误文案是英文/偏技术（`templateParse`、`note has 3 fields, expected 4`） | 用户看不懂 | `ErrorMessages` 增加这三类映射；未知错误回退原文 |
| 预设重名引擎不拦（E12） | 两个同名预设，选择器分不清 | 客户端唯一化（`Name 2`），与主仓一致 |
| 筛选卡组（filtered deck）被点进选项页 | `deck.normal()?` 报错 | `DeckRow.isFiltered` 从入口拦；服务层保留友好错误兜底 |
| 大 CSS/模板文本 + WebView 预览 | 编辑卡顿 / 内存峰值 | 预览按需创建，关闭即释放；不在列表 cell 里放 WebView |
| iOS 14 WebKit 缺 `:has()`/`aspect-ratio` | 预览与桌面不完全一致 | 与主 App 同样的已知差异，文档说明，不修 |
| 深色模式里 `cgColor` 只解析一次 | 边框/分隔线不跟随 | 沿用 `AmgiButton` 的 `traitCollectionDidChange` 重解析写法 |
| 模板编辑后没重新拉 notetype（E3） | 第二次保存字段错位 | 保存成功必 `notetype(id:)` 重取并重置 baseline；单测覆盖 |
| 两个 agent 同时 `xcodebuild` | 内存 swap、跑到超时 | `max_concurrent = 2`；串行阶段不要叠 |
| 沙箱内 tuist/xcodebuild 失败 | 误判"代码坏了" | 按 AGENTS：verify.sh 在沙箱外跑；沙箱内只用 `swiftc -target …14.0` 做语法检查 |

## 8. 文档与收尾（M4.5 一起做）

只改 `AmgiLite/` 内的文件：

| 文件 | 改什么 |
|---|---|
| `AMGI_LITE_IOS14_PLAN.md` | §1「做」加入这四块、从「不做」删掉；§5.2 的 Phase 4 表更新为「已落地」；§8 排期换成实际值；§9 偏离表补新条目 |
| `AMGI_LITE_PHASE4_PLAN.md` | 本文件：状态改为「已落地」，补实际耗时与偏离 |
| `AGENTS.md` | 「现状」段更新；目录表加新屏；「已知坑」补 full sync / 值域 / 笔记字段数 / 优化不可中断 |
| `README.md` | 状态段与功能列表更新（当前仍是 Phase 1 的描述） |
| `Sources/AGENTS.md` | 补表单行、字段编辑、预览这三条约定（如与实现有偏差） |
| `Tests/AGENTS.md` | 补「笔记/模板/牌组选项的引擎级用例」一节 |

上层目录不动：`../Documentation/*`、`../CHANGELOG.md` 的 Lite 部分由维护者在合并时处理，
本阶段不写。

## 9. 开工前需要拍板的三件事

1. **P1 边界**：新建笔记（2 天）、字段管理（2 天）、新建/复制笔记类型（1 天 + 引擎改动）
   要不要进本轮？不做的话，用户仍可在桌面/AnkiMobile 里建笔记类型和字段，再同步过来。
2. **字段编辑形态**：接受「按存储原样编辑 HTML + 预览」（本方案），
   还是想要所见即所得（另起一轮，成本 ~1.5 周）？
3. **交付节奏**：一次性发（4 周）还是拆两次——先「牌组选项 + FSRS + 笔记编辑」
   （约 2.5 周，感知强、风险低），再「模板编辑器 + 字段管理」。


## 10. 落地记录（as-built）

`M4.0a–M4.4` 的 P0 范围全部落地，没有改 `Engine/`、`Frameworks/` 或上层目录。

| Shard | 落地内容 |
|---|---|
| M4.0a | `DeckOptionsServicing` / `NotetypeServicing` / `NoteEditingServicing` 三个协议 + `LiveDeckOptionsService` / `LiveNotetypeService` / `LiveNoteEditingService` + `LiteServices` 装配 + `DeckRow.isFiltered`（`LiveDeckService.flatten` 透出） |
| M4.0b | `AmgiFormCells.swift`（switch/stepper/text/menu/disclosure/slider/action/info + section header）、`AmgiTypography.mono`、`KeyboardAvoiding.swift`。**没有做**调试画廊 |
| M4.1 | `Features/DeckOptions/`：`DeckOptionsDraft`（解析 + 权重写回规则）、`DeckOptionsRow`、`DeckOptionsViewModel`、`DeckOptionsViewController`、`PresetPickerViewController`、`FsrsWeightsViewController` |
| M4.2 | `Features/Templates/`：`TemplateValidation`、`NotetypeDraft`、`NotetypeListViewController`、`TemplateEditorViewModel`、`TemplateSourceEditor`、`TemplateEditorViewController`；预览屏抽到 `Support/CardPreviewViewController` 供模板/笔记共用 |
| M4.3 | `Features/NoteEditor/`：`NoteDraft`、`NoteEditorViewModel`、`NoteFieldView`、`NoteEditorViewController`（字段/标签、删除确认带卡片数、未保存预览、`isModalInPresentation` 拦截下滑丢改动） |
| M4.4 | `Router` 三个新 route、`Composition` 接线、Decks 长按「Deck Options」（filtered 不给）、Settings「Note Types」、NoteDetail「Edit」、Browse 上下文菜单「Edit Note」。复习屏菜单仍是 P1 |

### 10.1 与计划不同的地方

| 计划 | 实际 | 原因 |
|---|---|---|
| M4.0b 调试画廊 | 未做 | 用户要求「编译过 + iPhone 17 模拟器验证」；表单件已在三个真实屏幕里跑过 |
| 表单行用 `accessories = [.customView]` | stepper/text/menu 改成 `contentView` 内的横向栈 | iOS 14 的 custom accessory 在窄屏上会超出 cell 右边界（stepper 的 `+` 点不到、菜单标题被截断），复测后改成内容区布局 |
| 模板/笔记预览两个屏 | 共用 `CardPreviewViewController` | 除标题和提示文案外完全一致，避免两份 WebView 生命周期代码 |
| P1：字段管理、新建笔记、新建/复制笔记类型、复习屏菜单 | 未做 | 与总计划的「默认不进本轮」一致；引擎能力已由 §6.2 测试覆盖，下一轮只加 UI |
| 真机回归（§6.3） | 未做 | 本轮验收按用户指定改用 iPhone 17 模拟器；iOS 14 运行时仍需 iPhone 6s/7 |

### 10.2 验证

```bash
cd AmgiLite
./scripts/verify.sh --test   # build（14.0）+ 56 tests，iPhone 17
```

模拟器手工走查：Decks 长按 → Deck Options（改 New cards/day → Save → 重进确认）；
Settings → Note Types → Basic（Front/Back/Styles、Preview）；Browse → 笔记详情 → Edit
（字段 HTML、标签、Preview、未保存 Discard 拦截）。P1 没有入口，因此没有对应走查项。
