import Foundation
import SurfaceDeviceContracts
import SurfaceFeedbackPlanning

/// Closed trace protocol. Opaque native values are retained whole; UInt64 fields
/// use canonical decimal strings. Data is caller-owned; no files are opened.
public enum SchedulerTraceCodec: Sendable {
    private typealias Object = [String: ScenarioPayload]
    private static func s(_ value: String) -> ScenarioPayload { .scalar(.text(value)) }
    private static func n(_ value: Double) -> ScenarioPayload { .scalar(.number(value)) }
    private static let null = ScenarioPayload.scalar(.null)
    private static func object(_ value: ScenarioPayload) throws -> Object {
        guard case .object(let object) = value else { throw SchedulerCandidateError.invalid("object") }; return object
    }
    private static func text(_ value: ScenarioPayload?) throws -> String {
        guard case .scalar(.text(let text)) = value else { throw SchedulerCandidateError.invalid("text") }; return text
    }
    private static func number(_ value: ScenarioPayload?) throws -> Double {
        guard case .scalar(.number(let value)) = value, value.isFinite else { throw SchedulerCandidateError.invalid("number") }; return value
    }
    private static func uint(_ value: ScenarioPayload?) throws -> UInt64 {
        let value = try text(value)
        guard let number = UInt64(value), String(number) == value else { throw SchedulerCandidateError.invalid("decimal cursor") }; return number
    }
    private static func array(_ value: ScenarioPayload?) throws -> [ScenarioPayload] {
        guard case .array(let values) = value else { throw SchedulerCandidateError.invalid("array") }; return values
    }
    private static func strings(_ value: ScenarioPayload?) throws -> [String] { try array(value).map { try text($0) } }
    private static func optionalText(_ value: ScenarioPayload?) throws -> String? {
        guard let value else { throw SchedulerCandidateError.invalid("missing nullable field") }
        if value == null { return nil }; return try text(value)
    }
    private static func keys(_ object: Object, _ expected: Set<String>) throws {
        guard Set(object.keys) == expected else { throw SchedulerCandidateError.invalid("closed fields") }
    }
    private static func directions(_ value: ScenarioPayload?) throws -> Set<EffectDirection> {
        let raw = try strings(value)
        let parsed = try raw.map { name -> EffectDirection in
            guard let direction = EffectDirection(rawValue: name) else { throw SchedulerCandidateError.invalid("direction") }; return direction
        }
        guard Set(parsed).count == parsed.count else { throw SchedulerCandidateError.invalid("duplicate direction") }; return Set(parsed)
    }
    private static func directionPayload(_ values: Set<EffectDirection>) -> ScenarioPayload { .array(values.map(\.rawValue).sorted().map(s)) }

