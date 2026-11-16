import XCTest
import SurfaceDeviceContracts
import SurfaceFeedbackPlanning

final class FeedbackPlanningTests: XCTestCase {
    private struct Wire: Equatable, Sendable { var operation: String; var value: Int }
    private enum Origin: Equatable, Sendable { case local, remote, system }
    private struct Scope: Equatable, Sendable {
        var input: String? = "input"
        var output: String? = "output"
        var connection: UInt64 = 3
        var binding = "binding"
        var hardwareMode = true
    }
    private struct RawEndpoint: Equatable, Sendable {
        var name: String? = "label"
        var qualification: String? = "software-only"
        var origin: EndpointTransportOrigin? = nil
    }
    private struct Evidence: Equatable, Sendable {
        var endpoint: RawEndpoint? = RawEndpoint()
        var legacySource: String? = nil
        var nativeAt: Double? = nil
    }
    private struct NativeSnapshot: Equatable, Sendable {
        var policyRevision: UInt64 = 4
        var observationRevision: UInt64 = 7
    }
    private typealias Plan = FeedbackPlan<Wire, Origin, Scope, String, Evidence>
    private typealias Proof = FeedbackProof<Plan, NativeSnapshot>

    private func endpoint(id: String? = "output", device: String? = nil, generation: UInt64 = 3,
                          origin: EndpointTransportOrigin = .unknown) throws -> EndpointProvenance {
        try EndpointProvenance(endpointID: id, deviceID: device, connectionGeneration: generation, transportOrigin: origin)
    }
    private func plan(reference: String = "existing-reference", payload: Wire = Wire(operation: "encoded", value: 42),
                      origin: Origin = .local, scope: Scope = Scope(), source: DeviceSource = .hardware,
                      endpoint: EndpointProvenance? = nil, evidence: Evidence = Evidence(), target: String = "target",
                      affected: Set<String> = ["element"], classification: EffectClassification = .display,
                      sideEffects: Set<EffectDirection> = [], mode: FeedbackDeliveryMode = .direct) throws -> Plan {
        try Plan(reference: reference, payload: payload, origin: origin, scope: scope, source: source,
                 endpointEvidence: endpoint ?? self.endpoint(), capturedEvidence: evidence, targetID: target,
                 affectedElements: affected, classification: classification, sideEffects: sideEffects, deliveryMode: mode)
    }
    private func proof(_ plan: Plan, authorization: PlanAuthorization, safety: NativeSafetyResult,
                       snapshot: NativeSnapshot) -> Proof {
        Proof(plan: plan, nativeSnapshot: snapshot, authorization: authorization, safety: safety)
    }
    private func grantedProof(_ plan: Plan) -> Proof {
        proof(plan, authorization: .granted(directions: plan.requiredDirections), safety: .passed, snapshot: NativeSnapshot())
    }
    private func evaluate(_ plan: Plan, _ proof: Proof, scope: Scope = Scope(), snapshot: NativeSnapshot = NativeSnapshot()) -> FeedbackPreflight {
        FeedbackPreflight.evaluate(plan: plan, proof: proof, currentScope: scope, currentNativeSnapshot: snapshot)
    }

    func testExactGrantAndFreshNativeProofPermitTheSpecificPlan() throws {
        let plan = try plan()
        XCTAssertEqual(evaluate(plan, grantedProof(plan)), .permitted)
    }

    func testEveryPlanFieldMutationRejectsEvenWhenReferenceIsReused() throws {
        let original = try plan(), bound = grantedProof(original)
        let changes = try [
            plan(reference: "different"), plan(payload: Wire(operation: "other", value: 42)),
            plan(payload: Wire(operation: "encoded", value: 43)), plan(origin: .remote),
            plan(scope: Scope(binding: "new")), plan(source: .simulation),
            plan(endpoint: endpoint(id: nil)), plan(endpoint: endpoint(device: "device")),
            plan(endpoint: endpoint(generation: 4)), plan(endpoint: endpoint(origin: .localVirtual)),
            plan(evidence: Evidence(legacySource: "known")), plan(evidence: Evidence(nativeAt: 1)),
            plan(target: "other"), plan(affected: ["other"]), plan(classification: .query),
            plan(sideEffects: [.mechanism]), plan(mode: .coalescible)
        ]
        for changed in changes {
            XCTAssertEqual(evaluate(changed, bound), .rejected(.planMismatch))
        }
        XCTAssertEqual(original.reference, changes[1].reference)
    }

