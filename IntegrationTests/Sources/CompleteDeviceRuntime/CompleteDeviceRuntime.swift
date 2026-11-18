import Foundation
import MinimalDeviceAdapter
import PlatformRuntime
import SurfaceDeviceContracts
import SurfaceBindingContext
import SurfaceConnectionState
import SurfaceFeedbackPlanning
import SurfaceDeviceConformance
import SurfacePluginContracts
import SurfaceControlContracts

public enum NativeTransportFailure: Error { case injectedRejection, stalePin }

private struct AuthorityPolicy: Equatable, Sendable {
    let source: String
    let generation: String
    let mapping: String
    let allowsWrite: Bool
    let allowsDisplay: Bool
    let identities: [String]
    let parameters: [String]?
}
private struct NativeEndpoint: Equatable, Sendable {
    let input: String?
    let output: String?
    let name: String?
    let qualification: String?
    let origin: EndpointTransportOrigin
}
private struct DispatchScope: Equatable, Sendable {
    let instance: String
    let input: String?
    let output: String?
    let connection: UInt64
    let epoch: String
    let mapping: String
    let source: DeviceSource
    let mode: MinimalProtocolMode
    let authority: AuthorityPolicy?
}
private struct CapturedEvidence: Equatable, Sendable {
    let endpoint: NativeEndpoint?
    let mode: MinimalProtocolMode
    let logicalElement: String
    let requestedAt: Double
    let queuedAttribution: String?
}
private struct NativeFacts: Equatable, Sendable {
    let scope: DispatchScope
    let endpoint: NativeEndpoint?
    let targetOwner: String?
    let outputRoleSupported: Bool
    let encodedPayloadValid: Bool
}
private typealias Plan = FeedbackPlan<MinimalPacket, InputOrigin, DispatchScope, String, CapturedEvidence>
private struct Attempt {
    let logicalElement: String
    let fact: FeedbackReceiptFact<Plan>
    let recordedAt: Double
}

/// Generic test caller composition. Business values are always read/committed
/// through the real authority process, never a local mutable parameter map.
public final class CompleteDeviceRuntime {
    public let instanceID: String
    public let source: DeviceSource
    public let platform: PlatformRuntime
    public var authorityID: String { authorityInstance }
    public var attemptCount: Int { attempts.count }
    public private(set) var activePage = "page1"
    private let setup: [String: ScenarioPayload]
    private let pages: [String: [[String: ScenarioPayload]]]
    private let authority: AuthorityPort
    private let authorityInstance: String
    private let journal: ControlJournalOwner
    private let adapter: MinimalDeviceAdapter
    private var physical: MinimalPhysicalModel
    private var display = MinimalDisplayBackend()
    private var connection: ConnectionState<EmptyConnectionIdentity>
    private var endpoint: NativeEndpoint
    private var binding: BindingContextState
    private var pending = try! FeedbackQueue<String, Plan>(rate: .unlimited)
    private var targetOwners = ContextResourceIndex<String, String>()
    private var sentIndex = ContextResourceIndex<String, DispatchScope>()
    private var sent: [String: FeedbackReceiptFact<Plan>] = [:]
    private var attempts: [Attempt] = []
    private var decodedInputs: [DeviceInputEvent] = []
    private var revoked: [String] = []
    private var planOrdinal = 0
    private var epochOrdinal = 0
    private var operationTime = 0.0
    private var lastPreflight: FeedbackPreflight?
    private var preflightRecords: [[String: Any]] = []
    private let originalScope: DispatchScope
    private var attachedEvidence: [(original: NativeEndpoint, connected: NativeEndpoint, snapshot: ConnectionSnapshot<EmptyConnectionIdentity>, generation: UInt64)] = []
    private var decodedRecords: [[String: Any]] = []
    private var observationRecords: [[String: Any]] = []
    private let fault: String

