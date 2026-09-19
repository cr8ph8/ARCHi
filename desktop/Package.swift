// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARCHiDesktop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ARCHiDesktop", targets: ["ARCHiDesktop"])],
    targets: [
        .executableTarget(name: "ARCHiDesktop", resources: [.copy("Resources/CompanionArt"), .copy("Resources/ReactorBridge"), .copy("Resources/Branding"), .copy("Resources/ARC3Bridge")]),
        .testTarget(name: "ARCHiDesktopTests", dependencies: ["ARCHiDesktop"]),
    ]
)
