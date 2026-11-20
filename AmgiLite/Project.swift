import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "AmgiLite",
    options: .options(
        disableSynthesizedResourceAccessors: true
    ),
    settings: LiteModule.appSettings,
    targets: [
        // MARK: App

        .target(
            name: "AmgiLite",
            destinations: .iOS,
            product: .app,
            bundleId: "com.amgiapp.AmgiLite",
            deploymentTargets: .iOS(LiteModule.deploymentTarget),
            infoPlist: .file(path: "Info.plist"),
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "AnkiKit"),
                .target(name: "AnkiBackend"),
                .target(name: "AnkiProtoBridge"),
                .target(name: "AnkiSync"),
                .target(name: "AmgiCardWeb"),
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "",
                "GENERATE_INFOPLIST_FILE": "NO",
            ])
        ),

        // MARK: Engine (copies of Sources/…, see Engine/README.md)

        LiteModule.engineTarget("AnkiKit"),

        LiteModule.engineTarget(
            "AnkiProto",
            dependencies: [.external(name: "SwiftProtobuf")],
            unsafeBoundary: true
        ),

        LiteModule.engineTarget(
            "AnkiBackend",
            dependencies: [
                .xcframework(path: .relativeToManifest("Frameworks/AnkiRustLib.xcframework")),
                .target(name: "AnkiProto"),
                .external(name: "SwiftProtobuf"),
            ],
            unsafeBoundary: true
        ),

        LiteModule.engineTarget(
            "AnkiProtoBridge",
            dependencies: [
                .target(name: "AnkiKit"),
                .target(name: "AnkiBackend"),
                .target(name: "AnkiProto"),
                .external(name: "SwiftProtobuf"),
            ]
        ),

        LiteModule.engineTarget(
            "AnkiSync",
            dependencies: [.target(name: "AnkiKit")]
        ),

        LiteModule.engineTarget("AmgiCardWeb"),

        // MARK: Tests

        .target(
            name: "AmgiLiteTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.amgiapp.AmgiLiteTests",
            deploymentTargets: .iOS(LiteModule.deploymentTarget),
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "AmgiLite"),
                .target(name: "AnkiBackend"),
                .target(name: "AnkiKit"),
                .target(name: "AnkiProtoBridge"),
            ]
        ),
    ],
    resourceSynthesizers: []
)
