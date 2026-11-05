// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Sumbar", platforms: [.macOS(.v14)], products: [.executable(name: "Sumbar", targets: ["Sumbar"])], targets: [.executableTarget(name: "Sumbar"), .testTarget(name: "SumbarTests", dependencies: ["Sumbar"])])
