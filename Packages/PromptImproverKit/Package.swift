// swift-tools-version: 6.2
import PackageDescription

// All of Afino's code lives in this package. The Xcode project's app target is a shell whose
// main.swift calls `PromptImproverApplication.main()` from PIApp.
//
// The modules form layers, and each depends only on layers below it:
//
//   L0  PIFoundation   settings store, logging, Keychain, file helpers
//   L1  PIProviders    Anthropic and OpenAI clients: streaming, retries, errors, model catalog
//       PIPrompts      the engine prompt, the target packs, request assembly, output clean-up
//       PIDesign       design tokens and components (depends on nothing else here)
//   L2  PICore         the improve session and its state machine, settings, keys, history
//   L3  PIApp          the composition root: panel, Settings, menu bar item, shortcuts, updates
//
// Modules on the same layer never import each other, and PIApp is the only module that links
// Sparkle. `prompt-eval` (the PromptEval target) is a developer tool beside the layers: it runs
// PIPrompts and PIProviders against the real APIs and is never linked into the app.
//
// The package, the `PI` module prefix and the bundle identifier keep the name the project had
// before 1.0, PromptImprover. Renaming the bundle identifier would strand existing preferences
// and Keychain items; the other names never reach the user.

/// The upcoming language features every target is written against.
let commonSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// UI modules run on the main actor by default; everything else is nonisolated by default.
let uiSettings: [SwiftSetting] = commonSettings + [.defaultIsolation(MainActor.self)]

/// A library target with the package's settings; `ui` selects main-actor default isolation.
func module(
    _ name: String,
    ui: Bool = false,
    dependsOn dependencies: [Target.Dependency] = [],
    resources: [Resource]? = nil
) -> Target {
    .target(
        name: name,
        dependencies: dependencies,
        resources: resources,
        swiftSettings: ui ? uiSettings : commonSettings
    )
}

/// A test target with the same settings as the module it tests.
func tests(_ name: String, ui: Bool = false, for dependencies: [Target.Dependency], resources: [Resource]? = nil) -> Target {
    .testTarget(
        name: name,
        dependencies: dependencies,
        resources: resources,
        swiftSettings: ui ? uiSettings : commonSettings
    )
}

let package = Package(
    name: "PromptImproverKit",
    defaultLocalization: "en",
    // The single deployment target. PromptImprover.xcodeproj must state the same version;
    // DeploymentTargetTests fails when the two drift apart.
    platforms: [.macOS("26.0")],
    products: [
        // What the app target links.
        .library(name: "PIApp", targets: ["PIApp"]),
        // Opt-in quality and latency checks against the real APIs; spends the caller's own API credit.
        .executable(name: "prompt-eval", targets: ["PromptEval"]),
    ],
    dependencies: [
        // In-app updates for builds distributed outside the App Store.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        // L0: foundation
        module("PIFoundation"),
        tests("PIFoundationTests", for: ["PIFoundation"]),

        // L1: provider clients, prompt engine, design system
        module("PIProviders", dependsOn: ["PIFoundation"]),
        tests("PIProvidersTests", for: ["PIProviders", "PIFoundation"], resources: [.copy("Fixtures")]),
        module("PIPrompts", dependsOn: ["PIFoundation"], resources: [.copy("Resources")]),
        tests("PIPromptsTests", for: ["PIPrompts", "PIFoundation"]),
        module("PIDesign", ui: true),
        tests("PIDesignTests", ui: true, for: ["PIDesign"]),

        // The evaluation harness: runs the shipped prompt engine and provider clients over a fixture
        // set. Its own tests run offline in `swift test`; the tool itself is run by hand and is
        // never linked into the app.
        .executableTarget(
            name: "PromptEval",
            dependencies: ["PIPrompts", "PIProviders", "PIFoundation"],
            resources: [.copy("Fixtures")],
            swiftSettings: commonSettings
        ),
        tests("PromptEvalTests", for: ["PromptEval", "PIPrompts", "PIProviders"]),

        // L2: application logic
        module("PICore", ui: true, dependsOn: ["PIProviders", "PIPrompts", "PIFoundation"]),
        tests("PICoreTests", ui: true, for: ["PICore", "PIProviders", "PIPrompts", "PIFoundation"]),

        // L3: composition root
        module("PIApp", ui: true, dependsOn: [
            "PICore", "PIDesign", "PIProviders", "PIPrompts", "PIFoundation",
            .product(name: "Sparkle", package: "Sparkle"),
        ], resources: [.process("Resources")]),
        tests("PIAppTests", ui: true, for: ["PIApp", "PICore", "PIDesign", "PIFoundation"]),
    ],
    swiftLanguageModes: [.v6]
)
