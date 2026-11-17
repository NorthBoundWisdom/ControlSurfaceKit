import Foundation
import SurfaceDeviceContracts
import SurfaceFeedbackPlanning

public enum SchedulerCandidateError: Error, Equatable, Sendable {
    case invalid(String)
    case notInitialized
    case alreadyInitialized
    case ownerMismatch
    case ordinalMismatch
    case proposalMissing
    case itemMismatch
    case planPayloadMismatch
    case queuedEvidenceMismatch
}

func schedulerPayloadFinite(_ value: ScenarioPayload) -> Bool {
    switch value {
    case .scalar(let value): value.isFinite
    case .array(let values): values.allSatisfy(schedulerPayloadFinite)
    case .object(let values): values.values.allSatisfy(schedulerPayloadFinite)
    }
}

/// Whole native value and captured attribution. No field projection is applied
/// for candidate dedup: new IDs, times and actors remain observable differences.
public struct SchedulerItem: Equatable, Sendable {
    public let key: String
    public let value: ScenarioPayload
    public let scope: ScenarioPayload
    public init(key: String, value: ScenarioPayload, scope: ScenarioPayload) throws {
        guard !key.isEmpty else { throw SchedulerCandidateError.invalid("key") }
        guard schedulerPayloadFinite(value), schedulerPayloadFinite(scope) else { throw SchedulerCandidateError.invalid("nonfinite item") }
        self.key = key; self.value = value; self.scope = scope
    }
}

public enum SchedulerRate: Equatable, Sendable {
    case unlimited
    case bucket(perSecond: Double, burst: Int, errorCooldown: Double)
}
public enum SchedulerIngress: Equatable, Sendable {
    case externalRequest
    case derivedCallerRequeue(causeOrdinal: UInt64)
}
public enum SchedulerProposalCause: String, Equatable, Sendable {
    case direct, drain, release, style, refresh
}
public struct SchedulerProposal: Equatable, Sendable {
    public let ordinal: UInt64
    public let causeOrdinal: UInt64
    public let cause: SchedulerProposalCause
    public let item: SchedulerItem
}

public typealias SchedulerTracePlan = FeedbackPlan<ScenarioPayload, ScenarioPayload, ScenarioPayload, ScenarioPayload, ScenarioPayload>
public typealias SchedulerTraceProof = FeedbackProof<SchedulerTracePlan, ScenarioPayload>

public struct SchedulerGateRecord: Equatable, Sendable {
    public let proposalOrdinal: UInt64
    public let proposedItem: SchedulerItem
    public let dispatchPlan: SchedulerTracePlan
    public let proof: SchedulerTraceProof
    public let currentScope: ScenarioPayload
    public let currentNativeSnapshot: ScenarioPayload
    public init(proposalOrdinal: UInt64, proposedItem: SchedulerItem, dispatchPlan: SchedulerTracePlan,
                proof: SchedulerTraceProof, currentScope: ScenarioPayload, currentNativeSnapshot: ScenarioPayload) {
        self.proposalOrdinal = proposalOrdinal; self.proposedItem = proposedItem
        self.dispatchPlan = dispatchPlan; self.proof = proof
        self.currentScope = currentScope; self.currentNativeSnapshot = currentNativeSnapshot
    }
}

public struct SchedulerActualReceipt: Equatable, Sendable {
    public let item: SchedulerItem
    public let dispatchPlan: SchedulerTracePlan
    public let result: FeedbackAttemptResult
    public let currentScope: ScenarioPayload
    public init(item: SchedulerItem, dispatchPlan: SchedulerTracePlan, result: FeedbackAttemptResult, currentScope: ScenarioPayload) {
        self.item = item; self.dispatchPlan = dispatchPlan; self.result = result; self.currentScope = currentScope
    }
}

public enum SchedulerInput: Equatable, Sendable {
    case initialize(SchedulerRate)
    case enqueue(SchedulerItem, ingress: SchedulerIngress)
    case cancel(key: String)
    case drain(at: Double)
    case failure(at: Double)
    case clear
    case requestDirect(SchedulerItem)
    case changeStyle(style: SchedulerItem, projectionKey: String)
    case invalidateCache(affectedKeys: [String])
    case refreshDesired(order: [String])
    case release(key: String)
    case gate(SchedulerGateRecord)
    case receipt(SchedulerActualReceipt)
}

public struct SchedulerEnvelope: Equatable, Sendable {
    public let owner: String
    public let ordinal: UInt64
    public let input: SchedulerInput
    public let context: ScenarioPayload
    public init(owner: String, ordinal: UInt64, input: SchedulerInput, context: ScenarioPayload = .scalar(.null)) {
        self.owner = owner; self.ordinal = ordinal; self.input = input; self.context = context
    }
}

public struct SchedulerReadyProposal: Equatable, Sendable {
    public let proposal: SchedulerProposal
    public let plan: SchedulerTracePlan
}
public struct SchedulerGateDecision: Equatable, Sendable {
    public let proposalOrdinal: UInt64
    public let result: FeedbackPreflight
}
public struct SchedulerReceiptAssociation: Equatable, Sendable {
    public let proposalOrdinal: UInt64?
    public let receipt: SchedulerActualReceipt
    public let currentScopeMatches: Bool?
}

public struct SchedulerStateSnapshot: Equatable, Sendable {
    public let owner: String?
    public let inputOrdinal: UInt64
    public let rate: SchedulerRate?
    public let queued: [SchedulerItem]
    public let withheld: [SchedulerItem]
    public let desired: [String: SchedulerItem]
    public let acceptedCache: [String: SchedulerItem]
    public let awaitingGate: [SchedulerProposal]
    public let awaitingReceipt: [SchedulerReadyProposal]
    public let tokens: Double?
    public let lastRefill: Double?
    public let retryAfter: Double?
    public let persistentAlignmentDifferences: [String]
}

public struct SchedulerStep: Equatable, Sendable {
    public let input: SchedulerEnvelope
    public let snapshot: SchedulerStateSnapshot
    public let proposals: [SchedulerProposal]
    public let removedKeys: [String]
    public let replacedKeys: [String]
    public let deduplicatedKeys: [String]
    public let gateDecisions: [SchedulerGateDecision]
    public let receipts: [SchedulerReceiptAssociation]
    public let alignmentDifferences: [String]
}
