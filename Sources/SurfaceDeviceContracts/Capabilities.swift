import Foundation

public enum DeviceValueKind: String, Equatable, Sendable {
    case number, flag, text, none
}

public struct InputCapability: Equatable, Sendable {
    public let kind: InputKind
    public let valueKind: DeviceValueKind

    public init(kind: InputKind, valueKind: DeviceValueKind) {
        self.kind = kind
        self.valueKind = valueKind
    }
}

public struct DisplayCapability: Equatable, Sendable {
    public let kind: String
    public let valueKind: DeviceValueKind

    public init(kind: String, valueKind: DeviceValueKind) throws {
        try requireID(kind, field: "display.kind")
        self.kind = kind
        self.valueKind = valueKind
    }
}

public struct EffectCapability: Equatable, Sendable {
    public let kind: String
    public let classification: EffectClassification
    public let sideEffects: Set<EffectDirection>
    public var requiredDirections: Set<EffectDirection> { sideEffects.union([classification.direction]) }

    public init(kind: String, classification: EffectClassification, sideEffects: Set<EffectDirection>) throws {
        try requireID(kind, field: "effectCapability.kind")
        self.kind = kind
        self.classification = classification
        self.sideEffects = sideEffects
    }
}

public struct ElementCapability: Equatable, Sendable {
    public let elementID: String
    public let inputs: [InputCapability]
    public let displays: [DisplayCapability]
    public let effects: [EffectCapability]

    public init(elementID: String, inputs: [InputCapability], displays: [DisplayCapability],
                effects: [EffectCapability]) throws {
        try requireID(elementID, field: "capability.elementID")
        self.elementID = elementID
        self.inputs = inputs
        self.displays = displays
        self.effects = effects
    }
}

/// Modes are opaque adapter identifiers, not permission or safety flags.
public struct ProtocolModeCapability: Equatable, Sendable {
    public let id: String
    public let elements: [ElementCapability]

    public init(id: String, elements: [ElementCapability]) throws {
        try requireID(id, field: "mode.id")
        guard Set(elements.map(\.elementID)).count == elements.count else {
            throw DeviceContractError.duplicateIdentifier("elementID")
        }
        self.id = id
        self.elements = elements
    }
}

public struct DeviceCapabilities: Equatable, Sendable {
    public let profileID: String
    public let modes: [ProtocolModeCapability]

    public init(profileID: String, modes: [ProtocolModeCapability]) throws {
        try requireID(profileID, field: "profileID")
        guard Set(modes.map(\.id)).count == modes.count else { throw DeviceContractError.duplicateIdentifier("mode.id") }
        self.profileID = profileID
        self.modes = modes
    }
}
