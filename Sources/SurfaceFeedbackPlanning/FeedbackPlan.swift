import Foundation
import SurfaceDeviceContracts

public enum FeedbackDeliveryMode: Equatable, Sendable {
    case direct
    case coalescible
}

/// A scheduling choice, never authorization or evidence of a transport attempt.
public enum FeedbackDispatchChoice: Equatable, Sendable { case enqueue, send }

/// Complete immutable dispatch facts. Reference is caller-owned and need not be
/// globally unique. Native payload/evidence are opaque values, not device policy.
public struct FeedbackPlan<Payload: Equatable & Sendable, Origin: Equatable & Sendable,
                           Scope: Equatable & Sendable, Reference: Equatable & Sendable,
                           CapturedEvidence: Equatable & Sendable>: Equatable, Sendable {
    public let reference: Reference
    public let payload: Payload
    public let origin: Origin
    public let scope: Scope
    public let source: DeviceSource
    public let endpointEvidence: EndpointProvenance
    public let capturedEvidence: CapturedEvidence
    public let targetID: String
    public let affectedElements: Set<String>
    public let classification: EffectClassification
    public let sideEffects: Set<EffectDirection>
    public let deliveryMode: FeedbackDeliveryMode

    public var requiredDirections: Set<EffectDirection> { sideEffects.union([classification.direction]) }

    public init(reference: Reference, payload: Payload, origin: Origin, scope: Scope,
                source: DeviceSource, endpointEvidence: EndpointProvenance, capturedEvidence: CapturedEvidence,
                targetID: String, affectedElements: Set<String>, classification: EffectClassification,
                sideEffects: Set<EffectDirection>, deliveryMode: FeedbackDeliveryMode) throws {
        guard !targetID.isEmpty else { throw DeviceContractError.emptyIdentifier("feedback.targetID") }
        for element in affectedElements {
            guard !element.isEmpty else { throw DeviceContractError.emptyIdentifier("feedback.affectedElements") }
        }
        self.reference = reference
        self.payload = payload
        self.origin = origin
        self.scope = scope
        self.source = source
        self.endpointEvidence = endpointEvidence
        self.capturedEvidence = capturedEvidence
        self.targetID = targetID
        self.affectedElements = affectedElements
        self.classification = classification
        self.sideEffects = sideEffects
        self.deliveryMode = deliveryMode
    }

    public func dispatchChoice(canCoalesce: Bool) -> FeedbackDispatchChoice {
        deliveryMode == .coalescible && canCoalesce ? .enqueue : .send
    }
}
