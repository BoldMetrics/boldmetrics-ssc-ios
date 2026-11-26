// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BoldMetricsSSC",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "BoldMetricsSSC", targets: ["BoldMetricsSSC"]),
    ],
    targets: [
        .target(
            name: "BoldMetricsSSC",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "BoldMetricsSSCTests",
            dependencies: ["BoldMetricsSSC"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
