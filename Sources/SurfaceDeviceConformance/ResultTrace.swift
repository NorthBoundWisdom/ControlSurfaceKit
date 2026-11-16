import Foundation

public enum ScenarioStatus: String, Equatable, Sendable, Codable {
    case pass, fail
    case notApplicable = "not_applicable"
}

/// Frozen v1 trace vocabulary, not kernel device safety policy.
public enum ScenarioEffectKind: String, Equatable, Sendable, Codable {
    case display, motor, context, other
    case valueProjection = "value_projection"
}

public struct ScenarioEffectTrace: Equatable, Sendable, Codable {
    public let instanceID: String
    public let kinds: [ScenarioEffectKind]
    public let endpoint: String
    public let value: TraceValue
    public let accepted: Bool

    public init(instanceID: String, kinds: [ScenarioEffectKind], endpoint: String, value: TraceValue, accepted: Bool) {
        self.instanceID = instanceID
        self.kinds = kinds
        self.endpoint = endpoint
        self.value = value
        self.accepted = accepted
    }

    enum CodingKeys: String, CodingKey {
        case kinds, endpoint, value, accepted
        case instanceID = "instance_id"
    }
}

/// The original JSON step envelope. Schema validation is the single authority
/// for complete reports; this pure value is used to evaluate real observations.
public struct ScenarioStepTrace: Equatable, Sendable, Codable {
    public let index: Int
    public let operation: String
    public let status: ScenarioStatus
    public let reason: String?
    public let before: TraceObservations
    public let after: TraceObservations
    public let effects: [ScenarioEffectTrace]

    public init(index: Int, operation: String, status: ScenarioStatus, reason: String?,
                before: TraceObservations, after: TraceObservations, effects: [ScenarioEffectTrace]) {
        self.index = index
        self.operation = operation
        self.status = status
        self.reason = reason
        self.before = before
        self.after = after
        self.effects = effects
    }

    public func evaluate(_ assertion: ScenarioAssertion, instanceID: String) throws -> Bool {
        try AssertionEvaluator.evaluate(assertion, instanceID: instanceID, before: before, after: after)
    }
}
