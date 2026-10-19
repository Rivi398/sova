// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sova",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Sova",
            path: "Sources/Sova",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
