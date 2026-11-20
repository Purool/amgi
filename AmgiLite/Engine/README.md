# Engine sources

Copies of the monorepo's `Sources/` modules, so `AmgiLite/` can be moved out of
the repository and still build:

| Directory | Upstream | Changes |
|---|---|---|
| `AnkiKit/` | `Sources/AnkiKit` | none |
| `AnkiProto/` | `Sources/AnkiProto` | none |
| `AnkiBackend/` | `Sources/AnkiBackend` | `AnkiBackendDependency.swift` removed (`Dependencies` requires iOS 15); `Mutex` → `NSLock` + `@unchecked Sendable` for the iOS 14 floor |
| `AnkiProtoBridge/` | `Sources/AnkiProtoBridge` | none |
| `AnkiSync/` | `Sources/AnkiSync` | none |
| `AmgiCardWeb/` | `Sources/AmgiCardWeb` | `NativeCardContent.swift` removed (`AttributedString` is iOS 15); `URL.path(percentEncoded:)` → `URL.path` (iOS 16) |

## Re-syncing after an upstream change

```bash
cd AmgiLite
rsync -a --delete ../Sources/AnkiKit/ Engine/AnkiKit/
rsync -a --delete ../Sources/AnkiProto/ Engine/AnkiProto/
rsync -a --delete ../Sources/AnkiProtoBridge/ Engine/AnkiProtoBridge/
rsync -a --delete ../Sources/AnkiSync/ Engine/AnkiSync/

rsync -a --delete ../Sources/AnkiBackend/ Engine/AnkiBackend/
rm Engine/AnkiBackend/AnkiBackendDependency.swift

rsync -a --delete ../Sources/AmgiCardWeb/ Engine/AmgiCardWeb/
rm Engine/AmgiCardWeb/NativeCardContent.swift
```

Then re-apply the three edits the sync overwrote:

1. `Engine/AnkiBackend/AnkiBackend.swift` — `NSLock` + `@unchecked Sendable`
   block at the top of the class (replaces `Synchronization.Mutex`).
2. `Engine/AmgiCardWeb/CardAssetPath.swift` — `url.path(percentEncoded: true)`
   becomes `url.path` (the former is iOS 16).
3. `Engine/AnkiBackend/AnkiBackendDependency.swift` and
   `Engine/AmgiCardWeb/NativeCardContent.swift` stay deleted.

`scripts/verify.sh` catches all three: `Synchronization`, `path(percentEncoded:)`
and `AttributedString` fail to resolve against the iOS 14 target.

Do **not** re-add `AnkiBackendDependency.swift` as-is. If the Lite app ever needs
the `Dependencies` library, pin it to 1.10.x (the last iOS 13-compatible
release) in `Tuist/Package.swift` rather than taking 1.17.
