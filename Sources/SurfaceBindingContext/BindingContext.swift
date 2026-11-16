import Foundation
import SurfaceDeviceContracts

public enum BindingContextError: Error, Equatable, Sendable {
    case emptyIdentifier(String)
    case negativeRemovalCount
}

/// An immutable reference into the caller's existing binding configuration.
/// Action payloads, parameter definitions and parameter values remain there.
public struct ContextBinding: Equatable, Sendable {
    public let elementID: String
    public let facetID: String
    public let inputKind: InputKind
    public let targetReferenceID: String

    public init(elementID: String, facetID: String, inputKind: InputKind, targetReferenceID: String) throws {
        for (field, value) in [("elementID", elementID), ("facetID", facetID), ("targetReferenceID", targetReferenceID)] {
            guard !value.isEmpty else { throw BindingContextError.emptyIdentifier(field) }
        }
        self.elementID = elementID
        self.facetID = facetID
        self.inputKind = inputKind
        self.targetReferenceID = targetReferenceID
    }
}

private struct BindingKey: Hashable, Sendable {
    let elementID: String
    let facetID: String
    let kind: String
}

/// First matching entry wins, preserving the caller's existing ordered lookup.
public struct BindingContext: Equatable, Sendable {
    public let context: DeviceContext
    public let entries: [ContextBinding]
    private let targets: [BindingKey: String]

    public init(context: DeviceContext, entries: [ContextBinding]) {
        self.context = context
        self.entries = entries
        var targets: [BindingKey: String] = [:]
        for entry in entries {
            let key = BindingKey(elementID: entry.elementID, facetID: entry.facetID, kind: entry.inputKind.rawValue)
            if targets[key] == nil { targets[key] = entry.targetReferenceID }
        }
        self.targets = targets
    }

    public func target(elementID: String, facetID: String, inputKind: InputKind) -> String? {
        targets[BindingKey(elementID: elementID, facetID: facetID, kind: inputKind.rawValue)]
    }
}

public struct BindingContextTransition: Equatable, Sendable {
    public let previous: BindingContext
    public let current: BindingContext
    public var contextChanged: Bool { previous.context != current.context }
    public var bindingsChanged: Bool { previous.entries != current.entries }
    public var changed: Bool { contextChanged || bindingsChanged }
}

/// Caller-supplied identities stay independent; replacement never mints an epoch.
public struct BindingContextState: Equatable, Sendable {
    public private(set) var current: BindingContext

    public init(_ current: BindingContext) { self.current = current }

    @discardableResult
    public mutating func apply(_ next: BindingContext) -> BindingContextTransition {
        let transition = BindingContextTransition(previous: current, current: next)
        current = next
        return transition
    }
}

/// Stable lifecycle and binding identity, captured before a delayed operation.
/// Per-input interpretation and physical observations are not lifecycle identity.
public struct ContextScope: Equatable, Sendable {
    public let source: DeviceSource
    public let context: DeviceContext
    public let endpoint: EndpointProvenance?

    public init(source: DeviceSource, context: DeviceContext, endpoint: EndpointProvenance?) {
        self.source = source
        self.context = context
        self.endpoint = endpoint
    }

    public func matches(_ captured: ContextScope) -> Bool { self == captured }
}
