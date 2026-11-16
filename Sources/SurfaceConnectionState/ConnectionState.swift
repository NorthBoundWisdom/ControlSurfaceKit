import Foundation
import SurfaceBindingContext

/// Common route identity is mandatory. Extra preserves additional native identity
/// semantics without replacing or omitting the common input/output identities.
public struct ConnectionSnapshot<Extra: Equatable & Sendable>: Equatable, Sendable {
    public let inputID: String?
    public let outputID: String?
    public let transportGeneration: UInt64?
    public let isConnected: Bool
    public let extra: Extra

    public init(inputID: String?, outputID: String?, transportGeneration: UInt64?, isConnected: Bool, extra: Extra) throws {
        if inputID?.isEmpty == true { throw BindingContextError.emptyIdentifier("inputID") }
        if outputID?.isEmpty == true { throw BindingContextError.emptyIdentifier("outputID") }
        self.inputID = inputID
        self.outputID = outputID
        self.transportGeneration = transportGeneration
        self.isConnected = isConnected
        self.extra = extra
    }

    public func hasSameRoute(as other: Self) -> Bool {
        inputID == other.inputID && outputID == other.outputID &&
        transportGeneration == other.transportGeneration && extra == other.extra
    }
}

/// For a transport whose complete native route identity is the common fields.
public struct EmptyConnectionIdentity: Equatable, Sendable {
    public init() {}
}

public struct ConnectionTransition<Extra: Equatable & Sendable>: Equatable, Sendable {
    public let previous: ConnectionSnapshot<Extra>
    public let current: ConnectionSnapshot<Extra>
    public let previousGeneration: UInt64
    public let currentGeneration: UInt64
    public var routeChanged: Bool { !current.hasSameRoute(as: previous) }
    public var statusChanged: Bool { previous.isConnected != current.isConnected }
    public var invalidatesScope: Bool { routeChanged || statusChanged }
    public var clearPending: Bool { routeChanged || !current.isConnected }
    public var becameAvailable: Bool { current.isConnected && (!previous.isConnected || routeChanged) }
}

/// A pure value owner of route-change decisions. It emits no device effects and
/// does not reset caller epochs, replay work or fabricate any physical evidence.
public struct ConnectionState<Extra: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var snapshot: ConnectionSnapshot<Extra>
    public private(set) var connectionGeneration: UInt64

    public init(snapshot: ConnectionSnapshot<Extra>, connectionGeneration: UInt64) {
        self.snapshot = snapshot
        self.connectionGeneration = connectionGeneration
    }

    @discardableResult
    public mutating func apply(_ next: ConnectionSnapshot<Extra>) -> ConnectionTransition<Extra> {
        let changed = !snapshot.hasSameRoute(as: next) || snapshot.isConnected != next.isConnected
        let generation = changed ? next.transportGeneration ?? (connectionGeneration &+ 1) : connectionGeneration
        let transition = ConnectionTransition(previous: snapshot, current: next,
                                              previousGeneration: connectionGeneration, currentGeneration: generation)
        snapshot = next
        connectionGeneration = generation
        return transition
    }
}