    public init(setup payload: ScenarioPayload, instance: String, mode: MinimalProtocolMode,
                authority: AuthorityPort, authorityInstance: String, helper: String, sdkRoot: String, fault: String) throws {
        setup = try fields(payload)
        guard case .array(let instances) = setup["instances"], let selected = try instances.first(where: { try string(fields($0)["id"]) == instance }),
              case .array(let rawPages) = setup["pages"] else { throw CompositionError.shape("complete_setup") }
        let native = try fields(selected)
        instanceID = instance; source = try string(native["source"]) == "hardware" ? .hardware : .simulation
        self.authority = authority; self.authorityInstance = authorityInstance; self.fault = fault
        adapter = MinimalDeviceAdapter(mode: mode); physical = MinimalPhysicalModel(mode: mode)
        var pageTable: [String: [[String: ScenarioPayload]]] = [:]
        for raw in rawPages {
            let page = try fields(raw)
            guard case .array(let bindings) = page["bindings"] else { throw CompositionError.shape("page_bindings") }
            pageTable[try string(page["id"])] = try bindings.map(fields)
        }
        pages = pageTable
        let generation = UInt64(exactly: try scalar(native["route_generation"]))!
        let inputID = "owned." + instance + ".input", outputID = "owned." + instance + ".output"
        endpoint = NativeEndpoint(input: inputID, output: outputID, name: MinimalFixtureWiring.endpointDisplayName, qualification: nil, origin: .localVirtual)
        connection = ConnectionState(snapshot: try ConnectionSnapshot(inputID: inputID, outputID: outputID,
            transportGeneration: generation, isConnected: true, extra: EmptyConnectionIdentity()), connectionGeneration: generation)
        let profile = try MinimalFixtureWiring.profile(pages: pageTable, page: "page1", mode: mode, source: source)
        let capacity = Int(exactly: try scalar(setup["journal_capacity"]))!
        var controls = try SurfaceControlSession(instanceID: instance, epoch: authorityInstance + ".surface0", profile: profile, eventCapacity: capacity)
        if source == .hardware { try controls.transitionHardware(epoch: authorityInstance + ".surface1", linkState: .connected, at: 0) }
        journal = ControlJournalOwner(controls)
        let context = try DeviceContext(id: instance, generation: controls.expected.epoch, mappingRevision: controls.expected.mapping_revision)
        binding = BindingContextState(try MinimalFixtureWiring.bindings(pages: pageTable, page: "page1", mode: mode, context: context))
        platform = try PlatformRuntime(setup: payload, requestedInstance: instance, authority: authority,
            authorityInstance: authorityInstance, needsAuthority: true, helper: helper, sdkRoot: sdkRoot, fault: fault, sharedControl: journal)
        let raw = try authority.canonicalSnapshot(instance: authorityInstance, at: 0)
        originalScope = DispatchScope(instance: instance, input: inputID, output: outputID, connection: generation,
            epoch: controls.expected.epoch, mapping: controls.expected.mapping_revision, source: source, mode: mode,
            authority: try Self.policy(raw))
        // Setup explicitly supplies a native bootstrap report; it is not a UI
        // inference. Later page changes never manufacture another report.
        let bootTag = try string(native["hardware_context"])
        let boot = try adapter.decodePacket(MinimalFixtureWiring.contextReport(bootTag), context: context,
            endpoint: provenance(.input), source: source, at: 0)
        physical.noteDecoded(boot)
        observationRecords += boot.observations.map { observationRecord($0, packet: MinimalFixtureWiring.contextReport(bootTag)) }
    }

    private static func policy(_ snapshot: [String: Any]) throws -> AuthorityPolicy? {
        if snapshot["authorization"] is NSNull { return nil }
        guard let value = snapshot["authorization"] as? [String: Any], let source = value["source"] as? String,
              let generation = value["generation"] as? String, let mapping = value["mapping_revision"] as? NSNumber,
              let write = value["allows_write"] as? Bool, let display = value["allows_display"] as? Bool,
              let identities = value["identities"] as? [String] else { throw CompositionError.shape("actual_authority_policy") }
        return AuthorityPolicy(source: source, generation: generation, mapping: String(mapping.uint64Value),
            allowsWrite: write, allowsDisplay: display, identities: identities, parameters: value["parameters"] as? [String])
    }
    private func context() throws -> DeviceContext {
        try DeviceContext(id: instanceID, generation: journal.value.expected.epoch, mappingRevision: journal.value.expected.mapping_revision)
    }
    private enum Direction { case input, output }
    private func provenance(_ direction: Direction) throws -> EndpointProvenance {
        try EndpointProvenance(endpointID: direction == .input ? endpoint.input : endpoint.output, deviceID: nil, connectionGeneration: connection.connectionGeneration, transportOrigin: endpoint.origin)
    }
    private func scope() throws -> DispatchScope {
        DispatchScope(instance: instanceID, input: endpoint.input, output: endpoint.output, connection: connection.connectionGeneration,
            epoch: journal.value.expected.epoch, mapping: journal.value.expected.mapping_revision, source: source, mode: adapter.mode,
            authority: try Self.policy(authority.canonicalSnapshot(instance: authorityInstance, at: operationTime)))
    }
    private func value(_ parameter: String) throws -> Double {
        guard let value = try authority.values(instance: authorityInstance, at: operationTime)[parameter] else { throw CompositionError.shape("canonical_value") }; return value
    }

