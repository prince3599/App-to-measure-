// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PlanCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "PlanCore", targets: ["PlanCore"]),
    ],
    targets: [
        .target(name: "PlanCore"),
        .testTarget(name: "PlanCoreTests", dependencies: ["PlanCore"]),
    ]
)
