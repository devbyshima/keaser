// swift-tools-version: 6.0
import PackageDescription

// Everything that does not need UIKit, SwiftUI or WidgetKit lives here, so the
// app and the widget extension share one model and the logic is testable on the
// Mac with `swift test` (no simulator).
let package = Package(
    name: "KeaserKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KeaserKit", targets: ["KeaserKit"]),
    ],
    targets: [
        .target(name: "KeaserKit"),
        .testTarget(name: "KeaserKitTests", dependencies: ["KeaserKit"]),
    ]
)
