// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Pastille",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pastille",
            path: "Sources/Pastille"
        ),
        .testTarget(
            name: "PastilleTests",
            dependencies: ["Pastille"],
            path: "Tests/PastilleTests"
        ),
    ]
)
