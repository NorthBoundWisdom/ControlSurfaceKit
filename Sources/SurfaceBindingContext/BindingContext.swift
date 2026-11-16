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

/// A configuration-level control reference, independent from event capability.
/// It neither declares an input role nor falls back from an unsupported role.
public struct ControlBinding: Equatable, Sendable {
    public let elementID: String
    public let facetID: String
    public let targetReferenceID: String

    public init(elementID: String, facetID: String, targetReferenceID: String) throws {
        for (field, value) in [("elementID", elementID), ("facetID", facetID), ("targetReferenceID", targetReferenceID)] {
            guard !value.isEmpty else { throw BindingContextError.emptyIdentifier(field) }
        }
        self.elementID = elementID
        self.facetID = facetID
        self.targetReferenceID = targetReferenceID
    }
}

private struct ControlBindingKey: Hashable, Sendable {
    let elementID: String
    let facetID: String
}

private func firstMatchTargets<Key: Hashable>(_ entries: [(Key, String)]) -> [Key: String] {
    var targets: [Key: String] = [:]
    for (key, reference) in entries where targets[key] == nil { targets[key] = reference }
    return targets
}

/// First matching entry wins, preserving the caller's existing ordered lookup.
public struct BindingContext: Equatable, Sendable {
    public let context: DeviceContext
    public let entries: [ContextBinding]
    public let controlEntries: [ControlBinding]
    private let targets: [BindingKey: String]
    private let controlTargets: [ControlBindingKey: String]

    public init(context: DeviceContext, entries: [ContextBinding]) {
        self.init(context: context, entries: entries, controlEntries: [])
    }

    public init(context: DeviceContext, controlEntries: [ControlBinding]) {
        self.init(context: context, entries: [], controlEntries: controlEntries)
    }

    public init(context: DeviceContext, entries: [ContextBinding], controlEntries: [ControlBinding]) {
        self.context = context
        self.entries = entries
        self.controlEntries = controlEntries
        self.targets = firstMatchTargets(entries.map {
            (BindingKey(elementID: $0.elementID, facetID: $0.facetID, kind: $0.inputKind.rawValue), $0.targetReferenceID)
        })
        self.controlTargets = firstMatchTargets(controlEntries.map {
            (ControlBindingKey(elementID: $0.elementID, facetID: $0.facetID), $0.targetReferenceID)
        })
    }

    public func target(elementID: String, facetID: String, inputKind: InputKind) -> String? {
        targets[BindingKey(elementID: elementID, facetID: facetID, kind: inputKind.rawValue)]
    }

    public func targetForControl(elementID: String, facetID: String) -> String? {
        controlTargets[ControlBindingKey(elementID: elementID, facetID: facetID)]
    }
}

public struct BindingContextTransition: Equatable, Sendable {
    public let previous: BindingContext
    public let current: BindingContext
    public var contextChanged: Bool { previous.context != current.context }
    public var bindingsChanged: Bool {
        previous.entries != current.entries || previous.controlEntries != current.controlEntries
    }
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
