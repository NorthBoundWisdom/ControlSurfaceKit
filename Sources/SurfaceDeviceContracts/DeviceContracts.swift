import Foundation

public enum DeviceContractError: Error, Equatable, Sendable {
    case emptyIdentifier(String)
    case nonFiniteValue
    case invalidObservation
    case duplicateIdentifier(String)
}

func requireID(_ value: String, field: String) throws {
    guard !value.isEmpty else { throw DeviceContractError.emptyIdentifier(field) }
}

func requireFinite(_ value: Double) throws {
    guard value.isFinite else { throw DeviceContractError.nonFiniteValue }
}

/// A device fact or effect payload, never a business parameter definition/store.
public enum DeviceValue: Equatable, Sendable, Codable {
    case number(Double)
    case flag(Bool)
    case text(String)
    case none

    public var isFinite: Bool {
        if case .number(let value) = self { return value.isFinite }
        return true
    }

    enum CodingKeys: String, CodingKey { case number, flag, text, none }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DeviceContractError.nonFiniteValue
        }
        switch key {
        case .number:
            let value = try container.decode(Double.self, forKey: .number)
            try requireFinite(value)
            self = .number(value)
        case .flag: self = .flag(try container.decode(Bool.self, forKey: .flag))
        case .text: self = .text(try container.decode(String.self, forKey: .text))
        case .none:
            guard try container.decodeNil(forKey: .none) else { throw DeviceContractError.invalidObservation }
            self = .none
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .number(let value):
            try requireFinite(value)
            try container.encode(value, forKey: .number)
        case .flag(let value): try container.encode(value, forKey: .flag)
        case .text(let value): try container.encode(value, forKey: .text)
        case .none: try container.encodeNil(forKey: .none)
        }
    }
}

public enum DeviceSource: String, Equatable, Sendable, Codable {
    case simulation, hardware
}

public enum EndpointTransportOrigin: String, Equatable, Sendable, Codable {
    case unknown, physicalUSB, localVirtual, remoteVirtual
}

/// Captured at receipt/planning, never reconstructed from the current connection.
/// Unknown IDs are nil; known transport provenance is retained independently.
/// Provenance by itself grants neither route identity nor hardware qualification.
public struct EndpointProvenance: Equatable, Sendable {
    public let endpointID: String?
    public let deviceID: String?
    public let connectionGeneration: UInt64
    public let transportOrigin: EndpointTransportOrigin

    public init(endpointID: String?, deviceID: String?, connectionGeneration: UInt64,
                transportOrigin: EndpointTransportOrigin) throws {
        if let endpointID { try requireID(endpointID, field: "endpointID") }
        if let deviceID { try requireID(deviceID, field: "deviceID") }
        self.endpointID = endpointID
        self.deviceID = deviceID
        self.connectionGeneration = connectionGeneration
        self.transportOrigin = transportOrigin
    }
}

/// Opaque adapter context. This type does not interpret layers, pages or modes.
public struct DeviceContext: Equatable, Sendable {
    public let id: String
    public let generation: String
    public let mappingRevision: String?

    public init(id: String, generation: String, mappingRevision: String?) throws {
        try requireID(id, field: "context.id")
        try requireID(generation, field: "context.generation")
        if let mappingRevision { try requireID(mappingRevision, field: "context.mappingRevision") }
        self.id = id
        self.generation = generation
        self.mappingRevision = mappingRevision
    }
}

public enum InputKind: String, Equatable, Sendable, Codable {
    case absolute, relative, press, release, contactBegan, contactEnded
}

public struct DeviceInputEvent: Equatable, Sendable {
    public let elementID: String
    public let kind: InputKind
    public let value: DeviceValue
    public let context: DeviceContext
    public let endpoint: EndpointProvenance
    public let source: DeviceSource
    public let at: Double

    public init(elementID: String, kind: InputKind, value: DeviceValue, context: DeviceContext,
                endpoint: EndpointProvenance, source: DeviceSource, at: Double) throws {
        try requireID(elementID, field: "elementID")
        try requireFinite(at)
        guard value.isFinite else { throw DeviceContractError.nonFiniteValue }
        self.elementID = elementID
        self.kind = kind
        self.value = value
        self.context = context
        self.endpoint = endpoint
        self.source = source
        self.at = at
    }
}

public enum ObservationState: String, Equatable, Sendable {
    case unknown, observed, expired
}

