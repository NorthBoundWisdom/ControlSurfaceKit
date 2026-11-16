import SurfaceConnectionState

/// Device-specific scheduling and safety stay in the adapter.
public enum FeedbackPlanningBoundary: Sendable {
    public static let name = "feedback"
    public static let dependency = ConnectionStateBoundary.name
}
