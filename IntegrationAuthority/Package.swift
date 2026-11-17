// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Test infrastructure only. Acquisition is explicit; manifests only verify.
let authorityRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let verify = Process()
verify.executableURL = URL(fileURLWithPath: "/usr/bin/env")
verify.arguments = ["python3", authorityRoot.appendingPathComponent("configs/bcr_authority_dependency.py").path, "verify"]
verify.currentDirectoryURL = authorityRoot
do {
    try verify.run()
    verify.waitUntilExit()
    guard verify.terminationStatus == 0 else { fatalError("Run authority source ensure before building") }
} catch { fatalError("Cannot verify managed authority source: \(error)") }

let package = Package(
    name: "IntegrationAuthority",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AuthorityBridge", targets: ["AuthorityBridge"])],
    dependencies: [.package(path: "build/seed/BCR2000Dev")],
    targets: [.executableTarget(name: "AuthorityBridge", dependencies: [
        .product(name: "BCRSurfaceDomain", package: "BCR2000Dev")
    ])],
    swiftLanguageModes: [.v6]
)