    private func recordInput(_ event: DeviceInputEvent, logical: String, mapped: Double?) throws {
        let descriptor = journal.value.profile.controls.first { $0.id == logical }!
        let raw: JSONValue
        switch event.value { case .number(let value): raw = .double(value); case .flag(let value): raw = .bool(value); default: throw CompositionError.shape("input_value") }
        if source == .hardware {
            _ = try journal.value.recordHardwareInput(.init(expected: journal.value.expected, controlID: logical, encoding: descriptor.encoding.rawValue, value: raw),
                disposition: .accepted, mappedValue: mapped.map(JSONValue.double), at: operationTime)
        } else {
            _ = try journal.value.recordInput(.init(expected: journal.value.expected, expectedSequence: journal.value.discovery().latest_sequence,
                controlID: logical, encoding: descriptor.encoding.rawValue, value: raw), disposition: .accepted,
                mappedValue: mapped.map(JSONValue.double), origin: .interface, at: operationTime)
        }
    }
    private func receive(_ packet: MinimalPacket) throws {
        let inputEndpoint = try provenance(fault == "wrong_input_endpoint" ? .output : .input)
        let decoded = try adapter.decodePacket(packet, context: context(), endpoint: inputEndpoint, source: source, at: operationTime)
        observationRecords += decoded.observations.map { observationRecord($0, packet: packet) }
        physical.noteDecoded(decoded)
        guard let input = decoded.input else { return }
        decodedInputs.append(input)
        decodedRecords.append(["raw_packet": MinimalFixtureWiring.packetRecord(packet), "event": inputRecord(input), "native_endpoint": endpointRecord(endpoint)])
        guard input.endpoint.endpointID == endpoint.input, input.endpoint.connectionGeneration == connection.connectionGeneration,
              input.endpoint.transportOrigin == endpoint.origin, input.source == source else { throw CompositionError.shape("decoded_input_endpoint") }
        let logical = MinimalFixtureWiring.logicalInput(for: input.elementID)
        var mapped: Double?
        if let target = binding.current.target(elementID: input.elementID, facetID: activePage, inputKind: input.kind) {
            if logical == "button" {
                try platform.invokeBoundAction(target, actor: source == .hardware ? .hardware : .interface, at: operationTime)
            } else if case .number(let raw) = input.value {
                // Fixture consumer mapping is identity for absolute scalar and
                // one target unit per relative delta. SP owns canonicalization;
                // every relative proposal reads the sole real current owner.
                let proposal = input.kind == .relative ? try value(target) + raw : raw
                let reply = try platform.submitValue(target, proposed: proposal, actor: source == .hardware ? .hardware : .interface, at: operationTime)
                if reply["ok"] as? Bool == true { mapped = try value(target) }
            }
        }
        try recordInput(input, logical: logical, mapped: mapped)
        // An operator input does not echo to the same logical control. There is
        // no other parameter-bound logical control in this fixture's page.
    }

