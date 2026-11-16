import SurfaceDeviceContracts

/// The package dependency boundary; adoption requires host shadow comparisons.
public enum BindingContextBoundary: Sendable {
    public static let name = "binding"
    public static let dependency = DeviceContractBoundary.name
}
