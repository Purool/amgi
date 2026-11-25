# AmgiLite

The iOS 14 / UIKit build of Amgi: browse and review cards, edit notes and their
templates, tune deck options, and optimize FSRS weights.

Everything outside this folder belongs to the iOS 18 / SwiftUI app. This folder
shares no source files with it and can be moved to its own repository: the engine
is a copy under `Engine/`, the binary is the checked-in
`Frameworks/AnkiRustLib.xcframework`.

**This folder is self-contained.** Its docs, plans and code all live here.
Parent directories are read-only inputs: `../Sources` is where `Engine/` copies
come from, and `../anki-bridge-rs` + `../anki-upstream` are only needed to
rebuild the xcframework. Do not edit the parent directories, and do not add Lite
docs to `../Documentation`.

## Status

| Phase | Scope | State |
|---|---|---|
| 0 | iOS 14 toolchain, Tuist project, engine slice, smoke test | done |
| 1 | services, design system, card web view, shell | done |
| 2 | Decks / Review / Browse | done |
| 3 | Onboarding / Settings (AnkiWeb, sync, `.apkg` import) | done |
| 4 | **card templates, card text, deck options, FSRS optimization** | **P0 done** (P1 field/new-note extras deferred) |
| 5 | test hardening, device regression, AppIcon, TestFlight | not started |

Available today: deck tree with new/learning/due badges, review with Q/A toggle,
four ratings, undo and a finished state, browse with search and a note detail
with a modal editor, first-launch onboarding (create / import / sign in),
AnkiWeb sign-in and sync with media progress and the full-sync conflict prompt,
`.apkg` import, deck options (presets, limits, ordering, burying, advanced
multipliers, FSRS), note-type templates with front/back/CSS editing and card
preview, and a settings/about screen. 56 unit tests run against the real engine
and cover the Phase 4 RPCs end to end.

## Phase 4 (P0 landed)

- **Card templates** — note type list, per-template front/back/styling source
  editing, field insertion, preview with draft CSS, validation, save. Field
  management is a P1 item.
- **Card text** — edit a note's fields and tags, delete a note, preview unsaved
  edits. Adding new notes is a P1 item.
- **Deck options** — preset switch/create/rename/delete, daily limits, new-card
  and lapse steps, burying, ordering, advanced multipliers.
- **FSRS** — enable FSRS, desired/historical retention, weight editing,
  "optimize weights" for one preset or all presets, health check.

Still deferred (P1): field management, adding notes, creating/copying note
types, the review-screen menu, and the debug form gallery.

Out of scope: statistics, EPUB/dictionary, widgets/watch/shortcuts, iPad,
image occlusion, `ChangeNotetype`, FSRS simulator, media insertion in note
editing (the bridge has no `storeMediaFile`).

## Layout

```
AmgiLite/
  AGENTS.md                     rules for agents working in this folder
  AMGI_LITE_IOS14_PLAN.md       the plan: reuse, iOS 14 choices, phases, schedule
  AMGI_LITE_PHASE4_PLAN.md      Phase 4 implementation detail
  README.md                     this file
  Project.swift                 Tuist manifest — app + engine targets + tests
  Tuist.swift / Tuist/          makes this folder its own Tuist root
  Info.plist                    scene manifest, portrait iPhone, arm64
  Engine/                       copies of the monorepo's Sources/ modules
  Frameworks/                   AnkiRustLib.xcframework, built for iOS 14.0
  Sources/
    App/                        AppDelegate / SceneDelegate / AppContainer / Router / Composition
    DesignSystem/               colours, type, spacing, shared controls, form rows
    Services/                   Contracts.swift — the only engine boundary screens see
    Support/                    card web view, scheme handler, alerts, progress, error copy
    Features/Decks|Review|Browse|Onboarding|Settings|DeckOptions|Templates|NoteEditor/
  Tests/AmgiLiteTests/          engine-backed unit tests
  scripts/verify.sh             the one acceptance command
  scripts/build-engine.sh       rebuilds Frameworks/ (monorepo only)
  scripts/install-device.sh     signed build + install on a connected iPhone
```

## Build

```bash
cd AmgiLite
./scripts/verify.sh            # tuist install → generate → build, deployment target 14.0
./scripts/verify.sh --test     # + unit tests on a simulator
```

Requirements: Xcode 26.x, Tuist 4.210 (provided by `mise`), and the checked-in
framework. `verify.sh` pins `ARCHS=arm64` (the engine has no x86_64 slice) and
`IPHONEOS_DEPLOYMENT_TARGET=14.0`; do not replace it with ad-hoc `xcodebuild`
runs and call the result green.

### Real device (iOS 14)

Xcode 26.3 still ships device support for iOS 14.3, so a real phone can be the
target — and it is the only place WebKit-on-14, SQLite and memory behaviour can
be verified, because there is no iOS 14 simulator runtime.

