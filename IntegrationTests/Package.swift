// swift-tools-version: 6.0
import Foundation
import PackageDescription
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let verify = Process()
verify.executableURL = URL(fileURLWithPath: "/usr/bin/env")
verify.arguments = ["python3", root.appendingPathComponent("configs/surface_plugins_dependency.py").path, "verify"]
verify.currentDirectoryURL = root
verify.standardOutput = Pipe()
do {
    try verify.run(); verify.waitUntilExit()
    guard verify.terminationStatus == 0 else { fatalError("Ensure main integration SP source before building") }
} catch { fatalError("Cannot verify main integration source: \(error)") }
let package = Package(name: "MinimalDeviceIntegration", platforms: [.macOS(.v14)],
    products: [.executable(name: "CheckpointRunner", targets: ["CheckpointRunner"]),
               .executable(name: "PlatformCheckpointRunner", targets: ["PlatformCheckpointRunner"]),
               .executable(name: "ControlCheckpointRunner", targets: ["ControlCheckpointRunner"]),
               .executable(name: "CodecBoundaryRunner", targets: ["CodecBoundaryRunner"]),
               .executable(name: "CompleteScenarioRunner", targets: ["CompleteScenarioRunner"])],
    dependencies: [.package(path: ".."), .package(path: "build/seed/SurfacePlugins")],
    targets: [
        .target(name: "MinimalDeviceAdapter", dependencies: [.product(name: "SurfaceDeviceContracts", package: "ControlSurfaceKit")]),
        .executableTarget(name: "CheckpointRunner", dependencies: ["MinimalDeviceAdapter",
            .product(name: "SurfaceDeviceContracts", package: "ControlSurfaceKit"),
            .product(name: "SurfaceBindingContext", package: "ControlSurfaceKit"),
            .product(name: "SurfaceConnectionState", package: "ControlSurfaceKit"),
            .product(name: "SurfaceDeviceConformance", package: "ControlSurfaceKit"),
            .product(name: "SurfaceControlContracts", package: "SurfacePlugins"),
            .product(name: "SurfacePluginContracts", package: "SurfacePlugins"),
            .product(name: "RemoteToolContracts", package: "SurfacePlugins"),
            .product(name: "AgentPlugin", package: "SurfacePlugins"),
            .product(name: "AgentRemoteBinding", package: "SurfacePlugins")]),
        .target(name: "PlatformRuntime", dependencies: ["MinimalDeviceAdapter",
            .product(name: "SurfaceDeviceContracts", package: "ControlSurfaceKit"),
            .product(name: "SurfaceBindingContext", package: "ControlSurfaceKit"),
            .product(name: "SurfaceDeviceConformance", package: "ControlSurfaceKit"),
            .product(name: "SurfaceControlContracts", package: "SurfacePlugins"),
            .product(name: "SurfacePluginContracts", package: "SurfacePlugins"),
            .product(name: "RemoteToolContracts", package: "SurfacePlugins"),
            .product(name: "AgentPlugin", package: "SurfacePlugins"),
            .product(name: "AgentRemoteBinding", package: "SurfacePlugins")]),
        .executableTarget(name: "PlatformCheckpointRunner", dependencies: ["PlatformRuntime",
            .product(name: "SurfaceDeviceConformance", package: "ControlSurfaceKit")]),
        .executableTarget(name: "ControlCheckpointRunner", dependencies: ["PlatformRuntime",
            .product(name: "SurfaceDeviceConformance", package: "ControlSurfaceKit")]),
        .executableTarget(name: "CodecBoundaryRunner", dependencies: ["MinimalDeviceAdapter",
            .product(name: "SurfaceDeviceContracts", package: "ControlSurfaceKit"),
            .product(name: "SurfaceBindingContext", package: "ControlSurfaceKit"),
            .product(name: "SurfaceConnectionState", package: "ControlSurfaceKit")]),
        .target(name: "CompleteDeviceRuntime", dependencies: ["MinimalDeviceAdapter", "PlatformRuntime",
            .product(name: "SurfaceDeviceContracts", package: "ControlSurfaceKit"),
            .product(name: "SurfaceBindingContext", package: "ControlSurfaceKit"),
            .product(name: "SurfaceConnectionState", package: "ControlSurfaceKit"),
            .product(name: "SurfaceFeedbackPlanning", package: "ControlSurfaceKit"),
            .product(name: "SurfaceDeviceConformance", package: "ControlSurfaceKit"),
            .product(name: "SurfaceControlContracts", package: "SurfacePlugins"),
            .product(name: "SurfacePluginContracts", package: "SurfacePlugins")]),
        .executableTarget(name: "CompleteScenarioRunner", dependencies: ["CompleteDeviceRuntime", "PlatformRuntime",
            .product(name: "SurfaceDeviceConformance", package: "ControlSurfaceKit")])
    ], swiftLanguageModes: [.v6])
