// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SiftApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SiftApp", targets: ["SiftApp"]),
    ],
    targets: [
        .executableTarget(
            name: "SiftApp",
            path: "Sources/SiftApp"
        ),
    ]
)