    private func makePlan(logical: String, value: Double, actor: InputOrigin) throws -> Plan {
        guard ["axis", "meter", "button"].contains(logical) else { throw CompositionError.shape("logical_display") }
        let scope = try scope()
        let descriptor = try EffectDescriptor(id: "existing-operation", targetID: MinimalFixtureWiring.outputRole, affectedElements: [MinimalFixtureWiring.outputRole], value: .number(value),
            classification: .display, sideEffects: [], context: context(), endpoint: provenance(.output), source: source, timing: .immediate, at: operationTime)
        guard let payload = adapter.encode(descriptor) else { throw CompositionError.shape("native_display_encoding") }
        planOrdinal += 1
        let reference = authorityInstance + ".display." + String(planOrdinal)
        targetOwners.upsert(logical, scope: reference)
        return try Plan(reference: reference, payload: payload, origin: actor, scope: scope, source: source, endpointEvidence: provenance(.output),
            capturedEvidence: CapturedEvidence(endpoint: endpoint, mode: adapter.mode, logicalElement: logical, requestedAt: operationTime, queuedAttribution: nil),
            targetID: logical + ".display", affectedElements: [MinimalFixtureWiring.outputRole], classification: .display, sideEffects: [], deliveryMode: .direct)
    }
    private func nativeFacts(for plan: Plan) throws -> NativeFacts {
        var encodedValid = false
        if let value = MinimalFixtureWiring.displayValue(plan.payload) {
            let descriptor = try EffectDescriptor(id: plan.reference, targetID: MinimalFixtureWiring.outputRole, affectedElements: plan.affectedElements,
                value: .number(value), classification: plan.classification, sideEffects: plan.sideEffects,
                context: context(), endpoint: plan.endpointEvidence, source: plan.source, timing: .immediate, at: plan.capturedEvidence.requestedAt)
            encodedValid = adapter.encode(descriptor) == plan.payload
        }
        return NativeFacts(scope: try scope(), endpoint: endpoint, targetOwner: targetOwners.scope(for: plan.capturedEvidence.logicalElement),
            outputRoleSupported: try adapter.capabilities().modes.filter { $0.id == adapter.mode.rawValue }.contains { $0.elements.contains { $0.elementID == MinimalFixtureWiring.outputRole && !$0.displays.isEmpty } }, encodedPayloadValid: encodedValid)
    }
    private func send(_ plan: Plan, transportResult: String) throws {
        let facts = try nativeFacts(for: plan)
        let authorization: PlanAuthorization = facts.scope.authority?.allowsDisplay == true ? .granted(directions: [.display]) : .denied(reason: "real-authority-display-denied")
        let safety: NativeSafetyResult = connection.snapshot.isConnected && facts.outputRoleSupported && facts.encodedPayloadValid && facts.targetOwner == plan.reference
            && plan.affectedElements == [MinimalFixtureWiring.outputRole] && plan.classification == .display && plan.sideEffects.isEmpty
            ? .passed : .rejected(reason: "native-codec-route-or-owner-gate")
        let proof = FeedbackProof(plan: plan, nativeSnapshot: facts, authorization: authorization, safety: safety)
        let currentScope = try scope(), currentFacts = try nativeFacts(for: plan)
        let preflight = FeedbackPreflight.evaluate(plan: plan, proof: proof, currentScope: currentScope, currentNativeSnapshot: currentFacts)
        lastPreflight = preflight
        preflightRecords.append(["plan": planFacts(plan), "proof_plan": planFacts(proof.plan),
            "proof_native_snapshot": nativeFactRecord(proof.nativeSnapshot), "authorization": String(describing: proof.authorization),
            "native_safety": String(describing: proof.safety), "current_scope": scopeRecord(currentScope),
            "current_native_snapshot": nativeFactRecord(currentFacts), "preflight": String(describing: preflight)])
        guard preflight == .permitted else { return }
        // Actual native boundary. Validation/pin/rejection throws; no accepted
        // value or receipt is returned from a placeholder branch.
        var result: FeedbackAttemptResult
        do {
            guard plan.scope.connection == connection.connectionGeneration, plan.scope.output == endpoint.output,
                  plan.scope.mode == adapter.mode else { throw NativeTransportFailure.stalePin }
            if transportResult == "rejected" { throw NativeTransportFailure.injectedRejection }
            guard transportResult == "accepted" else { throw CompositionError.shape("transport_result") }
            try display.receive(plan.payload)
            result = .accepted
        } catch { result = .rejected(reason: String(describing: error)) }
        // Test-only regression control: transport really rejected above.
        if fault == "receipt_on_rejection", transportResult == "rejected" { result = .accepted }
        let receipt = FeedbackReceiptFact(plan: plan, result: result)
        attempts.append(Attempt(logicalElement: plan.capturedEvidence.logicalElement, fact: receipt, recordedAt: operationTime))
        if FeedbackReceiptEligibility.acceptedInCurrentScope(receipt, currentScope: try scope()) {
            sent[plan.capturedEvidence.logicalElement] = receipt
            sentIndex.upsert(plan.capturedEvidence.logicalElement, scope: plan.scope)
            if let value = MinimalFixtureWiring.displayValue(plan.payload) {
                _ = try journal.value.recordFeedback(.init(expected: journal.value.expected, controlID: plan.capturedEvidence.logicalElement,
                    kind: "value", value: .double(value)), origin: plan.origin, at: operationTime)
            }
        }
    }

