import Foundation
import XCTest
import SurfaceDeviceContracts
import SurfaceFeedbackPlanning
import SurfaceDeviceConformance

final class SchedulerCandidateTests: XCTestCase {
    private func text(_ value: String) -> ScenarioPayload { .scalar(.text(value)) }
    private func item(_ key: String, value: String = "wire", scope: String = "scope") throws -> SchedulerItem {
        try SchedulerItem(key: key, value: text(value), scope: text(scope))
    }
    private struct Harness {
        var candidate = SchedulerCandidate()
        var ordinal: UInt64 = 0
        mutating func send(_ input: SchedulerInput) throws -> SchedulerStep {
            ordinal += 1
            return try candidate.apply(SchedulerEnvelope(owner: "owned-test", ordinal: ordinal, input: input))
        }
    }
    private func plan(_ item: SchedulerItem) throws -> SchedulerTracePlan {
        try SchedulerTracePlan(reference: text("existing-ref"), payload: item.value, origin: text("caller"), scope: item.scope,
            source: .hardware, endpointEvidence: EndpointProvenance(endpointID: "output", deviceID: nil, connectionGeneration: UInt64.max, transportOrigin: .localVirtual),
            capturedEvidence: SchedulerTraceCodec.queuedEvidence(for: item, nativeDispatch: .object(["name": text("label"), "qualification": .scalar(.null)])),
            targetID: item.key, affectedElements: [item.key], classification: .display, sideEffects: [], deliveryMode: .direct)
    }
    private func gate(_ proposal: SchedulerProposal, safety: NativeSafetyResult, scope: ScenarioPayload? = nil) throws -> SchedulerGateRecord {
        let plan = try plan(proposal.item), facts = text("fresh-native-facts")
        return SchedulerGateRecord(proposalOrdinal: proposal.ordinal, proposedItem: proposal.item, dispatchPlan: plan,
            proof: SchedulerTraceProof(plan: plan, nativeSnapshot: facts, authorization: .granted(directions: [.display]), safety: safety),
            currentScope: scope ?? proposal.item.scope, currentNativeSnapshot: facts)
    }