    func testFullNativeEvidenceIsBoundButCosmeticChangesDoNotEnterSemanticScope() throws {
        let original = try plan(), bound = grantedProof(original)
        let changes = [
            Evidence(endpoint: RawEndpoint(name: "renamed")),
            Evidence(endpoint: RawEndpoint(qualification: "other")),
            Evidence(endpoint: nil),
            Evidence(endpoint: RawEndpoint(origin: .unknown)),
            Evidence(legacySource: "unknown"), Evidence(nativeAt: 0)
        ]
        for evidence in changes {
            let changed = try plan(evidence: evidence)
            XCTAssertEqual(changed.scope, original.scope)
            XCTAssertEqual(changed.endpointEvidence, original.endpointEvidence)
            XCTAssertNotEqual(changed.capturedEvidence, original.capturedEvidence)
            XCTAssertEqual(evaluate(changed, bound), .rejected(.planMismatch))
            XCTAssertEqual(evaluate(original, bound, scope: changed.scope), .permitted)
            XCTAssertEqual(evaluate(changed, grantedProof(changed)), .permitted)
        }
    }

    func testNilNativeObjectAndExplicitUnknownObjectRemainDifferent() throws {
        let absent = try plan(evidence: Evidence(endpoint: nil))
        let explicitUnknown = try plan(evidence: Evidence(endpoint: RawEndpoint(name: nil, qualification: nil, origin: .unknown)))
        XCTAssertEqual(absent.scope, explicitUnknown.scope)
        XCTAssertNotEqual(absent.capturedEvidence, explicitUnknown.capturedEvidence)
        XCTAssertEqual(evaluate(explicitUnknown, grantedProof(absent)), .rejected(.planMismatch))
        XCTAssertNil(absent.capturedEvidence.endpoint)
    }

    func testEverySemanticScopeDimensionInvalidatesAnOldProof() throws {
        let plan = try plan(), bound = grantedProof(plan)
        for current in [Scope(input: nil), Scope(output: nil), Scope(connection: 4), Scope(binding: "new"), Scope(hardwareMode: false)] {
            XCTAssertEqual(evaluate(plan, bound, scope: current), .rejected(.staleScope))
        }
    }

    func testFreshNativeSnapshotIsRequiredIndependentlyFromLifecycleScope() throws {
        let plan = try plan(), bound = grantedProof(plan)
        XCTAssertEqual(evaluate(plan, bound, snapshot: NativeSnapshot(policyRevision: 5)), .rejected(.staleNativeProof))
        XCTAssertEqual(evaluate(plan, bound, snapshot: NativeSnapshot(observationRevision: 8)), .rejected(.staleNativeProof))
    }

    func testManagementAndMechanismRequireTheirExactUnion() throws {
        let plan = try plan(classification: .management, sideEffects: [.mechanism])
        XCTAssertEqual(plan.requiredDirections, [.management, .mechanism])
        let partial = proof(plan, authorization: .granted(directions: [.mechanism]), safety: .passed, snapshot: NativeSnapshot())
        XCTAssertEqual(evaluate(plan, partial), .rejected(.wrongDirections(missing: [.management], surplus: [])))
        XCTAssertEqual(evaluate(plan, grantedProof(plan)), .permitted)
        let surplus = proof(plan, authorization: .granted(directions: [.management, .mechanism, .display]), safety: .passed, snapshot: NativeSnapshot())
        XCTAssertEqual(evaluate(plan, surplus), .rejected(.wrongDirections(missing: [], surplus: [.display])))
    }

    func testMixedMissingAndSurplusDirectionsAreBothReported() throws {
        let plan = try plan(classification: .management, sideEffects: [.mechanism])
        let bound = proof(plan, authorization: .granted(directions: [.query]), safety: .passed, snapshot: NativeSnapshot())
        XCTAssertEqual(evaluate(plan, bound), .rejected(.wrongDirections(missing: [.management, .mechanism], surplus: [.query])))
    }

    func testHardwareSourceAndPhysicalProvenanceGrantNothing() throws {
        let plan = try plan(endpoint: endpoint(origin: .physicalUSB))
        let denied = proof(plan, authorization: .denied(reason: "revoked"), safety: .passed, snapshot: NativeSnapshot())
        XCTAssertEqual(evaluate(plan, denied), .rejected(.authorizationDenied(reason: "revoked")))
        let unsafe = proof(plan, authorization: .granted(directions: [.display]), safety: .rejected(reason: "native-refused"), snapshot: NativeSnapshot())
        XCTAssertEqual(evaluate(plan, unsafe), .rejected(.nativeRejected(reason: "native-refused")))
    }

