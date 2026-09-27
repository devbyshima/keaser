// swift-tools-version: 6.0
import PackageDescription

// Everything that does not need UIKit, SwiftUI or WidgetKit lives here, so the
// app and the widget extension share one model and the logic is testable on the
// Mac with `swift test` (no simulator).
//
// KeaserKit itself is Foundation-only. KeaserIntelligence adds Apple
// Intelligence (Foundation Models, on device) behind KeaserKit's protocols. Only
// the app links it; its model code also runs on the Mac, so the opt-in
// evaluation (`scripts/eval.sh`, KeaserIntelligenceEvals) measures exactly what
// ships.
let package = Package(
    name: "KeaserKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KeaserKit", targets: ["KeaserKit"]),
        .library(name: "KeaserIntelligence", targets: ["KeaserIntelligence"]),
    ],
    targets: [
        .target(name: "KeaserKit"),
        .target(name: "KeaserIntelligence", dependencies: ["KeaserKit"]),
        .testTarget(name: "KeaserKitTests", dependencies: ["KeaserKit"]),
        .testTarget(name: "KeaserIntelligenceTests", dependencies: ["KeaserIntelligence", "KeaserKit"]),
        // Runs the real on-device model; skipped unless KEASER_MODEL_EVALS=1.
        .testTarget(name: "KeaserIntelligenceEvals", dependencies: ["KeaserIntelligence", "KeaserKit"]),
    ]
)
