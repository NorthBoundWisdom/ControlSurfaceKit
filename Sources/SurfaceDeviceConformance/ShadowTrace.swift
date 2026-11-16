import Foundation
import SurfaceDeviceContracts

public enum ShadowDecision: Equatable, Sendable {
    case accepted
    case rejected(reason: String)
    case ignored(reason: String)
}

/// A snapshot supplied by a host's actual execution at one step. No ideal reducer.
public struct ShadowSample: Equatable, Sendable {
    public let stepIndex: Int
    public let operationID: String
    public let decision: ShadowDecision
    public let context: DeviceContext
    public let endpoint: EndpointProvenance
    public let pendingQueueItems: [String]
    public let revokedQueueItems: [String]
    public let observations: [DeviceObservation]
    public let feedback: [EffectDescriptor]
    public let transmissions: [TransmissionEvidence]
    /// Full opaque transport records supplied by the adapter, in actual order.
    /// The kernel neither decodes nor normalizes their device-specific content.
    public let transportSequence: [String]

    public init(stepIndex: Int, operationID: String, decision: ShadowDecision,
                context: DeviceContext, endpoint: EndpointProvenance,
                pendingQueueItems: [String], revokedQueueItems: [String],
                observations: [DeviceObservation], feedback: [EffectDescriptor],
                transmissions: [TransmissionEvidence], transportSequence: [String]) {
        self.stepIndex = stepIndex
        self.operationID = operationID
        self.decision = decision
        self.context = context
        self.endpoint = endpoint
        self.pendingQueueItems = pendingQueueItems
        self.revokedQueueItems = revokedQueueItems
        self.observations = observations
        self.feedback = feedback
        self.transmissions = transmissions
        self.transportSequence = transportSequence
    }
}

public struct ShadowDifference: Equatable, Sendable {
    public let stepIndex: Int
    public let field: String
    public let reference: String
    public let candidate: String
}

public enum ShadowComparator: Sendable {
    /// Compares every field, retaining array order and duplicate multiplicity.
    /// No epsilon, subset projection, missing-field default or ignore list.
    public static func compare(reference: [ShadowSample], candidate: [ShadowSample]) -> [ShadowDifference] {
        var differences: [ShadowDifference] = []
        if reference.count != candidate.count {
            differences.append(ShadowDifference(stepIndex: -1, field: "stepCount",
                                                 reference: String(reference.count), candidate: String(candidate.count)))
        }
        for (index, pair) in zip(reference, candidate).enumerated() {
            func check<Value: Equatable>(_ field: String, _ left: Value, _ right: Value) {
                if left != right {
                    differences.append(ShadowDifference(stepIndex: index, field: field,
                                                         reference: String(reflecting: left), candidate: String(reflecting: right)))
                }
            }
            check("stepIndex", pair.0.stepIndex, pair.1.stepIndex)
            check("operationID", pair.0.operationID, pair.1.operationID)
            check("decision", pair.0.decision, pair.1.decision)
            check("context", pair.0.context, pair.1.context)
            check("endpoint", pair.0.endpoint, pair.1.endpoint)
            check("pendingQueueItems", pair.0.pendingQueueItems, pair.1.pendingQueueItems)
            check("revokedQueueItems", pair.0.revokedQueueItems, pair.1.revokedQueueItems)
            check("observations", pair.0.observations, pair.1.observations)
            check("feedback", pair.0.feedback, pair.1.feedback)
            check("transmissions", pair.0.transmissions, pair.1.transmissions)
            check("transportSequence", pair.0.transportSequence, pair.1.transportSequence)
        }
        return differences
    }
}
