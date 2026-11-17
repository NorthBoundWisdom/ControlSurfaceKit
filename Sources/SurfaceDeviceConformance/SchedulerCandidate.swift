import Foundation
import SurfaceFeedbackPlanning

/// Test support only. Own state, input-only evolution, no native-output restore,
/// device gate, sender, callback or clock. Proposals are never executed here.
public struct SchedulerCandidate: Sendable {
    private var owner: String?
    private var inputOrdinal: UInt64 = 0
    private var rate: SchedulerRate?
    private var queued: [String: SchedulerItem] = [:]
    private var queueOrder: [String] = []
    private var held: [String: SchedulerItem] = [:]
    private var heldOrder: [String] = []
    private var desired: [String: SchedulerItem] = [:]
    private var cache: [String: SchedulerItem] = [:]
    private var waiting: [SchedulerProposal] = []
    private var ready: [SchedulerReadyProposal] = []
    private var proposalOrdinal: UInt64 = 0
    private var tokens: Double?
    private var lastRefill: Double?
    private var retryAfter: Double?
    private var alignment: [String] = []

    public init() {}
    public var snapshot: SchedulerStateSnapshot {
        SchedulerStateSnapshot(owner: owner, inputOrdinal: inputOrdinal, rate: rate,
            queued: queueOrder.compactMap { queued[$0] }, withheld: heldOrder.compactMap { held[$0] },
            desired: desired, acceptedCache: cache, awaitingGate: waiting, awaitingReceipt: ready,
            tokens: tokens, lastRefill: lastRefill, retryAfter: retryAfter, persistentAlignmentDifferences: alignment)
    }

    /// Invalid input leaves the value unchanged, including its input ordinal.
    public mutating func apply(_ envelope: SchedulerEnvelope) throws -> SchedulerStep {
        var next = self
        let step = try next.reduce(envelope)
        self = next
        return step
    }

    private mutating func propose(_ item: SchedulerItem, cause: SchedulerProposalCause, into proposals: inout [SchedulerProposal]) throws {
        if cache[item.key] == item { return }
        guard proposalOrdinal < UInt64.max else { throw SchedulerCandidateError.invalid("proposal exhaustion") }
        proposalOrdinal += 1
        let proposal = SchedulerProposal(ordinal: proposalOrdinal, causeOrdinal: inputOrdinal, cause: cause, item: item)
        waiting.append(proposal); proposals.append(proposal)
    }
    private mutating func hold(_ item: SchedulerItem) {
        if held[item.key] == nil { heldOrder.append(item.key) }
        held[item.key] = item
    }
    private func finiteTime(_ at: Double) throws {
        guard at.isFinite else { throw SchedulerCandidateError.invalid("nonfinite time") }
    }

