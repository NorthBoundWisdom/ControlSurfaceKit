import SurfaceDeviceContracts

/// No binding reducer is adopted before host shadow comparisons.
public enum BindingContextBoundary: Sendable {
    public static let name = "binding"
    public static let dependency = DeviceContractBoundary.name
}
