// swift-tools-version: 6.2
import PackageDescription

// AmgiLite deliberately keeps its dependency surface tiny so the folder can be
// moved out of the monorepo. Notably absent:
//   - swift-dependencies  (1.17 requires iOS 15; LiteServices uses plain injection)
//   - swift-sharing / swift-navigation / swift-case-paths (iOS 15)
//   - hoshidicts / EPUBKit / ZipArchive (AnkiClients-only, iOS 17/18)
let package = Package(
    name: "AmgiLiteDependencies",
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ]
)