    public static func itemPayload(_ item: SchedulerItem) -> ScenarioPayload {
        .object(["key": s(item.key), "value": item.value, "scope": item.scope])
    }
    public static func queuedEvidence(for item: SchedulerItem, nativeDispatch: ScenarioPayload) -> ScenarioPayload {
        .object(["queued_item": itemPayload(item), "native_dispatch": nativeDispatch])
    }
    private static func item(_ value: ScenarioPayload) throws -> SchedulerItem {
        let value = try object(value); try keys(value, ["key", "value", "scope"])
        return try SchedulerItem(key: text(value["key"]), value: value["value"]!, scope: value["scope"]!)
    }
    private static func ratePayload(_ rate: SchedulerRate) -> ScenarioPayload {
        switch rate {
        case .unlimited: .object(["kind": s("unlimited")])
        case .bucket(let perSecond, let burst, let cooldown): .object(["kind": s("bucket"), "per_second": n(perSecond), "burst": n(Double(burst)), "error_cooldown": n(cooldown)])
        }
    }
    private static func rate(_ value: ScenarioPayload) throws -> SchedulerRate {
        let value = try object(value)
        switch try text(value["kind"]) {
        case "unlimited": try keys(value, ["kind"]); return .unlimited
        case "bucket":
            try keys(value, ["kind", "per_second", "burst", "error_cooldown"])
            guard let burst = Int(exactly: try number(value["burst"])) else { throw SchedulerCandidateError.invalid("burst") }
            return .bucket(perSecond: try number(value["per_second"]), burst: burst, errorCooldown: try number(value["error_cooldown"]))
        default: throw SchedulerCandidateError.invalid("rate kind")
        }
    }
    private static func endpointPayload(_ value: EndpointProvenance) -> ScenarioPayload {
        .object(["endpoint_id": value.endpointID.map(s) ?? null, "device_id": value.deviceID.map(s) ?? null,
                 "connection_generation": s(String(value.connectionGeneration)), "origin": s(value.transportOrigin.rawValue)])
    }
    private static func endpoint(_ value: ScenarioPayload) throws -> EndpointProvenance {
        let value = try object(value); try keys(value, ["endpoint_id", "device_id", "connection_generation", "origin"])
        guard let origin = EndpointTransportOrigin(rawValue: try text(value["origin"])) else { throw SchedulerCandidateError.invalid("origin") }
        return try EndpointProvenance(endpointID: optionalText(value["endpoint_id"]), deviceID: optionalText(value["device_id"]), connectionGeneration: uint(value["connection_generation"]), transportOrigin: origin)
    }
    public static func planPayload(_ plan: SchedulerTracePlan) -> ScenarioPayload {
        .object(["reference": plan.reference, "payload": plan.payload, "origin": plan.origin, "scope": plan.scope,
            "source": s(plan.source.rawValue), "endpoint": endpointPayload(plan.endpointEvidence), "evidence": plan.capturedEvidence,
            "target": s(plan.targetID), "affected_elements": .array(plan.affectedElements.sorted().map(s)),
            "classification": s(plan.classification.rawValue), "side_effects": directionPayload(plan.sideEffects),
            "delivery": s(plan.deliveryMode == .direct ? "direct" : "coalescible")])
    }
    private static func plan(_ value: ScenarioPayload) throws -> SchedulerTracePlan {
        let value = try object(value)
        try keys(value, ["reference", "payload", "origin", "scope", "source", "endpoint", "evidence", "target", "affected_elements", "classification", "side_effects", "delivery"])
        guard let source = DeviceSource(rawValue: try text(value["source"])), let classification = EffectClassification(rawValue: try text(value["classification"])) else { throw SchedulerCandidateError.invalid("plan enum") }
        let delivery = try text(value["delivery"])
        guard ["direct", "coalescible"].contains(delivery) else { throw SchedulerCandidateError.invalid("delivery") }
        let affected = try strings(value["affected_elements"])
        guard Set(affected).count == affected.count else { throw SchedulerCandidateError.invalid("duplicate affected role") }
        return try SchedulerTracePlan(reference: value["reference"]!, payload: value["payload"]!, origin: value["origin"]!, scope: value["scope"]!, source: source,
            endpointEvidence: endpoint(value["endpoint"]!), capturedEvidence: value["evidence"]!, targetID: text(value["target"]), affectedElements: Set(affected),
            classification: classification, sideEffects: directions(value["side_effects"]), deliveryMode: delivery == "direct" ? .direct : .coalescible)
    }
    private static func authorizationPayload(_ value: PlanAuthorization) -> ScenarioPayload {
        switch value {
        case .granted(let directions): .object(["state": s("granted"), "directions": directionPayload(directions)])
        case .denied(let reason): .object(["state": s("denied"), "reason": s(reason)])
        }
    }
    private static func authorization(_ value: ScenarioPayload) throws -> PlanAuthorization {
        let value = try object(value)
        switch try text(value["state"]) {
        case "granted": try keys(value, ["state", "directions"]); return .granted(directions: try directions(value["directions"]))
        case "denied": try keys(value, ["state", "reason"]); return .denied(reason: try text(value["reason"]))
        default: throw SchedulerCandidateError.invalid("authorization")
        }
    }
    private static func safetyPayload(_ value: NativeSafetyResult) -> ScenarioPayload {
        switch value {
        case .passed: .object(["state": s("passed")])
        case .rejected(let reason): .object(["state": s("rejected"), "reason": s(reason)])
        }
    }
    private static func safety(_ value: ScenarioPayload) throws -> NativeSafetyResult {
        let value = try object(value)
        switch try text(value["state"]) {
        case "passed": try keys(value, ["state"]); return .passed
        case "rejected": try keys(value, ["state", "reason"]); return .rejected(reason: try text(value["reason"]))
        default: throw SchedulerCandidateError.invalid("safety")
        }
    }
    private static func proofPayload(_ proof: SchedulerTraceProof) -> ScenarioPayload {
        .object(["plan": planPayload(proof.plan), "native_snapshot": proof.nativeSnapshot,
                 "authorization": authorizationPayload(proof.authorization), "safety": safetyPayload(proof.safety)])
    }
    private static func proof(_ value: ScenarioPayload) throws -> SchedulerTraceProof {
        let value = try object(value); try keys(value, ["plan", "native_snapshot", "authorization", "safety"])
        return SchedulerTraceProof(plan: try plan(value["plan"]!), nativeSnapshot: value["native_snapshot"]!,
            authorization: try authorization(value["authorization"]!), safety: try safety(value["safety"]!))
    }
    private static func resultPayload(_ value: FeedbackAttemptResult) -> ScenarioPayload {
        switch value {
        case .accepted: .object(["state": s("accepted")])
        case .rejected(let reason): .object(["state": s("rejected"), "reason": s(reason)])
        case .notAttempted(let reason): .object(["state": s("not_attempted"), "reason": s(reason)])
        }
    }
    private static func result(_ value: ScenarioPayload) throws -> FeedbackAttemptResult {
        let value = try object(value)
        switch try text(value["state"]) {
        case "accepted": try keys(value, ["state"]); return .accepted
        case "rejected": try keys(value, ["state", "reason"]); return .rejected(reason: try text(value["reason"]))
        case "not_attempted": try keys(value, ["state", "reason"]); return .notAttempted(reason: try text(value["reason"]))
        default: throw SchedulerCandidateError.invalid("attempt result")
        }
    }

