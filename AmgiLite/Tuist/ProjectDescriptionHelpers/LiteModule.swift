import Foundation
import ProjectDescription

/// Target/settings helpers for the Lite project.
///
/// The engine modules are copies of `Sources/AnkiKit` … under `Engine/`. They
/// are compiled with the same Swift language settings as the monorepo because
/// the copied code uses `public import`, `package import`, and the Swift 6.2
/// upcoming features. The app layer is plain Swift 5 so UIKit code is not
/// dragged into strict-concurrency diagnostics.
public enum LiteModule {
    public static let deploymentTarget = "14.0"
    public static let enginePackageName = "AnkiBridge"

    // MARK: - Settings

    public static let appSettings: Settings = {
        let base: SettingsDictionary = [
            "SWIFT_VERSION": "5.0",
            "SWIFT_STRICT_CONCURRENCY": "minimal",
            "IPHONEOS_DEPLOYMENT_TARGET": .string(deploymentTarget),
            "TARGETED_DEVICE_FAMILY": "1",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "ENABLE_POINTER_AUTHENTICATION": "NO",
            "COMPILATION_CACHE_ENABLE_CACHING": "YES",
            "MARKETING_VERSION": "0.1.0",
            "CURRENT_PROJECT_VERSION": "1",
        ]
        let debug: SettingsDictionary = ["EAGER_LINKING": "YES"]
        let release: SettingsDictionary = [
            "GCC_OPTIMIZATION_LEVEL": "s",
            "ONLY_ACTIVE_ARCH": "NO",
        ]
        return .settings(base: base, debug: debug, release: release)
    }()

    static func engineSettings(package: String, unsafeBoundary: Bool) -> Settings {
        var experimentalFeatures = [
            "IsolatedAny",
            "AccessLevelOnImport",
            "StrictSendableMetatypes",
        ]
        // The C++/FFI boundary intentionally contains unsafe operations.
        if !unsafeBoundary {
            experimentalFeatures.append("StrictMemorySafety")
        }
        // MemberImportVisibility is deliberately omitted: the copied AnkiKit
        // files rely on Foundation members without importing Foundation in
        // every file. Enabling it here would force edits to the copies, which
        // defeats re-syncing them from Sources/.
        let upcomingFeatures = [
            "ExistentialAny",
            "InternalImportsByDefault",
            "FullTypedThrows",
            "InferIsolatedConformances",
            "NonisolatedNonsendingByDefault",
        ]

        var flags = "$(inherited) -package-name \(package)"
        for feature in experimentalFeatures {
            flags += " -enable-experimental-feature \(feature)"
        }
        for feature in upcomingFeatures {
            flags += " -enable-upcoming-feature \(feature)"
        }

        let base: SettingsDictionary = [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "IPHONEOS_DEPLOYMENT_TARGET": .string(deploymentTarget),
            "OTHER_SWIFT_FLAGS": .string(flags),
        ]
        return .settings(base: base)
    }

    // MARK: - Targets

    /// One engine module, sourced from `Engine/<name>/**`.
    public static func engineTarget(
        _ name: String,
        dependencies: [TargetDependency] = [],
        unsafeBoundary: Bool = false
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "com.amgiapp.lite.\(name)",
            deploymentTargets: .iOS(deploymentTarget),
            sources: [.glob(.relativeToManifest("Engine/\(name)/**"))],
            dependencies: dependencies,
            settings: engineSettings(package: enginePackageName, unsafeBoundary: unsafeBoundary)
        )
    }
}
