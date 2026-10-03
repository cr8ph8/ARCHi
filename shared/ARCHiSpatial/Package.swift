// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARCHiSpatial",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "ARCHiSpatial", targets: ["ARCHiSpatial"])],
    targets: [
        .target(name: "ARCHiSpatial"),
        .testTarget(name: "ARCHiSpatialTests", dependencies: ["ARCHiSpatial"]),
    ]
)