    public static func encodeInput(_ envelope: SchedulerEnvelope) throws -> Data {
        let operation: String, arguments: ScenarioPayload
        switch envelope.input {
        case .initialize(let rate): operation = "initialize"; arguments = .object(["rate": ratePayload(rate)])
        case .enqueue(let item, let ingress):
            operation = "enqueue"
            let provenance: ScenarioPayload = switch ingress {
            case .externalRequest: .object(["kind": s("external_request")])
            case .derivedCallerRequeue(let cause): .object(["kind": s("derived_caller_requeue"), "cause_ordinal": s(String(cause))])
            }
            arguments = .object(["item": itemPayload(item), "ingress": provenance])
        case .cancel(let key): operation = "cancel"; arguments = .object(["key": s(key)])
        case .drain(let at): operation = "drain"; arguments = .object(["at": n(at)])
        case .failure(let at): operation = "failure"; arguments = .object(["at": n(at)])
        case .clear: operation = "clear"; arguments = .object([:])
        case .requestDirect(let item): operation = "request_direct"; arguments = .object(["item": itemPayload(item)])
        case .changeStyle(let style, let key): operation = "change_style"; arguments = .object(["style": itemPayload(style), "projection_key": s(key)])
        case .invalidateCache(let keys): operation = "invalidate_cache"; arguments = .object(["affected_keys": .array(keys.map(s))])
        case .refreshDesired(let order): operation = "refresh_desired"; arguments = .object(["order": .array(order.map(s))])
        case .release(let key): operation = "release"; arguments = .object(["key": s(key)])
        case .gate(let gate):
            operation = "gate"; arguments = .object(["proposal": s(String(gate.proposalOrdinal)), "item": itemPayload(gate.proposedItem), "plan": planPayload(gate.dispatchPlan),
                "proof": proofPayload(gate.proof), "current_scope": gate.currentScope, "current_native_snapshot": gate.currentNativeSnapshot])
        case .receipt(let receipt):
            operation = "receipt"; arguments = .object(["item": itemPayload(receipt.item), "plan": planPayload(receipt.dispatchPlan), "result": resultPayload(receipt.result), "current_scope": receipt.currentScope])
        }
        let value: ScenarioPayload = .object(["schema_version": n(1), "owner": s(envelope.owner), "ordinal": s(String(envelope.ordinal)),
            "operation": s(operation), "arguments": arguments, "context": envelope.context])
        guard schedulerPayloadFinite(value) else { throw SchedulerCandidateError.invalid("nonfinite input") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    public static func decodeInput(_ data: Data) throws -> SchedulerEnvelope {
        try SchedulerJSONGuard.validate(data)
        return try decodeInput(payload: JSONDecoder().decode(ScenarioPayload.self, from: data))
    }

    /// Complete raw JSON validation before a caller's own lossless AST conversion.
    /// Does not admit the scheduler schema or return a send/scheduling decision.
    public static func validateRawJSON(_ data: Data) throws {
        _ = try decodePayload(data)
    }

    /// Complete strict raw JSON decoding. Scalar tokens retain the same exact
    /// Foundation String/Double values as the legacy decoder, without NSNumber
    /// conversion or recursive trial-decoding of containers. The returned AST
    /// is ready for decodeInput(payload:); that semantic admission is separate.
    public static func decodePayload(_ data: Data) throws -> ScenarioPayload {
        try SchedulerStrictJSON.decode(data)
    }

    /// The same closed semantic parser for an already-parsed value. An AST cannot
    /// establish raw duplicate-key/encoding/size validity: callers first validate
    /// their original Data, then preserve every scalar type/bit/string byte.
    public static func decodeInput(payload: ScenarioPayload) throws -> SchedulerEnvelope {
        guard schedulerPayloadFinite(payload) else { throw SchedulerCandidateError.invalid("nonfinite input") }
        let value = try object(payload)
        try keys(value, ["schema_version", "owner", "ordinal", "operation", "arguments", "context"])
        guard try number(value["schema_version"]) == 1 else { throw SchedulerCandidateError.invalid("version") }
        let operation = try text(value["operation"]), args = try object(value["arguments"]!)
        let input: SchedulerInput
        switch operation {
        case "initialize": try keys(args, ["rate"]); input = .initialize(try rate(args["rate"]!))
        case "enqueue":
            try keys(args, ["item", "ingress"]); let ingress = try object(args["ingress"]!)
            let cause: SchedulerIngress
            switch try text(ingress["kind"]) {
            case "external_request": try keys(ingress, ["kind"]); cause = .externalRequest
            case "derived_caller_requeue": try keys(ingress, ["kind", "cause_ordinal"]); cause = .derivedCallerRequeue(causeOrdinal: try uint(ingress["cause_ordinal"]))
            default: throw SchedulerCandidateError.invalid("ingress")
            }
            input = .enqueue(try item(args["item"]!), ingress: cause)
        case "cancel": try keys(args, ["key"]); input = .cancel(key: try text(args["key"]))
        case "drain": try keys(args, ["at"]); input = .drain(at: try number(args["at"]))
        case "failure": try keys(args, ["at"]); input = .failure(at: try number(args["at"]))
        case "clear": try keys(args, []); input = .clear
        case "request_direct": try keys(args, ["item"]); input = .requestDirect(try item(args["item"]!))
        case "change_style": try keys(args, ["style", "projection_key"]); input = .changeStyle(style: try item(args["style"]!), projectionKey: try text(args["projection_key"]))
        case "invalidate_cache": try keys(args, ["affected_keys"]); input = .invalidateCache(affectedKeys: try strings(args["affected_keys"]))
        case "refresh_desired": try keys(args, ["order"]); input = .refreshDesired(order: try strings(args["order"]))
        case "release": try keys(args, ["key"]); input = .release(key: try text(args["key"]))
        case "gate":
            try keys(args, ["proposal", "item", "plan", "proof", "current_scope", "current_native_snapshot"])
            input = .gate(SchedulerGateRecord(proposalOrdinal: try uint(args["proposal"]), proposedItem: try item(args["item"]!),
                dispatchPlan: try plan(args["plan"]!), proof: try proof(args["proof"]!), currentScope: args["current_scope"]!, currentNativeSnapshot: args["current_native_snapshot"]!))
        case "receipt":
            try keys(args, ["item", "plan", "result", "current_scope"])
            input = .receipt(SchedulerActualReceipt(item: try item(args["item"]!), dispatchPlan: try plan(args["plan"]!), result: try result(args["result"]!), currentScope: args["current_scope"]!))
        default: throw SchedulerCandidateError.invalid("unknown operation")
        }
        return SchedulerEnvelope(owner: try text(value["owner"]), ordinal: try uint(value["ordinal"]), input: input, context: value["context"]!)
    }

    private static func proposalPayload(_ proposal: SchedulerProposal) -> ScenarioPayload {
        .object(["ordinal": s(String(proposal.ordinal)), "cause_ordinal": s(String(proposal.causeOrdinal)),
                 "cause": s(proposal.cause.rawValue), "item": itemPayload(proposal.item)])
    }
    private static func preflightPayload(_ result: FeedbackPreflight) -> ScenarioPayload {
        if case .permitted = result { return .object(["state": s("permitted")]) }
        guard case .rejected(let rejection) = result else { return null }
        var value: Object = ["state": s("rejected")]
        switch rejection {
        case .planMismatch: value["reason"] = s("plan_mismatch")
        case .staleScope: value["reason"] = s("stale_scope")
        case .staleNativeProof: value["reason"] = s("stale_native_proof")
        case .authorizationDenied(let reason): value["reason"] = s("authorization_denied"); value["native_reason"] = s(reason)
        case .wrongDirections(let missing, let surplus): value["reason"] = s("wrong_directions"); value["missing"] = directionPayload(missing); value["surplus"] = directionPayload(surplus)
        case .nativeRejected(let reason): value["reason"] = s("native_rejected"); value["native_reason"] = s(reason)
        }
        return .object(value)
    }
    public static func statePayload(_ state: SchedulerStateSnapshot) -> ScenarioPayload {
        .object(["owner": state.owner.map(s) ?? null, "input_ordinal": s(String(state.inputOrdinal)),
            "rate": state.rate.map(ratePayload) ?? null,
            "queued": .array(state.queued.map(itemPayload)), "withheld": .array(state.withheld.map(itemPayload)),
            "desired": .object(state.desired.mapValues(itemPayload)), "accepted_cache": .object(state.acceptedCache.mapValues(itemPayload)),
            "awaiting_gate": .array(state.awaitingGate.map(proposalPayload)),
            "awaiting_receipt": .array(state.awaitingReceipt.map { .object(["proposal": proposalPayload($0.proposal), "plan": planPayload($0.plan)]) }),
            "tokens": state.tokens.map(n) ?? null, "last_refill": state.lastRefill.map(n) ?? null, "retry_after": state.retryAfter.map(n) ?? null,
            "persistent_alignment_differences": .array(state.persistentAlignmentDifferences.map(s))])
    }
    /// Complete output, intentionally not accepted by the input decoder.
    public static func encodeStep(_ step: SchedulerStep) throws -> Data {
        let input = try JSONDecoder().decode(ScenarioPayload.self, from: encodeInput(step.input))
        let value: ScenarioPayload = .object(["artifact": s("scheduler_candidate_output_v1"), "input": input,
            "state": statePayload(step.snapshot), "proposals": .array(step.proposals.map(proposalPayload)),
            "removed_keys": .array(step.removedKeys.map(s)), "replaced_keys": .array(step.replacedKeys.map(s)),
            "deduplicated_keys": .array(step.deduplicatedKeys.map(s)),
            "gates": .array(step.gateDecisions.map { .object(["proposal": s(String($0.proposalOrdinal)), "result": preflightPayload($0.result)]) }),
            "receipts": .array(step.receipts.map { association in .object([
                "proposal": association.proposalOrdinal.map { s(String($0)) } ?? null,
                "item": itemPayload(association.receipt.item), "plan": planPayload(association.receipt.dispatchPlan),
                "result": resultPayload(association.receipt.result),
                "current_scope_matches": association.currentScopeMatches.map { .scalar(.flag($0)) } ?? null]) }),
            "alignment_differences": .array(step.alignmentDifferences.map(s))])
        guard schedulerPayloadFinite(value) else { throw SchedulerCandidateError.invalid("nonfinite output") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