    private mutating func reduce(_ envelope: SchedulerEnvelope) throws -> SchedulerStep {
        guard !envelope.owner.isEmpty else { throw SchedulerCandidateError.invalid("owner") }
        guard schedulerPayloadFinite(envelope.context) else { throw SchedulerCandidateError.invalid("nonfinite context") }
        guard inputOrdinal < UInt64.max, envelope.ordinal == inputOrdinal + 1 else { throw SchedulerCandidateError.ordinalMismatch }
        if let owner, owner != envelope.owner { throw SchedulerCandidateError.ownerMismatch }
        var proposals: [SchedulerProposal] = [], removed: [String] = [], replaced: [String] = [], dedup: [String] = []
        var gates: [SchedulerGateDecision] = [], receipts: [SchedulerReceiptAssociation] = [], differences: [String] = []
        inputOrdinal = envelope.ordinal
        if case .initialize(let policy) = envelope.input {
            guard owner == nil else { throw SchedulerCandidateError.alreadyInitialized }
            switch policy {
            case .unlimited: tokens = nil
            case .bucket(let perSecond, let burst, let cooldown):
                guard perSecond.isFinite, perSecond > 0, burst > 0, burst <= 1_000_000,
                      cooldown.isFinite, cooldown >= 0 else { throw SchedulerCandidateError.invalid("rate policy") }
                tokens = Double(burst)
            }
            owner = envelope.owner; rate = policy
        } else {
            guard rate != nil else { throw SchedulerCandidateError.notInitialized }
            switch envelope.input {
            case .initialize: throw SchedulerCandidateError.alreadyInitialized
            case .enqueue(let item, let ingress):
                if case .derivedCallerRequeue(let cause) = ingress {
                    guard cause > 0, cause < inputOrdinal else { throw SchedulerCandidateError.invalid("requeue cause") }
                }
                if queued[item.key] == nil { queueOrder.append(item.key) } else { replaced.append(item.key) }
                queued[item.key] = item; desired[item.key] = item
            case .cancel(let key):
                if queued.removeValue(forKey: key) != nil { queueOrder.removeAll { $0 == key }; removed.append(key) }
                if held.removeValue(forKey: key) != nil { heldOrder.removeAll { $0 == key }; removed.append(key) }
            case .drain(let at):
                try finiteTime(at)
                if case .bucket(let perSecond, let burst, _) = rate {
                    if let previous = lastRefill {
                        let elapsed = at - previous
                        tokens = elapsed < 0 ? 0 : min(Double(burst), (tokens ?? 0) + elapsed * perSecond)
                    }
                    lastRefill = at
                }
                if retryAfter.map({ at < $0 }) != true {
                    let amount = min(queueOrder.count, tokens.map(Int.init) ?? queueOrder.count)
                    let keys = Array(queueOrder.prefix(amount)); queueOrder.removeFirst(amount)
                    for key in keys {
                        if let item = queued.removeValue(forKey: key) {
                            removed.append(key)
                            if cache[key] == item { dedup.append(key) }
                            else { try propose(item, cause: .drain, into: &proposals) }
                        }
                    }
                    if tokens != nil { tokens! -= Double(keys.count) }
                }
            case .failure(let at):
                try finiteTime(at)
                if case .bucket(_, _, let cooldown) = rate {
                    let deadline = at + cooldown
                    guard deadline.isFinite else { throw SchedulerCandidateError.invalid("cooldown overflow") }
                    retryAfter = deadline
                }
            case .clear:
                removed += queueOrder + heldOrder
                queued.removeAll(); queueOrder.removeAll(); held.removeAll(); heldOrder.removeAll(); cache.removeAll()
                lastRefill = nil; retryAfter = nil
                if case .bucket(_, let burst, _) = rate { tokens = Double(burst) }
                // Existing proposed/attempted operations retain receipt association.
            case .requestDirect(let item):
                desired[item.key] = item
                if cache[item.key] == item { dedup.append(item.key) }
                else { try propose(item, cause: .direct, into: &proposals) }
            case .changeStyle(let style, let projectionKey):
                guard !projectionKey.isEmpty else { throw SchedulerCandidateError.invalid("projection key") }
                desired[style.key] = style
                if cache[style.key] == style { desired[style.key] = style; dedup.append(style.key) }
                else {
                    try propose(style, cause: .style, into: &proposals)
                    cache.removeValue(forKey: projectionKey)
                    if let projection = desired[projectionKey] { try propose(projection, cause: .style, into: &proposals) }
                }
            case .invalidateCache(let keys):
                for key in keys { cache.removeValue(forKey: key) }
            case .refreshDesired(let order):
                for key in order {
                    if let item = desired[key] {
                        if cache[key] == item { dedup.append(key) }
                        else { try propose(item, cause: .refresh, into: &proposals) }
                    }
                }
            case .release(let key):
                if let item = held.removeValue(forKey: key) {
                    heldOrder.removeAll { $0 == key }; removed.append(key)
                    try propose(item, cause: .release, into: &proposals)
                }
            case .gate(let gate):
                guard schedulerPayloadFinite(SchedulerTraceCodec.planPayload(gate.dispatchPlan)),
                      schedulerPayloadFinite(SchedulerTraceCodec.planPayload(gate.proof.plan)),
                      schedulerPayloadFinite(gate.proof.nativeSnapshot), schedulerPayloadFinite(gate.currentScope),
                      schedulerPayloadFinite(gate.currentNativeSnapshot) else { throw SchedulerCandidateError.invalid("nonfinite gate") }
                guard let position = waiting.firstIndex(where: { $0.ordinal == gate.proposalOrdinal }) else { throw SchedulerCandidateError.proposalMissing }
                let proposal = waiting[position]
                guard proposal.item == gate.proposedItem else { throw SchedulerCandidateError.itemMismatch }
                guard gate.dispatchPlan.payload == proposal.item.value else { throw SchedulerCandidateError.planPayloadMismatch }
                guard case .object(let evidence) = gate.dispatchPlan.capturedEvidence,
                      evidence["queued_item"] == SchedulerTraceCodec.itemPayload(proposal.item), evidence["native_dispatch"] != nil else {
                    throw SchedulerCandidateError.queuedEvidenceMismatch
                }
                let result = FeedbackPreflight.evaluate(plan: gate.dispatchPlan, proof: gate.proof,
                    currentScope: gate.currentScope, currentNativeSnapshot: gate.currentNativeSnapshot)
                waiting.remove(at: position); gates.append(SchedulerGateDecision(proposalOrdinal: proposal.ordinal, result: result))
                if result == .permitted { ready.append(SchedulerReadyProposal(proposal: proposal, plan: gate.dispatchPlan)) }
                else { hold(proposal.item) }
            case .receipt(let receipt):
                guard schedulerPayloadFinite(SchedulerTraceCodec.planPayload(receipt.dispatchPlan)),
                      schedulerPayloadFinite(receipt.currentScope) else { throw SchedulerCandidateError.invalid("nonfinite receipt") }
                if let index = ready.firstIndex(where: { $0.proposal.item == receipt.item && $0.plan == receipt.dispatchPlan }) {
                    let matched = ready.remove(at: index)
                    let fact = FeedbackReceiptFact(plan: receipt.dispatchPlan, result: receipt.result)
                    let current = FeedbackReceiptEligibility.matchesCurrentScope(fact, currentScope: receipt.currentScope)
                    if fact.successfulSend && current { cache[receipt.item.key] = receipt.item }
                    if case .rejected = receipt.result, current { cache.removeValue(forKey: receipt.item.key) }
                    if case .notAttempted = receipt.result { hold(receipt.item) }
                    receipts.append(SchedulerReceiptAssociation(proposalOrdinal: matched.proposal.ordinal, receipt: receipt, currentScopeMatches: current))
                } else {
                    let message = "unmatched actual receipt at input " + String(inputOrdinal) + " key " + receipt.item.key
                    alignment.append(message); differences.append(message)
                    receipts.append(SchedulerReceiptAssociation(proposalOrdinal: nil, receipt: receipt, currentScopeMatches: nil))
                }
            }
        }
        return SchedulerStep(input: envelope, snapshot: snapshot, proposals: proposals, removedKeys: removed,
            replacedKeys: replaced, deduplicatedKeys: dedup, gateDecisions: gates, receipts: receipts, alignmentDifferences: differences)
    }
}
