# Known issues

Behaviour that looks like a bug in the code you are touching, and is not.

## Engine

- **Deck tree with counts fails on a fresh sync.** Pass `now=0` to skip counts
  and fetch per-deck counts separately.
- **`SyncCollection` returns `FULL_DOWNLOAD` for an empty local collection.**
  Act on it — trigger the download — rather than reporting "already complete".
- **Apple's Compression framework has no zstd.** Rust handles zstd internally;
  no Swift-side compression is needed.

## Linking

- **A screen shows `DependenciesMacros.Unimplemented` / "Couldn't Load Decks"
  with "(… error 1.)".** A `@DependencyClient` resolved its empty `testValue`
  in a live context, because the `DependencyKey` conformance was compiled into a
  static-framework archive member the linker never extracted. Keep `liveValue`
  in the client's own file; see "Dependency client shape" in
  `Sources/AGENTS.md`. The console says which endpoint:
  `Unimplemented: 'DeckClient.fetchTree'`. The user-facing message only carries
  `Unimplemented error 1`, so check the log rather than the screen.

## Toolchain

- **SourceKit reports errors that do not exist.** Trust `build_sim` /
  `BuildProject` over the editor.
- **`libcxxshim.modulemap will be ignored`, three times per build.** One each
  for `ReaderFeature`, `RootFeature` and `AmgiApp` — the Cxx chain — and six if
  you build two architectures. swift-frontend warns about its own argument: C++
  interop appends `-fmodule-map-file=…/libcxxshim.modulemap`, then CAS-backed
  caching drops every `-fmodule-map-file` and warns per dropped file. Cosmetic;
  the C++ still compiles, because the modulemap reaches the build through the
  dependency scanner. Not silenceable — the diagnostic has no group, and the one
  lever (`COMPILATION_CACHE_ENABLE_CACHING: NO`) cannot be scoped to those
  targets and costs the whole caching win. Keep that setting enabled in
  `AmgiApp/Project.swift`.
- **`CODE_SIGNING_ALLOWED=NO` breaks a keychain test.** See
  `agents/build-and-verify.md`.
