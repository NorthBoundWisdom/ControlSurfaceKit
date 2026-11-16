import SurfaceDeviceContracts
import SurfaceBindingContext
import SurfaceConnectionState
import SurfaceFeedbackPlanning

/// Test support only; this target is never a production dependency.
public enum ConformanceBoundary: Sendable {
    public static let dependencies = [DeviceContractBoundary.name, BindingContextBoundary.name,
                                      ConnectionStateBoundary.name, FeedbackPlanningBoundary.name]
}