    public func execute(operation: String, arguments payload: ScenarioPayload, at: Double) throws {
        operationTime = at
        try platform.setOperationClock(at)
        let args = try fields(payload)
        switch operation {
        case "receive_input":
            let logical = try string(args["element_id"])
            if logical == "button" { try receive(MinimalFixtureWiring.button(flag(args["value"]))) }
            else { try receive(MinimalFixtureWiring.input(logical: logical, value: scalar(args["value"]), context: string(args["context"]))) }
        case "turn_absolute": try receive(physical.turn(by: scalar(args["delta"])))
        case "receive_repeated":
            let count = Int(exactly: try scalar(args["count"]))!
            for _ in 0..<count { try receive(MinimalFixtureWiring.relative(scalar(args["value"]), context: string(args["context"]))) }
        case "publish_display": try send(makePlan(logical: string(args["element_id"]), value: scalar(args["value"]), actor: .remote), transportResult: "accepted")
        case "prepare_display":
            let logical = try string(args["element_id"]), plan = try makePlan(logical: logical, value: scalar(args["value"]), actor: .remote)
            pending.enqueue(plan, for: logical)
        case "flush":
            for entry in try pending.drain(at: operationTime) {
                try send(entry.item, transportResult: string(args["transport_result"]))
            }
        case "select_software_page":
            activePage = try string(args["page"])
            try transitionSurface(reconnect: false)
            if let row = pages[activePage]?.first(where: { (try? string($0["element_id"])) == "axis" }), let target = try? string(row["target_id"]) {
                try send(makePlan(logical: "axis", value: value(target), actor: .interface), transportResult: "accepted")
            }
        case "replace_route":
            let requestedGeneration = UInt64(exactly: try scalar(args["route_generation"]))!
            let generation = fault == "wrong_route" ? connection.connectionGeneration : requestedGeneration
            let transition = connection.apply(try ConnectionSnapshot(inputID: endpoint.input, outputID: endpoint.output, transportGeneration: generation, isConnected: true, extra: EmptyConnectionIdentity()))
            if transition.invalidatesScope { physical.invalidateConnectionEvidence(); try transitionSurface(reconnect: true) }
        case "attach_endpoint":
            let id = try string(args["endpoint_id"]), raw = try string(args["provenance"])
            let origin: EndpointTransportOrigin = raw == "remote_virtual" ? .remoteVirtual : raw == "physical_usb" ? .physicalUSB : .unknown
            let incoming = NativeEndpoint(input: id, output: id, name: try string(args["name"]), qualification: nil, origin: origin)
            let installed = NativeEndpoint(input: incoming.input, output: incoming.output, name: incoming.name,
                qualification: fault == "qualification_upgrade" ? "synthetic-invalid-upgrade" : incoming.qualification,
                origin: fault == "wrong_origin" ? .unknown : incoming.origin)
            endpoint = installed
            _ = connection.apply(try ConnectionSnapshot(inputID: id, outputID: id, transportGeneration: connection.connectionGeneration + 1, isConnected: true, extra: EmptyConnectionIdentity()))
            attachedEvidence.append((incoming, endpoint, connection.snapshot, connection.connectionGeneration))
            physical.invalidateConnectionEvidence(); try transitionSurface(reconnect: true)
        case "receive_unconfigured":
            let logical = try string(args["element_id"])
            try receive(MinimalFixtureWiring.unconfigured(logical: logical, value: scalar(args["value"])))
            if fault == "auto_enable_binding" {
                let extra = try ContextBinding(elementID: logical, facetID: activePage, inputKind: .absolute, targetReferenceID: "enable")
                _ = binding.apply(BindingContext(context: try context(), entries: binding.current.entries + [extra]))
            }
        case "write_parameter":
            let id = try string(args["parameter_id"]), actor: InputOrigin = try string(args["origin"]) == "gui" ? .interface : .remote
            let result = try platform.submitValue(id, proposed: scalar(args["value"]), actor: actor, at: at)
            if result["ok"] as? Bool == true || (result["error"] as? [String: Any])?["code"] as? String == "authority_rejected" {
                for row in pages[activePage] ?? [] where try string(row["kind"]) == "parameter" && string(row["target_id"]) == id {
                    try send(makePlan(logical: string(row["element_id"]), value: value(id), actor: actor), transportResult: "accepted")
                }
            }
        case "configure_permissions":
            try platform.execute(operation: operation, arguments: payload, at: at)
            clearProjectionState()
        case "simulation_feedback":
            guard source == .simulation else { throw CompositionError.shape("simulation_feedback_to_hardware") }
            try send(makePlan(logical: string(args["element_id"]), value: scalar(args["value"]), actor: .remote), transportResult: "accepted")
        case "simulation_reset":
            guard source == .simulation else { throw CompositionError.shape("simulation_reset_hardware") }
            epochOrdinal += 1
            try journal.value.reset(expected: journal.value.expected, expectedSequence: journal.value.discovery().latest_sequence,
                epoch: authorityInstance + ".reset." + String(epochOrdinal), at: at)
            clearProjectionState(); physical.invalidateConnectionEvidence(); display = MinimalDisplayBackend()
        case "overflow_journal":
            let requested = Int(exactly: try scalar(args["count"]))!
            let count = fault == "truncate_journal" ? max(0, requested - 1) : requested
            for index in 0..<count { try receive(MinimalFixtureWiring.untaggedAbsolute(Double(index % 128))) }
            try platform.checkCurrentJournalGap(at: at)
        case "authority_reply", "remote_input", "advance_time": try platform.execute(operation: operation, arguments: payload, at: at)
        case "inspect": break
        default: throw CompositionError.operation(operation)
        }
    }
    private func clearProjectionState() {
        revoked += pending.clear(); _ = targetOwners.removeAll(); _ = sentIndex.removeAll()
    }
    private func transitionSurface(reconnect: Bool) throws {
        clearProjectionState(); epochOrdinal += 1
        let profile = try MinimalFixtureWiring.profile(pages: pages, page: activePage, mode: adapter.mode, source: source)
        let epoch = authorityInstance + ".surface." + String(epochOrdinal)
        if source == .hardware { try journal.value.transitionHardware(epoch: epoch, linkState: .connected, profile: profile, at: operationTime) }
        else { try journal.value.reset(expected: journal.value.expected, expectedSequence: journal.value.discovery().latest_sequence, epoch: epoch, profile: profile, at: operationTime) }
        _ = binding.apply(try MinimalFixtureWiring.bindings(pages: pages, page: activePage, mode: adapter.mode, context: context()))
    }

