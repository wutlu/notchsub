// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchSub",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "NotchSub",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            path: "Sources/NotchSub",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
