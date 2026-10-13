// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "RightPilot", platforms: [.macOS(.v13)], targets: [
    .target(name: "RightPilotCore"),
    .executableTarget(name: "CoreChecks", dependencies: ["RightPilotCore"], path: "Tests/CoreChecks")
])
