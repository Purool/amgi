# AmgiLite

The iOS 14 / UIKit build of Amgi: browse cards and review them on schedule, and
nothing else. Everything outside this folder is the iOS 18 / SwiftUI app; this
folder shares no source files with it, so it can be moved to its own repository.

**Status: Phase 0 scaffold.** It builds for an iOS 14 deployment target, launches,
and the engine smoke test passes. Every screen is a placeholder; Phase 1 onwards
replaces them (see `Documentation/AMGI_LITE_IOS14_PLAN.md` in the monorepo).

## Layout

```
AmgiLite/
  Project.swift            Tuist manifest — one app target + engine targets
  Tuist.swift              makes this folder its own Tuist root
  Tuist/Package.swift      SwiftProtobuf + swift-log only (see "Dependency policy")
  Info.plist               scene manifest, portrait iPhone
  Engine/                  copies of the monorepo's Sources/ modules (see Engine/README.md)
  Frameworks/              AnkiRustLib.xcframework, built for iOS 14.0
  Sources/
    App/                   AppDelegate / SceneDelegate / AppContainer / Router / Composition
    DesignSystem/          UIColor-driven tokens (no SwiftUI)
    Services/              Contracts.swift — the only engine boundary feature code sees
    Support/               CardViewHosting (Phase 1 replaces the placeholder with WKWebView)
  Tests/AmgiLiteTests/     engine smoke test
  scripts/verify.sh        the one acceptance command
  scripts/build-engine.sh  rebuilds Frameworks/ from the monorepo (not needed to build the app)
```

## Build

```bash
cd AmgiLite
./scripts/verify.sh            # build, deployment target 14.0
./scripts/verify.sh --test     # + engine smoke test on a simulator
```

Requirements: Xcode 26.x, Tuist 4.210 (`mise` provides it), and the checked-in
framework. The app target compiles in Swift 5 mode; the engine targets keep the
monorepo's Swift 6 settings, so the copies stay byte-identical to `Sources/`.

Two environment quirks when running under a sandboxed agent:

- `tuist install` / `tuist generate` compile manifests through `sandbox-exec`;
  they need to run outside a seatbelt sandbox.
- `xcodebuild test` launches a simulator whose test runner needs to allocate a
  pty; that also fails under a sandbox.

Neither affects a normal terminal or CI.

## Dependency policy

Only SwiftProtobuf and swift-log. Everything else the main app uses is either
iOS 15+ or pointless for a browse/review-only app:

| Package | Floor | Why it is absent |
|---|---|---|
| `swift-dependencies` | iOS 15 (1.17+) | `AnkiServices` uses `@DependencyClient`; LiteServices injects `AnkiBackend` directly |
| `swift-sharing` / `swift-navigation` / `swift-case-paths` | iOS 15 | SwiftUI-era state/navigation, not needed in UIKit |
| `swift-perception` | iOS 15 | Observation backport, not needed (no `@Observable`) |
| `hoshidicts` | iOS 18 | Reader/dictionary only |
| `EPUBKit` / `ZipArchive` | iOS 17 / 15.5 | Reader only; `.apkg` zip parsing happens in Rust |

## Engine

`Engine/` holds copies of `Sources/AnkiKit`, `AnkiProto`, `AnkiBackend`,
`AnkiProtoBridge`, `AnkiSync` and `AmgiCardWeb`. `Engine/README.md` lists the
three edits that make them iOS 14-safe and how to re-sync after upstream changes.

`Frameworks/AnkiRustLib.xcframework` is the Rust engine built with
`IPHONEOS_DEPLOYMENT_TARGET=14.0` (device + simulator, no watchOS slice). It is
checked in on purpose: git worktrees — and a standalone copy of this folder — must
not need a 20-minute Rust build to compile the app. Rebuild it with
`scripts/build-engine.sh` from inside the monorepo; outside the monorepo you can
only consume it.

## What the scaffold already guarantees

- App and engine build with `-target arm64-apple-ios14.0`, `MinimumOSVersion 14.0`.
- `AnkiRustLib.framework` is embedded with `MinimumOSVersion 14.0`.
- `libswift_Concurrency.dylib` is embedded for the iOS 13/14 back-deployment.
- `EngineSmokeTests` opens a collection through the Rust dylib and closes it.
- `AnkiBackend` no longer needs `Synchronization.Mutex` (iOS 18).

## Not done yet (Phase 0 exit criteria)

- Run on a physical iOS 14 device (iPhone 6s/7): the only real WebKit/SQLite check.
- Real deck list / review / browse screens; `Composition.swift` is the single
  wiring point the integration shards edit.
