import Foundation
import SurfaceDeviceContracts

/// Attempt means invoking the real transport boundary; a rejected pin can still
/// have zero physical writes. Admission/defer/disconnect before it is notAttempted.
public enum FeedbackAttemptResult: Equatable, Sendable {
    case notAttempted(reason: String)
    case accepted
    case rejected(reason: String)

    public var hasTransportAttempt: Bool {
        if case .notAttempted = self { return false }
        return true
    }
    public var successfulSend: Bool { self == .accepted }
    public var transmissionOutcome: TransmissionOutcome? {
        switch self {
        case .notAttempted: nil
        case .accepted: .accepted
        case .rejected(let reason): .rejected(reason: reason)
        }
    }
}

/// Old captured facts survive a late completion. There is deliberately no clock,
/// new identity, observation, sender or current-state candidate in this value.
public struct FeedbackReceiptFact<Plan: Equatable & Sendable>: Equatable, Sendable {
    public let plan: Plan
    public let result: FeedbackAttemptResult
    public init(plan: Plan, result: FeedbackAttemptResult) { self.plan = plan; self.result = result }
    public var hasTransportAttempt: Bool { result.hasTransportAttempt }
    public var successfulSend: Bool { result.successfulSend }
    public var transmissionOutcome: TransmissionOutcome? { result.transmissionOutcome }
}

public enum FeedbackReceiptEligibility: Sendable {
    /// Recompute at the native bookkeeping point, including after reentrant
    /// callbacks where required. Full captured evidence is not current identity.
    public static func matchesCurrentScope<Payload, Origin, Scope, Reference, CapturedEvidence>(
        _ receipt: FeedbackReceiptFact<FeedbackPlan<Payload, Origin, Scope, Reference, CapturedEvidence>>,
        currentScope: Scope
    ) -> Bool { receipt.plan.scope == currentScope }

    public static func acceptedInCurrentScope<Payload, Origin, Scope, Reference, CapturedEvidence>(
        _ receipt: FeedbackReceiptFact<FeedbackPlan<Payload, Origin, Scope, Reference, CapturedEvidence>>,
        currentScope: Scope
    ) -> Bool { receipt.successfulSend && matchesCurrentScope(receipt, currentScope: currentScope) }
}

/// Nonempty/all-success aggregation only. It owns no callback, native collector,
/// transaction, overlay undo, retry or inference from an evictable monitor.
public struct FeedbackReceiptSummary: Equatable, Sendable {
    public let attemptCount: Int
    public let acceptedCount: Int
    public let rejectedCount: Int
    public let notAttemptedCount: Int
    public var anyAccepted: Bool { acceptedCount > 0 }
    public var allAccepted: Bool { acceptedCount > 0 && rejectedCount == 0 && notAttemptedCount == 0 }

    public init(_ results: [FeedbackAttemptResult]) {
        var accepted = 0, rejected = 0, notAttempted = 0
        for result in results {
            switch result {
            case .accepted: accepted += 1
            case .rejected: rejected += 1
            case .notAttempted: notAttempted += 1
            }
        }
        attemptCount = accepted + rejected
        acceptedCount = accepted
        rejectedCount = rejected
        notAttemptedCount = notAttempted
    }
}