    func testPermanentMockRightsCannotTransferIntoHardwareModeAtVirtualEndpoints() throws {
        let mockScope = Scope(hardwareMode: false)
        let mock = try plan(scope: mockScope, source: .simulation, endpoint: endpoint(origin: .localVirtual),
                            classification: .management, sideEffects: [.mechanism])
        let bound = grantedProof(mock)
        XCTAssertEqual(evaluate(mock, bound, scope: mockScope), .permitted)
        XCTAssertEqual(evaluate(mock, bound, scope: Scope(hardwareMode: true)), .rejected(.staleScope))
        let rehearsal = try plan(source: .hardware, endpoint: endpoint(origin: .localVirtual),
                                 classification: .management, sideEffects: [.mechanism])
        XCTAssertEqual(evaluate(rehearsal, bound), .rejected(.planMismatch))
        let nativeRefusal = proof(rehearsal, authorization: .denied(reason: "display-only-vocabulary"),
                                  safety: .rejected(reason: "not-an-existing-local-explicit-command"), snapshot: NativeSnapshot())
        XCTAssertEqual(evaluate(rehearsal, nativeRefusal), .rejected(.authorizationDenied(reason: "display-only-vocabulary")))
    }

    func testStageAuthorizationSufficiencyCannotReplaceFinalSafetyOrFullUnion() throws {
        let plan = try plan(classification: .management, sideEffects: [.mechanism])
        let partial = PlanAuthorization.granted(directions: [.mechanism])
        XCTAssertEqual(FeedbackAuthorizationCheck.evaluate(requirements: [.mechanism], authorization: partial), .sufficient)
        XCTAssertEqual(evaluate(plan, proof(plan, authorization: partial, safety: .passed, snapshot: NativeSnapshot())),
                       .rejected(.wrongDirections(missing: [.management], surplus: [])))
        let full = PlanAuthorization.granted(directions: [.management, .mechanism])
        XCTAssertEqual(FeedbackAuthorizationCheck.evaluate(requirements: plan.requiredDirections, authorization: full), .sufficient)
        XCTAssertEqual(evaluate(plan, proof(plan, authorization: full, safety: .rejected(reason: "native-touch-gate"), snapshot: NativeSnapshot())),
                       .rejected(.nativeRejected(reason: "native-touch-gate")))
        XCTAssertEqual(evaluate(plan, proof(plan, authorization: full, safety: .passed, snapshot: NativeSnapshot()), scope: Scope(connection: 9)), .rejected(.staleScope))
        XCTAssertEqual(evaluate(plan, proof(plan, authorization: full, safety: .passed, snapshot: NativeSnapshot()), snapshot: NativeSnapshot(policyRevision: 9)), .rejected(.staleNativeProof))
        XCTAssertEqual(plan.requiredDirections, [.management, .mechanism])
    }

    func testStageDenialAndNarrowingPreserveNativeReasons() {
        XCTAssertEqual(FeedbackAuthorizationCheck.evaluate(requirements: [.display], authorization: .denied(reason: "native-policy")),
                       .rejected(.authorizationDenied(reason: "native-policy")))
        XCTAssertEqual(FeedbackAuthorizationCheck.evaluate(requirements: [.display], authorization: .granted(directions: [.display, .management])),
                       .rejected(.wrongDirections(missing: [], surplus: [.management])))
    }

    func testEmptyStageRequirementsDoNotShrinkTheFullPlan() throws {
        let plan = try plan()
        XCTAssertEqual(FeedbackAuthorizationCheck.evaluate(requirements: [], authorization: .granted(directions: [])), .sufficient)
        let bound = proof(plan, authorization: .granted(directions: []), safety: .passed, snapshot: NativeSnapshot())
        XCTAssertEqual(evaluate(plan, bound), .rejected(.wrongDirections(missing: [.display], surplus: [])))
    }

    func testSchedulingChoiceIsNotAPermitAndDirectLeavesCoalescingBypassed() throws {
        let direct = try plan(mode: .direct), coalescible = try plan(mode: .coalescible)
        XCTAssertEqual(direct.dispatchChoice(canCoalesce: true), .send)
        XCTAssertEqual(direct.dispatchChoice(canCoalesce: false), .send)
        XCTAssertEqual(coalescible.dispatchChoice(canCoalesce: true), .enqueue)
        XCTAssertEqual(coalescible.dispatchChoice(canCoalesce: false), .send)
        let denied = proof(direct, authorization: .denied(reason: "no-right"), safety: .passed, snapshot: NativeSnapshot())
        XCTAssertEqual(evaluate(direct, denied), .rejected(.authorizationDenied(reason: "no-right")))
    }