    func testQueueReplacementRetainsPositionAndCancellationReinsertAppends() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited))
        _ = try h.send(.enqueue(item("a", value: "old"), ingress: .externalRequest))
        _ = try h.send(.enqueue(item("b"), ingress: .externalRequest))
        let replaced = try h.send(.enqueue(item("a", value: "new"), ingress: .externalRequest))
        XCTAssertEqual(replaced.replacedKeys, ["a"])
        XCTAssertEqual(replaced.snapshot.queued.map(\.key), ["a", "b"])
        _ = try h.send(.cancel(key: "a"))
        _ = try h.send(.enqueue(item("a", value: "last"), ingress: .externalRequest))
        let drain = try h.send(.drain(at: 0))
        XCTAssertEqual(drain.proposals.map { $0.item.key }, ["b", "a"])
        XCTAssertEqual(drain.proposals.last?.item.value, text("last"))
    }

    func testNegativeReferenceDateDomainBackwardAndZeroCrossingAreRealInputs() throws {
        var h = Harness(); _ = try h.send(.initialize(.bucket(perSecond: 2, burst: 2, errorCooldown: 1)))
        let reference = Date(timeIntervalSince1970: 0).timeIntervalSinceReferenceDate
        XCTAssertLessThan(reference, 0)
        _ = try h.send(.enqueue(item("a"), ingress: .externalRequest))
        let first = try h.send(.drain(at: reference))
        XCTAssertEqual(first.proposals.count, 1); XCTAssertEqual(first.snapshot.lastRefill, reference)
        XCTAssertEqual(first.snapshot.tokens, 1)
        _ = try h.send(.enqueue(item("b"), ingress: .externalRequest))
        let backward = try h.send(.drain(at: reference - 1))
        XCTAssertEqual(backward.snapshot.tokens, 0); XCTAssertTrue(backward.proposals.isEmpty)
        let crossed = try h.send(.drain(at: 0))
        XCTAssertEqual(crossed.proposals.map { $0.item.key }, ["b"])
        XCTAssertEqual(crossed.snapshot.lastRefill, 0)
    }

    func testFailureSetsCooldownWithoutRefundOrAutomaticRequeue() throws {
        var h = Harness(); _ = try h.send(.initialize(.bucket(perSecond: 1, burst: 1, errorCooldown: 2)))
        _ = try h.send(.enqueue(item("a"), ingress: .externalRequest))
        let drain = try h.send(.drain(at: 0))
        _ = try h.send(.failure(at: 0))
        XCTAssertTrue(h.candidate.snapshot.queued.isEmpty)
        XCTAssertEqual(h.candidate.snapshot.tokens, 0)
        _ = try h.send(.enqueue(item("a"), ingress: .derivedCallerRequeue(causeOrdinal: drain.input.ordinal)))
        let blocked = try h.send(.drain(at: 1))
        XCTAssertTrue(blocked.proposals.isEmpty); XCTAssertEqual(blocked.snapshot.lastRefill, 1)
        XCTAssertEqual(blocked.snapshot.retryAfter, 2)
        XCTAssertEqual(try h.send(.drain(at: 2)).proposals.count, 1)
    }

    func testDedupRequiresActualMatchingAcceptedReceiptAndComparesWholeItem() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited))
        let value = try SchedulerItem(key: "a", value: .object(["wire": text("same-wire"), "id": text("one"), "at": .scalar(.number(1)), "actor": text("local")]), scope: text("scope"))
        let first = try h.send(.requestDirect(value)).proposals[0]
        XCTAssertEqual(try h.send(.requestDirect(value)).proposals.count, 1) // generated != accepted
        let resolution = try gate(first, safety: .passed)
        _ = try h.send(.gate(resolution))
        _ = try h.send(.receipt(SchedulerActualReceipt(item: value, dispatchPlan: resolution.dispatchPlan, result: .accepted, currentScope: value.scope)))
        let duplicate = try h.send(.requestDirect(value))
        XCTAssertTrue(duplicate.proposals.isEmpty); XCTAssertEqual(duplicate.deduplicatedKeys, ["a"])
        let changedMetadata = try SchedulerItem(key: "a", value: .object(["wire": text("same-wire"), "id": text("two"), "at": .scalar(.number(2)), "actor": text("remote")]), scope: text("scope"))
        XCTAssertEqual(try h.send(.requestDirect(changedMetadata)).proposals.count, 1)
    }

    func testNoGateNoAcceptedCacheAndUnmatchedReceiptDoesNotSeedState() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited)); let value = try item("a")
        _ = try h.send(.requestDirect(value))
        let receipt = SchedulerActualReceipt(item: value, dispatchPlan: try plan(value), result: .accepted, currentScope: value.scope)
        let unmatched = try h.send(.receipt(receipt))
        XCTAssertEqual(unmatched.alignmentDifferences.count, 1)
        XCTAssertTrue(unmatched.snapshot.acceptedCache.isEmpty)
        _ = try h.send(.clear)
        XCTAssertEqual(h.candidate.snapshot.persistentAlignmentDifferences, unmatched.alignmentDifferences)
        XCTAssertEqual(try h.send(.requestDirect(value)).proposals.count, 1)
    }

    func testNativeSafetyRejectedOwnProposalIsHeldAndReleaseUsesOwnLatestValue() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited))
        let first = try h.send(.requestDirect(item("a", value: "old"))).proposals[0]
        XCTAssertEqual(try h.send(.gate(gate(first, safety: .rejected(reason: "original-native-gate")))).snapshot.withheld.first?.value, text("old"))
        let latest = try h.send(.requestDirect(item("a", value: "new"))).proposals[0]
        _ = try h.send(.gate(gate(latest, safety: .rejected(reason: "original-native-gate"))))
        let released = try h.send(.release(key: "a"))
        XCTAssertEqual(released.proposals.first?.item.value, text("new"))
        XCTAssertTrue(released.snapshot.awaitingReceipt.isEmpty) // new proof is mandatory
    }

    func testStaleScopeAndWrongPlanCannotBecomePermittedProposal() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited))
        let proposal = try h.send(.requestDirect(item("a"))).proposals[0]
        let stale = try h.send(.gate(gate(proposal, safety: .passed, scope: text("new-scope"))))
        XCTAssertEqual(stale.gateDecisions.first?.result, .rejected(.staleScope))
        XCTAssertTrue(stale.snapshot.awaitingReceipt.isEmpty)
        let before = h.candidate.snapshot
        XCTAssertThrowsError(try h.candidate.apply(SchedulerEnvelope(owner: "owned-test", ordinal: h.ordinal + 1, input: .gate(gate(proposal, safety: .passed)))))
        XCTAssertEqual(h.candidate.snapshot, before)
    }

    func testStyleReprojectsOwnDesiredValueAndCallerRefreshOrderIsExplicit() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited))
        _ = try h.send(.requestDirect(item("projection", value: "position-42")))
        let style = try h.send(.changeStyle(style: item("style", value: "style-one"), projectionKey: "projection"))
        XCTAssertEqual(style.proposals.map { $0.item.key }, ["style", "projection"])
        XCTAssertEqual(style.proposals.last?.item.value, text("position-42"))
        let refresh = try h.send(.refreshDesired(order: ["style", "missing", "projection"]))
        XCTAssertEqual(refresh.proposals.map { $0.item.key }, ["style", "projection"])
    }

    func testInputOrdinalOwnerAndRestoreAttemptsFailWithoutMutation() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited)); let before = h.candidate.snapshot
        XCTAssertThrowsError(try h.candidate.apply(SchedulerEnvelope(owner: "other", ordinal: 2, input: .clear)))
        XCTAssertThrowsError(try h.candidate.apply(SchedulerEnvelope(owner: "owned-test", ordinal: 3, input: .clear)))
        XCTAssertThrowsError(try h.candidate.apply(SchedulerEnvelope(owner: "owned-test", ordinal: 1, input: .clear)))
        XCTAssertEqual(h.candidate.snapshot, before)
        let raw = Data("{\"schema_version\":1,\"owner\":\"owned-test\",\"ordinal\":\"2\",\"operation\":\"restore_native_state\",\"arguments\":{},\"context\":null}".utf8)
        XCTAssertThrowsError(try SchedulerTraceCodec.decodeInput(raw))
    }

    func testStrictCodecPreservesNullableOpaqueFieldsAndLargeGenerationStrings() throws {
        let value = try SchedulerItem(key: "a", value: .object(["unknown": .scalar(.null), "explicit": text("unknown"), "generation": text(String(UInt64.max))]), scope: .scalar(.null))
        let envelope = SchedulerEnvelope(owner: "owned", ordinal: UInt64.max, input: .enqueue(value, ingress: .derivedCallerRequeue(causeOrdinal: UInt64.max - 1)))
        let encoded = try SchedulerTraceCodec.encodeInput(envelope)
        let decoded = try SchedulerTraceCodec.decodeInput(encoded)
        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(try SchedulerTraceCodec.encodeInput(decoded), encoded)
    }

    func testGateAndReceiptCodecRoundTripsCompleteProofAndNativeEvidence() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited))
        let proposal = try h.send(.requestDirect(item("a"))).proposals[0]
        let record = try gate(proposal, safety: .rejected(reason: "native-check"))
        let input = SchedulerEnvelope(owner: "owned", ordinal: 3, input: .gate(record))
        XCTAssertEqual(try SchedulerTraceCodec.decodeInput(SchedulerTraceCodec.encodeInput(input)), input)
        let receipt = SchedulerEnvelope(owner: "owned", ordinal: 4, input: .receipt(SchedulerActualReceipt(item: proposal.item, dispatchPlan: record.dispatchPlan, result: .rejected(reason: "actual-boundary"), currentScope: text("new"))))
        XCTAssertEqual(try SchedulerTraceCodec.decodeInput(SchedulerTraceCodec.encodeInput(receipt)), receipt)
    }

    func testStrictCodecRejectsDuplicateUnknownMissingTypeAndNonfiniteInput() throws {
        let cases = [
            "{\"schema_version\":1,\"owner\":\"a\",\"owner\":\"b\",\"ordinal\":\"1\",\"operation\":\"clear\",\"arguments\":{},\"context\":null}",
            "{\"schema_version\":1,\"owner\":\"a\",\"\\u006fwner\":\"b\",\"ordinal\":\"1\",\"operation\":\"clear\",\"arguments\":{},\"context\":null}",
            "{\"schema_version\":1,\"owner\":\"a\",\"ordinal\":1,\"operation\":\"clear\",\"arguments\":{},\"context\":null}",
            "{\"schema_version\":1,\"owner\":\"a\",\"ordinal\":\"01\",\"operation\":\"clear\",\"arguments\":{},\"context\":null}",
            "{\"schema_version\":1,\"owner\":\"a\",\"ordinal\":\"1\",\"operation\":\"clear\",\"arguments\":{\"native_pending\":[]},\"context\":null}",
            "{\"schema_version\":1,\"owner\":\"a\",\"ordinal\":\"1\",\"operation\":\"drain\",\"arguments\":{\"at\":1e999},\"context\":null}"
        ]
        for raw in cases { XCTAssertThrowsError(try SchedulerTraceCodec.decodeInput(Data(raw.utf8))) }
        var h = Harness(); _ = try h.send(.initialize(.unlimited)); let step = try h.send(.clear)
        XCTAssertThrowsError(try SchedulerTraceCodec.decodeInput(SchedulerTraceCodec.encodeStep(step)))
        XCTAssertThrowsError(try SchedulerTraceCodec.encodeInput(SchedulerEnvelope(owner: "owned", ordinal: 1, input: .drain(at: .nan))))
    }

    func testRejectedTransportAndOldScopeSuccessDoNotPopulateCurrentCache() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited)); let value = try item("a")
        let first = try h.send(.requestDirect(value)).proposals[0], firstGate = try gate(first, safety: .passed)
        _ = try h.send(.gate(firstGate))
        _ = try h.send(.receipt(SchedulerActualReceipt(item: value, dispatchPlan: firstGate.dispatchPlan, result: .rejected(reason: "failed"), currentScope: value.scope)))
        XCTAssertTrue(h.candidate.snapshot.acceptedCache.isEmpty)
        let next = try h.send(.requestDirect(value)).proposals[0], nextGate = try gate(next, safety: .passed)
        _ = try h.send(.gate(nextGate))
        let old = try h.send(.receipt(SchedulerActualReceipt(item: value, dispatchPlan: nextGate.dispatchPlan, result: .accepted, currentScope: text("new-scope"))))
        XCTAssertEqual(old.receipts.first?.currentScopeMatches, false)
        XCTAssertTrue(old.snapshot.acceptedCache.isEmpty)
    }

    func testReplayFromInputsOnlyReproducesEveryCompleteStateAndOutput() throws {
        var live = Harness(); var inputs: [Data] = [], outputs: [Data] = []
        for input in [SchedulerInput.initialize(.bucket(perSecond: 3, burst: 2, errorCooldown: 1)),
                      .enqueue(try item("a"), ingress: .externalRequest), .enqueue(try item("b"), ingress: .externalRequest),
                      .drain(at: -1), .failure(at: -1), .clear] {
            let step = try live.send(input)
            inputs.append(try SchedulerTraceCodec.encodeInput(step.input)); outputs.append(try SchedulerTraceCodec.encodeStep(step))
        }
        var replay = SchedulerCandidate()
        for (index, data) in inputs.enumerated() {
            let step = try replay.apply(SchedulerTraceCodec.decodeInput(data))
            XCTAssertEqual(try SchedulerTraceCodec.encodeStep(step), outputs[index])
        }
    }

    func testExactDiffDetectsOrderDroppedReplacementNullAndCachePhaseMutations() throws {
        let first = try item("a", value: "new"), second = try item("b")
        let reference = ScenarioPayload.object(["items": .array([SchedulerTraceCodec.itemPayload(first), SchedulerTraceCodec.itemPayload(second)]), "cache": .scalar(.null)])
        let reordered = ScenarioPayload.object(["items": .array([SchedulerTraceCodec.itemPayload(second), SchedulerTraceCodec.itemPayload(first)]), "cache": .scalar(.null)])
        XCTAssertFalse(SchedulerTraceDiff.compare(reference: reference, candidate: reordered).isEmpty)
        let stale = ScenarioPayload.object(["items": .array([SchedulerTraceCodec.itemPayload(try item("a", value: "old")), SchedulerTraceCodec.itemPayload(second)])])
        let differences = SchedulerTraceDiff.compare(reference: reference, candidate: stale)
        XCTAssertTrue(differences.contains { $0.path == "$.cache" && $0.candidate == nil })
        XCTAssertTrue(differences.contains { $0.path == "$.items[0].value" })
        XCTAssertTrue(SchedulerTraceDiff.compare(reference: reference, candidate: reference).isEmpty)
    }

    func testBadPolicyAndNonfiniteTimeRejectWithoutStateOrOrdinalMutation() throws {
        var candidate = SchedulerCandidate()
        for rate in [SchedulerRate.bucket(perSecond: 0, burst: 1, errorCooldown: 1),
                     .bucket(perSecond: 1, burst: 0, errorCooldown: 1), .bucket(perSecond: 1, burst: 1, errorCooldown: -1),
                     .bucket(perSecond: .infinity, burst: 1, errorCooldown: 1)] {
            XCTAssertThrowsError(try candidate.apply(SchedulerEnvelope(owner: "owned", ordinal: 1, input: .initialize(rate))))
            XCTAssertNil(candidate.snapshot.owner); XCTAssertEqual(candidate.snapshot.inputOrdinal, 0)
        }
        _ = try candidate.apply(SchedulerEnvelope(owner: "owned", ordinal: 1, input: .initialize(.unlimited)))
        let before = candidate.snapshot
        XCTAssertThrowsError(try candidate.apply(SchedulerEnvelope(owner: "owned", ordinal: 2, input: .drain(at: .nan))))
        XCTAssertThrowsError(try candidate.apply(SchedulerEnvelope(owner: "owned", ordinal: 2, input: .failure(at: .infinity))))
        XCTAssertEqual(candidate.snapshot, before)
    }

    func testOtherItemPayloadAndNativeProofCannotResolveOwnProposal() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited)); let proposed = try h.send(.requestDirect(item("a"))).proposals[0]
        let correct = try gate(proposed, safety: .passed), other = try item("b")
        let before = h.candidate.snapshot
        let substituted = SchedulerGateRecord(proposalOrdinal: proposed.ordinal, proposedItem: other,
            dispatchPlan: correct.dispatchPlan, proof: correct.proof, currentScope: correct.currentScope, currentNativeSnapshot: correct.currentNativeSnapshot)
        XCTAssertThrowsError(try h.candidate.apply(SchedulerEnvelope(owner: "owned-test", ordinal: h.ordinal + 1, input: .gate(substituted))))
        XCTAssertEqual(h.candidate.snapshot, before)
        let wrongProof = SchedulerGateRecord(proposalOrdinal: proposed.ordinal, proposedItem: proposed.item,
            dispatchPlan: correct.dispatchPlan,
            proof: SchedulerTraceProof(plan: try plan(other), nativeSnapshot: correct.currentNativeSnapshot, authorization: .granted(directions: [.display]), safety: .passed),
            currentScope: correct.currentScope, currentNativeSnapshot: correct.currentNativeSnapshot)
        XCTAssertEqual(try h.send(.gate(wrongProof)).gateDecisions.first?.result, .rejected(.planMismatch))
        XCTAssertTrue(h.candidate.snapshot.awaitingReceipt.isEmpty)
    }

    func testDerivedCallerRequeueKeepsCausalityAndDoesNotRealignDivergence() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited)); let value = try item("a")
        let request = try h.send(.requestDirect(value))
        let unmatched = try h.send(.receipt(SchedulerActualReceipt(item: value, dispatchPlan: try plan(value), result: .accepted, currentScope: value.scope)))
        let requeue = try h.send(.enqueue(value, ingress: .derivedCallerRequeue(causeOrdinal: request.input.ordinal)))
        XCTAssertEqual(requeue.snapshot.persistentAlignmentDifferences, unmatched.alignmentDifferences)
        XCTAssertEqual(try SchedulerTraceCodec.decodeInput(SchedulerTraceCodec.encodeInput(requeue.input)).input,
                       .enqueue(value, ingress: .derivedCallerRequeue(causeOrdinal: request.input.ordinal)))
    }

    func testDrainingAnOldQueuedRequestDoesNotRewriteNewerDesiredProjection() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited))
        _ = try h.send(.enqueue(item("projection", value: "old-queued"), ingress: .externalRequest))
        _ = try h.send(.requestDirect(item("projection", value: "new-direct")))
        XCTAssertEqual(try h.send(.drain(at: 0)).proposals.first?.item.value, text("old-queued"))
        let style = try h.send(.changeStyle(style: item("style"), projectionKey: "projection"))
        XCTAssertEqual(style.proposals.last?.item.value, text("new-direct"))
        XCTAssertEqual(style.snapshot.desired["projection"]?.value, text("new-direct"))
    }

    func testSuccessfulCacheCannotDeduplicateTheSameValueFromAnotherScope() throws {
        var h = Harness(); _ = try h.send(.initialize(.unlimited)); let old = try item("a", scope: "old")
        let proposal = try h.send(.requestDirect(old)).proposals[0], resolved = try gate(proposal, safety: .passed)
        _ = try h.send(.gate(resolved))
        _ = try h.send(.receipt(SchedulerActualReceipt(item: old, dispatchPlan: resolved.dispatchPlan, result: .accepted, currentScope: old.scope)))
        let changed = try SchedulerItem(key: old.key, value: old.value, scope: text("new"))
        XCTAssertEqual(try h.send(.requestDirect(changed)).proposals.count, 1)
    }
}
