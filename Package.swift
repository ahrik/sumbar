// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Sumbar", defaultLocalization: "ru", platforms: [.macOS(.v14)], products: [.executable(name: "Sumbar", targets: ["Sumbar"])], targets: [.executableTarget(name: "Sumbar", resources: [.process("Resources")]), .testTarget(name: "SumbarTests", dependencies: ["Sumbar"])])