    public func metrics() throws -> [String: TraceValue] {
        var values = try platform.metrics()[instanceID] ?? [:]
        let canonical = try authority.values(instance: authorityInstance, at: operationTime)
        for (id, value) in canonical { values["parameter_" + id] = .number(value) }
        values["hardware_context"] = physical.lastReportedHardwareContext.map(TraceValue.text) ?? .null
        values["software_page"] = .text(activePage)
        values["route_generation"] = .number(Double(connection.connectionGeneration))
        values["old_authorization_valid"] = .flag(try scope() == originalScope)
        values["release_count"] = .number(Double(decodedInputs.filter { $0.kind == .release }.count))
        values["relative_delta_sum"] = .number(decodedInputs.reduce(0) { sum, input in if input.kind == .relative, case .number(let value) = input.value { return sum + value }; return sum })
        values["enable_binding_count"] = .number(Double(binding.current.entries.filter { $0.targetReferenceID == "enable" }.count))
        values["device_output_count"] = .number(Double(attempts.count))
        values["display_output_count"] = .number(Double(attempts.filter { $0.fact.plan.classification == .display }.count))
        values["accepted_transport_count"] = .number(Double(attempts.filter { $0.fact.successfulSend }.count))
        values["layer_select_output_count"] = .number(Double(attempts.filter { $0.fact.plan.classification == .management }.count))
        values["display_plan_valid"] = .flag(lastPreflight == .permitted)
        values["provenance_preserved"] = .flag(attachedEvidence.allSatisfy { row in
            row.original.input == row.snapshot.inputID && row.original.output == row.snapshot.outputID && row.original.origin == row.connected.origin
        })
        values["qualification_upgraded"] = .flag(attachedEvidence.contains { $0.original.qualification == nil && $0.connected.qualification != nil } || endpoint.qualification != nil)
        if sentIndex.contains("axis"), let receipt = sent["axis"], let value = MinimalFixtureWiring.displayValue(receipt.plan.payload) { values["sent_value"] = .number(value) }
        else { values["sent_value"] = .null }
        return values
    }

