import Foundation

public enum ConformanceError: Error, Equatable, Sendable {
    case invalidScalar
    case nonFiniteNumber
    case invalidEnvelope
    case missingObservation(instance: String, metric: String, phase: String)
    case numericRelationRequired
    case missingAssertionValue
}

/// JSON scalar with exact type equality: true is never the numeric value one.
public enum TraceValue: Equatable, Sendable, Codable {
    case number(Double)
    case flag(Bool)
    case text(String)
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .flag(value) }
        else if let value = try? container.decode(Double.self) {
            guard value.isFinite else { throw ConformanceError.nonFiniteNumber }
            self = .number(value)
        } else if let value = try? container.decode(String.self) { self = .text(value) }
        else { throw ConformanceError.invalidScalar }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value):
            guard value.isFinite else { throw ConformanceError.nonFiniteNumber }
            try container.encode(value)
        case .flag(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var isFinite: Bool {
        if case .number(let number) = self { return number.isFinite }
        return true
    }
}

/// Opaque setup/operation data. It carries no parameter or device behavior.
public indirect enum ScenarioPayload: Equatable, Sendable, Codable {
    case scalar(TraceValue)
    case array([ScenarioPayload])
    case object([String: ScenarioPayload])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode([String: ScenarioPayload].self) { self = .object(value) }
        else if let value = try? container.decode([ScenarioPayload].self) { self = .array(value) }
        else { self = .scalar(try TraceValue(from: decoder)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .scalar(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public enum AssertionRelation: String, Equatable, Sendable, Codable {
    case equals
    case notEquals = "not_equals"
    case unchanged
    case increased
    case increasedBy = "increased_by"
    case atLeast = "at_least"
}

public struct ScenarioAssertion: Equatable, Sendable, Codable {
    public let metric: String
    public let relation: AssertionRelation
    public let value: TraceValue?
    public let instanceID: String?

    public init(metric: String, relation: AssertionRelation, value: TraceValue? = nil, instanceID: String? = nil) {
        self.metric = metric
        self.relation = relation
        self.value = value
        self.instanceID = instanceID
    }

    enum CodingKeys: String, CodingKey {
        case metric, relation, value
        case instanceID = "instance_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metric = try container.decode(String.self, forKey: .metric)
        relation = try container.decode(AssertionRelation.self, forKey: .relation)
        // A present JSON null is an assertion value, distinct from a missing key.
        value = container.contains(.value) ? try container.decode(TraceValue.self, forKey: .value) : nil
        instanceID = try container.decodeIfPresent(String.self, forKey: .instanceID)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metric, forKey: .metric)
        try container.encode(relation, forKey: .relation)
        if let value { try container.encode(value, forKey: .value) }
        try container.encodeIfPresent(instanceID, forKey: .instanceID)
    }
}

public struct ScenarioAction: Equatable, Sendable, Codable {
    public let operation: String
    public let instanceID: String
    public let requiresFeatures: [String]
    public let arguments: ScenarioPayload
    public let expect: [ScenarioAssertion]

    enum CodingKeys: String, CodingKey {
        case operation, arguments, expect
        case instanceID = "instance_id"
        case requiresFeatures = "requires_features"
    }
}

public struct ScenarioDefinition: Equatable, Sendable, Codable {
    public let id: String
    public let title: String
    public let requiresFeatures: [String]
    public let setup: ScenarioPayload
    public let steps: [ScenarioAction]

    enum CodingKeys: String, CodingKey {
        case id, title, setup, steps
        case requiresFeatures = "requires_features"
    }
}

public struct ScenarioCatalog: Equatable, Sendable, Codable {
    public let schemaVersion: Int
    public let artifact: String
    public let sourceDocument: String
    public let scenarios: [ScenarioDefinition]

    enum CodingKeys: String, CodingKey {
        case artifact, scenarios
        case schemaVersion = "schema_version"
        case sourceDocument = "source_document"
    }

    /// Caller supplies validated fixture bytes. No file, resource or clock access.
    /// Full closed-schema/reference validation remains in the migrated validator.
    public static func decode(data: Data) throws -> ScenarioCatalog {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1,
              catalog.artifact == "neutral-controller-regression",
              Set(catalog.scenarios.map(\.id)).count == catalog.scenarios.count else {
            throw ConformanceError.invalidEnvelope
        }
        return catalog
    }
}

public typealias TraceObservations = [String: [String: TraceValue]]

public enum AssertionEvaluator: Sendable {
    /// Missing observations, invalid values or an incompatible numeric relation
    /// are errors; they cannot silently become pass or not-applicable.
    public static func evaluate(_ assertion: ScenarioAssertion, instanceID: String,
                                before: TraceObservations, after: TraceObservations) throws -> Bool {
        let instance = assertion.instanceID ?? instanceID
        func observation(_ values: TraceObservations, phase: String) throws -> TraceValue {
            guard let value = values[instance]?[assertion.metric] else {
                throw ConformanceError.missingObservation(instance: instance, metric: assertion.metric, phase: phase)
            }
            guard value.isFinite else { throw ConformanceError.nonFiniteNumber }
            return value
        }
        func desired() throws -> TraceValue {
            guard let value = assertion.value else { throw ConformanceError.missingAssertionValue }
            guard value.isFinite else { throw ConformanceError.nonFiniteNumber }
            return value
        }
        func number(_ value: TraceValue) throws -> Double {
            guard case .number(let number) = value else { throw ConformanceError.numericRelationRequired }
            return number
        }
        let current = try observation(after, phase: "after")
        switch assertion.relation {
        case .equals: return current == (try desired())
        case .notEquals: return current != (try desired())
        case .unchanged: return current == (try observation(before, phase: "before"))
        case .increased: return try number(current) > number(observation(before, phase: "before"))
        case .increasedBy:
            let difference = try number(current) - number(observation(before, phase: "before"))
            guard difference.isFinite else { throw ConformanceError.nonFiniteNumber }
            return try difference == number(desired())
        case .atLeast: return try number(current) >= number(desired())
        }
    }
}
