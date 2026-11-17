// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "qlm", platforms: [.macOS(.v15)], products: [.executable(name: "qlm", targets: ["qlm"])], targets: [.executableTarget(name: "qlm", path: "Sources", swiftSettings: [.swiftLanguageMode(.v5)])])
