// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ControlSurfaceKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SurfaceDeviceContracts", targets: ["SurfaceDeviceContracts"]),
        .library(name: "SurfaceBindingContext", targets: ["SurfaceBindingContext"]),
        .library(name: "SurfaceConnectionState", targets: ["SurfaceConnectionState"]),
        .library(name: "SurfaceFeedbackPlanning", targets: ["SurfaceFeedbackPlanning"]),
        // Test support only: no production target may depend on this product.
        .library(name: "SurfaceDeviceConformance", targets: ["SurfaceDeviceConformance"]),
    ],
    targets: [
        .target(name: "SurfaceDeviceContracts"),
        .target(name: "SurfaceBindingContext", dependencies: ["SurfaceDeviceContracts"]),
        .target(name: "SurfaceConnectionState", dependencies: ["SurfaceBindingContext"]),
        .target(name: "SurfaceFeedbackPlanning", dependencies: ["SurfaceConnectionState"]),
        .target(name: "SurfaceDeviceConformance", dependencies: ["SurfaceDeviceContracts", "SurfaceBindingContext", "SurfaceConnectionState", "SurfaceFeedbackPlanning"]),
        .testTarget(name: "ArchitectureTests", dependencies: ["SurfaceDeviceConformance"]),
        .testTarget(name: "DeviceContractTests", dependencies: ["SurfaceDeviceContracts"]),
        .testTarget(name: "ContextRuntimeTests", dependencies: ["SurfaceDeviceContracts", "SurfaceBindingContext", "SurfaceConnectionState"]),
        .testTarget(name: "ConformanceTests", dependencies: ["SurfaceDeviceContracts", "SurfaceDeviceConformance"]),
    ],
    swiftLanguageModes: [.v6]
)
