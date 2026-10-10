// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mousebutton",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MouseButtonCore"
        ),
        .executableTarget(
            name: "mousebutton",
            dependencies: ["MouseButtonCore"]
        )
    ]
)
