// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ProcessMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CProcessInfo",
            path: "Sources/CProcessInfo"
        ),
        .executableTarget(
            name: "ProcessMonitor",
            dependencies: ["CProcessInfo"],
            path: "Sources/ProcessMonitor",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
