// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARCHiDesktop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ARCHiDesktop", targets: ["ARCHiDesktop"])],
    dependencies: [.package(path: "../shared/ARCHiSpatial")],
    targets: [
        .executableTarget(name: "ARCHiDesktop", dependencies: [.product(name: "ARCHiSpatial", package: "ARCHiSpatial")], resources: [.copy("Resources/CompanionArt"), .copy("Resources/ReactorBridge"), .copy("Resources/Branding"), .copy("Resources/ARC3Bridge"), .copy("Resources/RecordReader")]),
        .testTarget(name: "ARCHiDesktopTests", dependencies: ["ARCHiDesktop"]),
    ]
)
