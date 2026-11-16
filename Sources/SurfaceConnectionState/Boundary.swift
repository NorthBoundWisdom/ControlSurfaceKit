import SurfaceBindingContext

/// The future reducer is a caller-driven value, never a callback owner.
public enum ConnectionStateBoundary: Sendable {
    public static let name = "connection"
    public static let dependency = BindingContextBoundary.name
}