    func testEmptyTargetOrAffectedIdentifierIsRejected() throws {
        XCTAssertThrowsError(try plan(target: ""))
        XCTAssertThrowsError(try plan(affected: [""]))
        XCTAssertNoThrow(try plan(affected: [])) // Unknown affected set is not invented.
    }

    func testPreflightRejectionAndNoAttemptDoNotCreateTransmissionOutcome() throws {
        let plan = try plan()
        let notAttempted = FeedbackReceiptFact(plan: plan, result: .notAttempted(reason: "preflight-denied"))
        XCTAssertFalse(notAttempted.hasTransportAttempt)
        XCTAssertFalse(notAttempted.successfulSend)
        XCTAssertNil(notAttempted.transmissionOutcome)
        XCTAssertFalse(FeedbackReceiptEligibility.acceptedInCurrentScope(notAttempted, currentScope: plan.scope))
    }

    func testRejectedTransportAttemptIsNotASuccessfulSend() throws {
        let plan = try plan()
        let receipt = FeedbackReceiptFact(plan: plan, result: .rejected(reason: "transport-refused"))
        XCTAssertTrue(receipt.hasTransportAttempt)
        XCTAssertFalse(receipt.successfulSend)
        XCTAssertEqual(receipt.transmissionOutcome, .rejected(reason: "transport-refused"))
        XCTAssertTrue(FeedbackReceiptEligibility.matchesCurrentScope(receipt, currentScope: plan.scope))
        XCTAssertFalse(FeedbackReceiptEligibility.acceptedInCurrentScope(receipt, currentScope: plan.scope))
    }

    func testAcceptedOldScopeRemainsSuccessButCannotBookkeepNewCanonicalState() throws {
        let plan = try plan()
        let receipt = FeedbackReceiptFact(plan: plan, result: .accepted)
        XCTAssertTrue(receipt.hasTransportAttempt)
        XCTAssertTrue(receipt.successfulSend)
        XCTAssertEqual(receipt.transmissionOutcome, .accepted)
        XCTAssertTrue(FeedbackReceiptEligibility.acceptedInCurrentScope(receipt, currentScope: plan.scope))
        let afterCallback = Scope(connection: 12, binding: "new")
        XCTAssertFalse(FeedbackReceiptEligibility.matchesCurrentScope(receipt, currentScope: afterCallback))
        XCTAssertFalse(FeedbackReceiptEligibility.acceptedInCurrentScope(receipt, currentScope: afterCallback))
        XCTAssertTrue(receipt.successfulSend)
        XCTAssertEqual(receipt.plan.endpointEvidence.connectionGeneration, 3)
    }

    func testReceiptEligibilityDoesNotRetroactivelyRecheckPhysicalProofFacts() throws {
        let plan = try plan(), receipt = FeedbackReceiptFact(plan: try self.plan(), result: .accepted)
        let newerPhysicalFact = NativeSnapshot(observationRevision: 200)
        XCTAssertEqual(evaluate(plan, grantedProof(plan), snapshot: newerPhysicalFact), .rejected(.staleNativeProof))
        XCTAssertTrue(FeedbackReceiptEligibility.acceptedInCurrentScope(receipt, currentScope: plan.scope))
        // The native caller applies its old revision cutoff to preserve newer input.
    }

    func testBatchSummaryDoesNotTreatEmptyDeferredOrPartialAsAllAccepted() {
        XCTAssertFalse(FeedbackReceiptSummary([]).allAccepted)
        XCTAssertFalse(FeedbackReceiptSummary([.notAttempted(reason: "queued")]).anyAccepted)
        let partial = FeedbackReceiptSummary([.accepted, .rejected(reason: "failed"), .notAttempted(reason: "scope-changed")])
        XCTAssertEqual(partial.attemptCount, 2)
        XCTAssertEqual(partial.acceptedCount, 1)
        XCTAssertEqual(partial.rejectedCount, 1)
        XCTAssertEqual(partial.notAttemptedCount, 1)
        XCTAssertTrue(partial.anyAccepted)
        XCTAssertFalse(partial.allAccepted)
        XCTAssertTrue(FeedbackReceiptSummary([.accepted, .accepted]).allAccepted)
    }

    func testPlansProofsAndReceiptsAreSendableValueCopies() throws {
        func sendable<T: Sendable>(_ value: T) -> T { value }
        let original = try plan(), bound = sendable(grantedProof(original))
        let receipt = sendable(FeedbackReceiptFact(plan: original, result: .accepted))
        XCTAssertEqual(sendable(original), original)
        XCTAssertEqual(bound.plan, original)
        XCTAssertEqual(receipt.plan.capturedEvidence, original.capturedEvidence)
    }
}