public enum ObservationEvidence: String, Equatable, Sendable {
    case deviceReport, readback, operatorObservation
}

/// Sent evidence is deliberately absent from ObservationEvidence.
public struct DeviceObservation: Equatable, Sendable {
    public let targetID: String
    public let value: DeviceValue?
    public let state: ObservationState
    public let evidence: ObservationEvidence?
    public let context: DeviceContext
    public let endpoint: EndpointProvenance
    public let source: DeviceSource
    public let at: Double

    public init(targetID: String, value: DeviceValue?, state: ObservationState,
                evidence: ObservationEvidence?, context: DeviceContext, endpoint: EndpointProvenance,
                source: DeviceSource, at: Double) throws {
        try requireID(targetID, field: "targetID")
        try requireFinite(at)
        guard value?.isFinite != false else { throw DeviceContractError.nonFiniteValue }
        switch state {
        case .unknown:
            guard value == nil && evidence == nil else { throw DeviceContractError.invalidObservation }
        case .observed:
            guard value != nil && evidence != nil else { throw DeviceContractError.invalidObservation }
        case .expired:
            guard (value == nil) == (evidence == nil) else { throw DeviceContractError.invalidObservation }
        }
        self.targetID = targetID
        self.value = value
        self.state = state
        self.evidence = evidence
        self.context = context
        self.endpoint = endpoint
        self.source = source
        self.at = at
    }
}

public enum EffectDirection: String, Hashable, Sendable, Codable {
    case display, mechanism, management, query
}

public enum EffectClassification: String, Equatable, Sendable, Codable {
    case display, mechanism, management, query

    public var direction: EffectDirection {
        switch self {
        case .display: .display
        case .mechanism: .mechanism
        case .management: .management
        case .query: .query
        }
    }
}

public enum EffectTiming: Equatable, Sendable {
    case immediate
    case deferred(until: Double)
}

/// Describes facts; it has no sender, permission override or device safety switch.
public struct EffectDescriptor: Equatable, Sendable {
    public let id: String
    public let targetID: String
    public let affectedElements: Set<String>
    public let value: DeviceValue
    public let classification: EffectClassification
    public let sideEffects: Set<EffectDirection>
    public let context: DeviceContext
    public let endpoint: EndpointProvenance
    public let source: DeviceSource
    public let timing: EffectTiming
    public let at: Double

    public var requiredDirections: Set<EffectDirection> { sideEffects.union([classification.direction]) }

    public init(id: String, targetID: String, affectedElements: Set<String>, value: DeviceValue,
                classification: EffectClassification, sideEffects: Set<EffectDirection>,
                context: DeviceContext, endpoint: EndpointProvenance, source: DeviceSource,
                timing: EffectTiming, at: Double) throws {
        try requireID(id, field: "effect.id")
        try requireID(targetID, field: "effect.targetID")
        for element in affectedElements { try requireID(element, field: "affectedElements") }
        try requireFinite(at)
        if case .deferred(let until) = timing { try requireFinite(until) }
        guard value.isFinite else { throw DeviceContractError.nonFiniteValue }
        self.id = id
        self.targetID = targetID
        self.affectedElements = affectedElements
        self.value = value
        self.classification = classification
        self.sideEffects = sideEffects
        self.context = context
        self.endpoint = endpoint
        self.source = source
        self.timing = timing
        self.at = at
    }
}

public enum TransmissionOutcome: Equatable, Sendable {
    case accepted
    case rejected(reason: String)
}

/// Transport acceptance is not a DeviceObservation and cannot be promoted to one.
public struct TransmissionEvidence: Equatable, Sendable {
    public let effectID: String
    public let targetID: String
    public let context: DeviceContext
    public let endpoint: EndpointProvenance
    public let source: DeviceSource
    public let at: Double
    public let outcome: TransmissionOutcome

    public init(effectID: String, targetID: String, context: DeviceContext, endpoint: EndpointProvenance,
                source: DeviceSource, at: Double, outcome: TransmissionOutcome) throws {
        try requireID(effectID, field: "effectID")
        try requireID(targetID, field: "targetID")
        try requireFinite(at)
        if case .rejected(let reason) = outcome { try requireID(reason, field: "rejection.reason") }
        self.effectID = effectID
        self.targetID = targetID
        self.context = context
        self.endpoint = endpoint
        self.source = source
        self.at = at
        self.outcome = outcome
    }
}
