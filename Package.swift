// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Translatrix",
    platforms: [.macOS(.v13), .iOS(.v15)],
    products: [
        .executable(name: "translatrix", targets: ["Translatrix"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(name: "Translatrix", dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
    ]
)