    public func detail() throws -> [String: Any] {
        ["instance": instanceID, "source": source.rawValue, "mode": adapter.mode.rawValue,
         "logical_axis_input_role": MinimalFixtureWiring.inputRole, "logical_axis_display_role": MinimalFixtureWiring.outputRole, "knob_display_capability": try adapter.capabilities().modes.first { $0.id == adapter.mode.rawValue }!.elements.first { $0.elementID == MinimalFixtureWiring.inputRole }!.displays.isEmpty == false,
         "profile_capabilities": journal.value.profile.capabilities, "decoded_inputs": decodedRecords, "observations": observationRecords,
         "pending": pending.orderedKeys, "revoked": revoked, "preflight_records": preflightRecords,
         "attempts": attempts.map { attempt -> [String: Any] in
             let packet = MinimalFixtureWiring.packetRecord(attempt.fact.plan.payload)
             let address = packet["address"], value = packet["value"]
             return ["logical_target": attempt.fact.plan.targetID, "affected_elements": attempt.fact.plan.affectedElements.sorted(),
                     "native_address": address as Any? ?? NSNull(), "value": value as Any? ?? NSNull(),
                     "successful_send": attempt.fact.successfulSend, "actual_attempt": attempt.fact.hasTransportAttempt,
                     "result": String(describing: attempt.fact.result), "recorded_at": attempt.recordedAt, "receipt_plan": planFacts(attempt.fact.plan),
                     "captured_name": attempt.fact.plan.capturedEvidence.endpoint?.name as Any? ?? NSNull()]
         }, "native_received_display_packets": display.received.count,
         "attached_evidence": attachedEvidence.map { row in ["original_descriptor": endpointRecord(row.original), "actual_connection_native_endpoint": endpointRecord(row.connected), "actual_generation": String(row.generation), "actual_connection_input_id": row.snapshot.inputID as Any? ?? NSNull(), "actual_connection_output_id": row.snapshot.outputID as Any? ?? NSNull()] },
         "actual_native_endpoint": endpointRecord(endpoint),
         "reported_absolute_position": physical.lastReportedAbsolutePosition as Any? ?? NSNull(),
         "reported_hardware_context": physical.lastReportedHardwareContext as Any? ?? NSNull(),
         "accepted_lamp_brightness": display.lastAcceptedBrightness as Any? ?? NSNull(),
         "platform": try platform.supplementalFacts(), "action_journal": try platform.actionJournalFacts()]
    }
    private func commonEndpointRecord(_ value: EndpointProvenance) -> [String: Any] {
        ["endpoint_id": value.endpointID as Any? ?? NSNull(), "device_id": value.deviceID as Any? ?? NSNull(),
         "connection_generation": String(value.connectionGeneration), "transport_origin": value.transportOrigin.rawValue]
    }
    private func contextRecord(_ value: DeviceContext) -> [String: Any] {
        ["id": value.id, "generation": value.generation, "mapping_revision": value.mappingRevision as Any? ?? NSNull()]
    }
    private func inputRecord(_ value: DeviceInputEvent) -> [String: Any] {
        ["element_id": value.elementID, "input_kind": value.kind.rawValue, "value": String(describing: value.value),
         "context": contextRecord(value.context), "endpoint": commonEndpointRecord(value.endpoint), "source": value.source.rawValue, "at": value.at]
    }
    private func observationRecord(_ value: DeviceObservation, packet: MinimalPacket) -> [String: Any] {
        ["raw_packet": MinimalFixtureWiring.packetRecord(packet), "target_id": value.targetID, "state": value.state.rawValue, "evidence": value.evidence?.rawValue as Any? ?? NSNull(),
         "value": String(describing: value.value), "context": contextRecord(value.context), "endpoint": commonEndpointRecord(value.endpoint), "source": value.source.rawValue, "at": value.at]
    }
    private func endpointRecord(_ value: NativeEndpoint?) -> Any {
        guard let value else { return NSNull() }
        return ["input": value.input as Any? ?? NSNull(), "output": value.output as Any? ?? NSNull(),
            "name": value.name as Any? ?? NSNull(), "qualification": value.qualification as Any? ?? NSNull(), "origin": value.origin.rawValue]
    }
    private func scopeRecord(_ scope: DispatchScope) -> [String: Any] {
        let policy: Any = scope.authority.map { value -> [String: Any] in
            ["source": value.source, "generation": value.generation, "mapping": value.mapping, "allows_write": value.allowsWrite,
             "allows_display": value.allowsDisplay, "identities": value.identities, "parameters": value.parameters as Any? ?? NSNull()]
        } ?? NSNull()
        return ["instance": scope.instance, "input": scope.input as Any? ?? NSNull(), "output": scope.output as Any? ?? NSNull(),
            "connection_generation": String(scope.connection), "epoch": scope.epoch, "mapping": scope.mapping,
            "source": scope.source.rawValue, "native_mode": scope.mode.rawValue, "actual_authority_context": policy]
    }
    private func nativeFactRecord(_ value: NativeFacts) -> [String: Any] {
        ["scope": scopeRecord(value.scope), "endpoint": endpointRecord(value.endpoint), "target_owner": value.targetOwner as Any? ?? NSNull(),
         "output_role_supported": value.outputRoleSupported, "encoded_payload_valid": value.encodedPayloadValid]
    }
    private func planFacts(_ plan: Plan) -> [String: Any] {
        let wire = MinimalFixtureWiring.packetRecord(plan.payload)
        return ["reference": plan.reference, "payload": wire, "origin": plan.origin.rawValue, "scope": scopeRecord(plan.scope),
            "source": plan.source.rawValue, "target": plan.targetID, "affected_elements": plan.affectedElements.sorted(),
            "classification": plan.classification.rawValue, "side_effects": plan.sideEffects.map(\.rawValue).sorted(),
            "required_directions": plan.requiredDirections.map(\.rawValue).sorted(), "delivery_mode": String(describing: plan.deliveryMode),
            "common_endpoint": ["endpoint_id": plan.endpointEvidence.endpointID as Any? ?? NSNull(), "device_id": plan.endpointEvidence.deviceID as Any? ?? NSNull(),
                "generation": String(plan.endpointEvidence.connectionGeneration), "origin": plan.endpointEvidence.transportOrigin.rawValue],
            "full_captured_evidence": ["endpoint": endpointRecord(plan.capturedEvidence.endpoint), "mode": plan.capturedEvidence.mode.rawValue,
                "logical_element": plan.capturedEvidence.logicalElement, "requested_at": plan.capturedEvidence.requestedAt,
                "queued_attribution": plan.capturedEvidence.queuedAttribution as Any? ?? NSNull()]]
    }
    public func effectTraces(since count: Int) -> [ScenarioEffectTrace] {
        attempts.dropFirst(count).map { attempt in
            let value: TraceValue
            if let brightness = MinimalFixtureWiring.displayValue(attempt.fact.plan.payload) { value = .number(brightness) } else { value = .null }
            return ScenarioEffectTrace(instanceID: instanceID, kinds: [.display, .valueProjection], endpoint: attempt.fact.plan.targetID,
                value: value, accepted: attempt.fact.successfulSend)
        }
    }
}
