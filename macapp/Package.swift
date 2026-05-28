// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PaperManagerApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PaperManagerApp", targets: ["PaperManagerApp"]),
    ],
    targets: [
        .executableTarget(
            name: "PaperManagerApp",
            path: "Sources/PaperManagerApp"
        ),
    ]
)
