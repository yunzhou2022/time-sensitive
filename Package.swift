// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "TimeSensitive",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "TimeSensitive", targets: ["TimeSensitive"])],
  targets: [
    .target(name: "TimerCore"),
    .executableTarget(name: "TimeSensitive", dependencies: ["TimerCore"]),
    .testTarget(name: "TimerCoreTests", dependencies: ["TimerCore"])
  ]
)
