// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tado",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Tado",
            path: "Sources/Tado"
        ),
    ]
)