```bash
cd AmgiLite
TEAM_ID=XXXXXXXXXX DEVICE_UDID=<udid> ./scripts/install-device.sh
```

This needs an Apple ID signed into Xcode (Settings → Accounts); without one,
`xcodebuild -allowProvisioningUpdates` fails with `No Accounts` even when the
development certificate is in the keychain. `devicectl` is CoreDevice (iOS 17+),
so if it cannot reach an iOS 14 device it prints the fallback: open
`AmgiLite.xcworkspace`, pick the phone, Run.

Two environment quirks when running under a sandboxed agent:

- `tuist install` / `tuist generate` compile manifests through `sandbox-exec`;
  they need to run outside a seatbelt sandbox.
- `xcodebuild test` launches a simulator whose test runner needs to allocate a
  pty; that also fails under a sandbox.

Neither affects a normal terminal or CI.

## Dependency policy

Only SwiftProtobuf and swift-log. Everything else the main app uses is either
iOS 15+ or pointless for a deck/review/edit app:

| Package | Floor | Why it is absent |
|---|---|---|
| `swift-dependencies` | iOS 15 (1.17+) | `AnkiServices` uses `@DependencyClient`; `LiteServices` injects `AnkiBackend` directly |
| `swift-sharing` / `swift-navigation` / `swift-case-paths` | iOS 15 | SwiftUI-era state/navigation, not needed in UIKit |
| `swift-perception` | iOS 15 | Observation backport, not needed (no `@Observable`) |
| `hoshidicts` | iOS 18 | Reader/dictionary only |
| `EPUBKit` / `ZipArchive` | iOS 17 / 15.5 | Reader only; `.apkg` zip parsing happens in Rust |

## Engine

`Engine/` holds copies of `Sources/AnkiKit`, `AnkiProto`, `AnkiBackend`,
`AnkiProtoBridge`, `AnkiSync` and `AmgiCardWeb`. Four edits make them iOS 14-safe
(`Mutex` → `NSLock` in `AnkiBackend`, `AnkiBackendDependency.swift` removed,
`NativeCardContent.swift` removed, `path(percentEncoded:)` → `path`).
`Engine/AGENTS.md` and `Engine/README.md` list them and how to re-sync after an
upstream change. The monorepo itself is not modified by this folder.

`Frameworks/AnkiRustLib.xcframework` is the Rust engine built with
`IPHONEOS_DEPLOYMENT_TARGET=14.0` (device + simulator, no watchOS slice). It is
checked in on purpose: worktrees — and a standalone copy of this folder — must
not need a 20-minute Rust build to compile the app. Rebuild it with
`scripts/build-engine.sh` from inside the monorepo; the repository `.gitignore`
ignores the xcframework, so it has to be committed with `git add -f`.

## Known limits

- **No iOS 14 simulator runtime.** Deployment target is 14.0, but tests run on
  the newest simulator; a physical iPhone 6s/7 is the only 14.x check.
- **arm64 only.** There is no x86_64 slice in the engine, so Intel simulators
  cannot run the app.
- **No AppIcon yet** (Phase 5).
- **iOS 14 WebKit** does not support `:has()` or `aspect-ratio`; a few decks'
  styling will differ from desktop clients.
- **Editing a template's structure forces a full sync** (fields or templates
  added/removed/reordered). The editor warns before saving.
- **Deck-option values outside the engine's bounds are silently reset to the
  default** rather than rejected; the form clamps them.
- **FSRS optimization cannot be interrupted** — the engine has no abort RPC, so
  "cancel" only stops waiting.
- **No media insertion when editing notes.** The bridge exposes no
  `storeMediaFile`, so field editing is text only.

Debug helper: `xcrun simctl launch booted com.amgiapp.AmgiLite -AmgiLiteStartAtSettings`
opens the Settings tab directly (DEBUG builds only).

Deck Options is reached by long-pressing a deck row; filtered decks have no
preset and deliberately do not offer it.

## Docs

- [`AGENTS.md`](AGENTS.md) — hard rules, layout, shard conventions, pitfalls.
- [`AMGI_LITE_IOS14_PLAN.md`](AMGI_LITE_IOS14_PLAN.md) — reuse and dependency
  strategy, iOS 14 API choices, phases, schedule.
- [`AMGI_LITE_PHASE4_PLAN.md`](AMGI_LITE_PHASE4_PLAN.md) — the current phase:
  engine semantics, contracts, screens, tests, risks.
- [`Engine/README.md`](Engine/README.md) — engine copies and the four iOS 14 patches.
- [`Sources/AGENTS.md`](Sources/AGENTS.md) — layering and screen conventions.
- [`Tests/AGENTS.md`](Tests/AGENTS.md) — test rules.
