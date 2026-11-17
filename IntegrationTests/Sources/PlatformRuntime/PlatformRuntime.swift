import Foundation
import MinimalDeviceAdapter
import SurfaceDeviceContracts
import SurfaceBindingContext
import SurfaceDeviceConformance
import SurfacePluginContracts
import SurfaceControlContracts
import RemoteToolContracts
import AgentPlugin
import AgentRemoteBinding

public enum CompositionError: Error { case shape(String), operation(String), requiresJ4Dispatch }

public func fields(_ payload: ScenarioPayload) throws -> [String: ScenarioPayload] {
    guard case .object(let value) = payload else { throw CompositionError.shape("object") }
    return value
}
public func string(_ value: ScenarioPayload?) throws -> String {
    guard case .scalar(.text(let value)) = value else { throw CompositionError.shape("string") }
    return value
}
public func scalar(_ value: ScenarioPayload?) throws -> Double {
    guard case .scalar(.number(let value)) = value else { throw CompositionError.shape("number") }
    return value
}
public func flag(_ value: ScenarioPayload?) throws -> Bool {
    guard case .scalar(.flag(let value)) = value else { throw CompositionError.shape("flag") }
    return value
}

/// Serial test caller owner of the actual production control-session value.
/// Sharing this owner avoids two input/feedback journals for one device.
public final class ControlJournalOwner {
    public var value: SurfaceControlSession
    public init(_ value: SurfaceControlSession) { self.value = value }
}

/// Test-only caller services assembled from production libraries. No expected
/// assertion enters this type, and current business values live only in Bridge.
public final class PlatformRuntime {
    public let instanceID: String
    public let authorityInstance: String
    public private(set) var operationClock = 0.0
    public private(set) var remoteTransportFacts: [String: Any] = [:]
    private let authority: AuthorityPort
    private let hasAuthority: Bool
    private let helper: String
    private let sdkRoot: String
    private let adapter = MinimalDeviceAdapter()
    private let definitions: [String: SurfacePluginContracts.ParameterDefinition]
    private let controlBindings: BindingContext
    private let journalOwner: ControlJournalOwner
    private var session: SurfaceControlSession {
        get { journalOwner.value }
        set { journalOwner.value = newValue }
    }
    private var registry: RemoteRegistry
    private let baselineActionSequence: UInt64
    private var lastAuthorityError: [String: Any]?
    private var lastJournalError: String?
    private var writeDecisions: [String: String] = [:]
    private var remoteDispatchOrigins: [InputOrigin] = []
    private var remoteRejection: String?
    private var spoofParserAuxiliary: [String: Any] = [:]
    private var approvalRegistry: RemoteRegistry
    private var untrustedApprovalEvents: [PluginEvent] = []
    private var approvalControls: [String: Any] = [:]
    private var clockWitness: AgentPlugin
    private var policyMonotonic = 0.0
    private var policyWall = 0.0
    private var lastPolicyServerTime: Double?
    private var clockErrors: [String] = []
    private var deviceTransmissionEvidence: [TransmissionEvidence] = []
    private var fault: String

    public init(setup: ScenarioPayload, requestedInstance: String, authority: AuthorityPort, authorityInstance: String,
                needsAuthority: Bool, helper: String, sdkRoot: String, fault: String,
                sharedControl: ControlJournalOwner? = nil) throws {
        let setup = try fields(setup)
        guard case .array(let rawInstances) = setup["instances"],
              let selected = try rawInstances.first(where: { try string(fields($0)["id"]) == requestedInstance }),
              case .array(let rawDefinitions) = setup["parameters"] else { throw CompositionError.shape("setup") }
        let instance = try fields(selected)
        instanceID = try string(instance["id"])
        let hardware = try string(instance["source"]) == "hardware"
        self.authority = authority; self.authorityInstance = authorityInstance
        self.hasAuthority = needsAuthority; self.helper = helper; self.sdkRoot = sdkRoot; self.fault = fault
        var definitions: [String: SurfacePluginContracts.ParameterDefinition] = [:]
        var bridgeDefinitions: [[String: Any]] = []
        for raw in rawDefinitions {
            let raw = try fields(raw), id = try string(raw["id"])
            let minimum = try scalar(raw["minimum"]), maximum = try scalar(raw["maximum"]), initial = try scalar(raw["initial"])
            let step = try raw["step"].map { try scalar($0) }
            definitions[id] = try .init(id: .init(rawValue: id), nameKey: id,
                minimum: minimum, maximum: maximum, defaultValue: initial, step: step)
            var bridge: [String: Any] = ["id": id, "minimum": minimum, "maximum": maximum, "initial": initial]
            if let step { bridge["step"] = step }
            bridgeDefinitions.append(bridge)
        }
        self.definitions = definitions
        let profile = ControlProfile(id: "minimal.offline", version: hardware ? "1.4" : "1.3", controls: [
            .init(id: "axis", inputKind: .absolute, encoding: .scalar, range: .init(minimum: 0, maximum: 127),
                  mapping: .init(kind: .parameter, id: "p1"), acceptsInput: !hardware),
            .init(id: "button", inputKind: .button, encoding: .boolean,
                  mapping: .init(kind: .action, id: "fire1"), acceptsInput: !hardware)
        ], capabilities: [hardware ? "hardware" : "simulation", "controls.input_declared", "input.absolute", "input.button"])
        guard let capacity = Int(exactly: try scalar(setup["journal_capacity"])) else { throw CompositionError.shape("capacity") }
        if let sharedControl {
            guard sharedControl.value.expected.instance_id == instanceID else { throw CompositionError.shape("shared_session_instance") }
            journalOwner = sharedControl
        } else {
            var value = try SurfaceControlSession(instanceID: instanceID, epoch: authorityInstance + ".bootstrap", profile: profile, eventCapacity: capacity)
            if hardware { try value.transitionHardware(epoch: authorityInstance + ".connected", linkState: .connected, at: 0) }
            journalOwner = ControlJournalOwner(value)
        }
        controlBindings = BindingContext(context: try DeviceContext(id: instanceID, generation: "page1", mappingRevision: nil),
            controlEntries: [try ControlBinding(elementID: "button", facetID: "page1", targetReferenceID: "fire1")])
        registry = try RemoteRegistry(epoch: authorityInstance + ".actions", eventCapacity: 64)
        for action in ["fire1", "fire2"] {
            try registry.install(AgentRemoteBinding(instanceID: action, plugin: AgentPlugin(slotCount: 1)))
            _ = try registry.handle(instanceID: action, input: .start, at: 0)
        }
        baselineActionSequence = try registry.journal.read(epoch: registry.journal.epoch, after: 0).latestSequence
        var approval = try AgentPlugin(slotCount: 1, approvalPolicy: .localOrigins, at: 0)
        _ = try approval.handle(.start, at: 0)
        _ = try approval.handle(.invoke(.init(pluginID: AgentPlugin.pluginID, actionID: AgentPlugin.primaryActionID, index: 1), origin: .interface), at: 0)
        _ = try approval.handle(.advance, at: 10) // Explicit diagnostic clock, not fixture time.
        guard approval.slots.first?.state == .waitingApproval else { throw CompositionError.shape("approval_not_waiting") }
        approvalRegistry = try RemoteRegistry(epoch: authorityInstance + ".approval-witness", eventCapacity: 16)
        try approvalRegistry.install(AgentRemoteBinding(instanceID: "approval.witness", plugin: approval))
        // An unmapped production-plugin diagnostic exercises a real timed policy
        // without adding a business action or indicator to the device mapping.
        clockWitness = try AgentPlugin(slotCount: 1, at: 0)
        _ = try clockWitness.handle(.start, at: 0)
        _ = try clockWitness.handle(.invoke(.init(pluginID: AgentPlugin.pluginID,
            actionID: AgentPlugin.primaryActionID, index: 1), origin: .interface), at: 0)
        if needsAuthority {
            let created = try authority.call("create", instance: authorityInstance, at: 0, arguments: ["definitions": bridgeDefinitions])
            guard created["ok"] as? Bool == true else { throw CompositionError.shape("create_authority") }
            let permissions = try authority.call("permissions", instance: authorityInstance, at: 0,
                arguments: ["allows_write": true, "allows_display": true, "identities": ["local", "remote", "history"]])
            guard permissions["ok"] as? Bool == true else { throw CompositionError.shape("authority_permissions") }
        }
    }

    public func metrics() throws -> TraceObservations {
        let events = try registry.journal.read(epoch: registry.journal.epoch, after: baselineActionSequence).events
        let count = events.filter { $0.instanceID == "fire1" }.count
        var values: [String: TraceValue] = [
            "action_fire1_count": .number(Double(count)),
            "action_fire2_count": .number(Double(events.filter { $0.instanceID == "fire2" }.count)),
            "result_certain": .flag(!((remoteTransportFacts["client_errors"] as? [String]) ?? []).contains("transport_unknown")),
            "automatic_action_replay_count": .number(Double((remoteTransportFacts["automatic_retry_attempts"] as? Int) ?? 0)),
            "journal_gap": .flag(lastJournalError == "event_gap"),
            "control_sequence": .text(session.discovery().latest_sequence),
            "control_source": .text(session.source.rawValue),
            "authority_error_visible": .flag(lastAuthorityError?["code"] as? String == "authority_rejected")
        ]
        values["device_output_count"] = .number(Double(deviceTransmissionEvidence.count))
        values["authorization_rules_equal"] = .flag(writeDecisions["local"].map { $0 == writeDecisions["remote"] } ?? false)
        let approved = untrustedApprovalEvents.contains {
            $0.code == "agent.updated" && $0.fields["statusKey"] == .string("agent.mock.approved")
        }
        values["manual_authority_granted"] = .flag(approved)
        values["monotonic_policy_preserved"] = .flag(clockErrors.isEmpty && lastPolicyServerTime == policyMonotonic
            && clockWitness.slots.allSatisfy { $0.lastUpdated <= policyMonotonic })
        if hasAuthority {
            guard let value = try authority.values(instance: authorityInstance, at: operationClock)["p1"] else { throw CompositionError.shape("canonical_p1") }
            values["rendered_value"] = .number(fault == "wrong_render" ? value + 1 : value)
        }
        return [instanceID: values]
    }

    public func execute(operation: String, arguments: ScenarioPayload, at: Double) throws {
        operationClock = at
        let arguments = try fields(arguments)
        switch operation {
        case "configure_permissions":
            let display = try flag(arguments["display"])
            _ = try flag(arguments["motor"]); _ = try flag(arguments["manage"])
            // This is the existing fixture primitive's mapping used by both host
            // executors: withdrawing display also withdraws value-write authority.
            let result = try authority.call("permissions", instance: authorityInstance, at: at,
                arguments: ["allows_write": display, "allows_display": display, "identities": ["local", "remote", "history"]])
            guard result["ok"] as? Bool == true else { throw CompositionError.shape("permissions") }
        case "authority_reply":
            let accepted = try flag(arguments["accepted"])
            var reply: [String: Any] = ["parameter": try string(arguments["parameter_id"]), "accepted": accepted]
            if !accepted {
                reply["actual_value"] = try scalar(arguments["actual_value"])
                reply["reason"] = try string(arguments["reason"])
            }
            let response = try authority.call("authority_reply", instance: authorityInstance, at: at, arguments: reply)
            guard response["ok"] as? Bool == true else { throw CompositionError.shape("authority_reply") }
        case "write_parameter":
            let id = try string(arguments["parameter_id"])
            let origin = try string(arguments["origin"])
            guard ["gui", "remote", "agent"].contains(origin) else { throw CompositionError.shape("origin") }
            let response = try submitValue(id, proposed: scalar(arguments["value"]), actor: origin == "gui" ? .interface : .remote, at: at)
            if response["ok"] as? Bool == true { throw CompositionError.requiresJ4Dispatch }
        case "remote_input":
            guard try string(arguments["element_id"]) == "button", try flag(arguments["value"]),
                  controlBindings.targetForControl(elementID: "button", facetID: "page1") == "fire1" else {
                throw CompositionError.shape("remote_action")
            }
            let claimedOrigin = try string(arguments["claimed_origin"])
            if claimedOrigin != "remote" {
                let forgedFields: [String: JSONValue] = ["expected": try .encoded(session.expected),
                    "expected_sequence": .string(session.discovery().latest_sequence), "control_id": .string("button"),
                    "encoding": .string("boolean"), "value": .bool(true), "origin": .string(claimedOrigin)]
                var baselineFields = forgedFields
                baselineFields.removeValue(forKey: "origin")
                let before = try registry.journal.read(epoch: registry.journal.epoch, after: baselineActionSequence).events.count
                do {
                    _ = try SurfaceControlTools.parse("surface_control_input", arguments: .object(forgedFields))
                    throw CompositionError.shape("forged_origin_parsed")
                } catch let error as ControlContractError { remoteRejection = error.code }
                guard case .input(let baselineInput) = try SurfaceControlTools.parse("surface_control_input", arguments: .object(baselineFields)) else {
                    throw CompositionError.shape("baseline_did_not_parse_as_input")
                }
                var hardwareValidationError: String?
                do {
                    _ = try session.validateInput(baselineInput, at: at)
                    throw CompositionError.shape("hardware_remote_input_was_not_refused")
                } catch let error as ControlContractError { hardwareValidationError = error.code }
                let after = try registry.journal.read(epoch: registry.journal.epoch, after: baselineActionSequence).events.count
                let preserved = Dictionary(uniqueKeysWithValues: baselineFields.keys.map {
                    ($0, ControlCanonicalJSON.serialize(baselineFields[$0]!) == ControlCanonicalJSON.serialize(forgedFields[$0]!))
                })
                spoofParserAuxiliary = ["removed_keys": ["origin"], "other_fields_byte_preserved": preserved,
                    "forged_arguments_canonical": ControlCanonicalJSON.serialize(.object(forgedFields)),
                    "baseline_arguments_canonical": ControlCanonicalJSON.serialize(.object(baselineFields)),
                    "forged_parse_error": remoteRejection.map { $0 as Any } ?? NSNull(),
                    "baseline_parse_result": "input", "hardware_validation_error": hardwareValidationError.map { $0 as Any } ?? NSNull(),
                    "action_events_before_aux": before, "action_events_after_aux": after]
                try exerciseApprovalControls(at: at)
                if fault == "accept_spoof" {
                    let approval = try approvalRegistry.handle(instanceID: "approval.witness", input: .invoke(.init(pluginID: AgentPlugin.pluginID,
                        actionID: AgentPlugin.primaryActionID, index: 1), origin: .hardware), at: 10 + at)
                    untrustedApprovalEvents += approval.events
                    _ = try registry.handle(instanceID: "fire1", input: .invoke(.init(pluginID: AgentPlugin.pluginID,
                        actionID: AgentPlugin.primaryActionID, index: 1), origin: .hardware), at: at)
                    remoteDispatchOrigins.append(.hardware)
                    return
                }
                return
            }
            guard try flag(arguments["drop_response"]) else { throw CompositionError.shape("checkpoint_requires_response_loss") }
            let transport = try LineProcess(executable: "/usr/bin/env", arguments: ["python3", "-B", helper, "--sdk-root", sdkRoot]
                + (fault == "retry_lost_action" ? ["--retry-after-loss"] : []))
            while true {
                let frame = try transport.receive()
                if frame["event"] as? String == "complete" { remoteTransportFacts = frame; break }
                guard frame["event"] as? String == "rpc", let request = frame["request"] as? [String: Any],
                      request["method"] as? String == "tools/call", let id = request["id"] as? Int,
                      let parameters = request["params"] as? [String: Any], let name = parameters["name"] as? String,
                      let rawArguments = parameters["arguments"] else { throw CompositionError.shape("rpc") }
                let args = try JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: rawArguments))
                let result = try registry.call(name, arguments: args, context: RemoteCallContext(time: at))
                remoteDispatchOrigins.append(.remote)
                let structured = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result))
                try transport.send(["event": "committed", "id": id, "result": ["structuredContent": structured, "isError": false]])
            }
            let (code, errors) = try transport.close()
            guard code == 0, errors.isEmpty else { throw CompositionError.shape("action_transport_exit") }
        case "advance_time":
            policyMonotonic += try scalar(arguments["monotonic_delta_s"])
            policyWall += try scalar(arguments["wall_delta_s"]) + scalar(arguments["monotonic_delta_s"])
            let supplied = fault == "use_wall_clock" ? policyWall : policyMonotonic
            do {
                _ = try clockWitness.handle(.advance, at: supplied)
                lastPolicyServerTime = try session.snapshot(at: supplied).server_time
            } catch { clockErrors.append(String(describing: error)) }
        case "overflow_journal":
            guard let requested = Int(exactly: try scalar(arguments["count"])), (1...1024).contains(requested) else { throw CompositionError.shape("count") }
            let actual = fault == "truncate_journal" ? requested - 1 : requested
            let context = try DeviceContext(id: instanceID, generation: session.expected.epoch, mappingRevision: session.expected.mapping_revision)
            let endpoint = try EndpointProvenance(endpointID: "minimal.input", deviceID: nil, connectionGeneration: 1, transportOrigin: .localVirtual)
            for i in 0..<actual {
                guard let event = try adapter.decode(.position(address: "knob.input", value: Double(i)), context: context,
                    endpoint: endpoint, source: .hardware, at: at), case .number(let value) = event.value else { throw CompositionError.shape("packet") }
                let input = ControlHardwareInput(expected: session.expected, controlID: "axis", encoding: "scalar", value: .double(value))
                _ = try session.recordHardwareInput(input, disposition: .accepted, at: at)
            }
            do {
                _ = try session.events(instanceID: instanceID, epoch: session.expected.epoch, afterSequence: "0", at: at)
                lastJournalError = nil
            } catch let error as ControlContractError { lastJournalError = error.code }
        case "publish_display", "prepare_display", "flush", "simulation_feedback":
            throw CompositionError.requiresJ4Dispatch
        default: throw CompositionError.operation(operation)
        }
    }

    /// Generic caller intent mapping; actual canonicalization/authorization/value
    /// commit remain the production SP definition and independent Bridge owner.
    public func submitValue(_ id: String, proposed: Double, actor: InputOrigin, at: Double) throws -> [String: Any] {
        operationClock = at
        guard let definition = definitions[id] else { throw CompositionError.shape("parameter") }
        let canonical = try definition.clamp(proposed)
        let identity = actor == .remote ? "remote" : "local"
        if identity == "remote" && fault == "bypass_remote_permission" {
            _ = try authority.call("permissions", instance: authorityInstance, at: at,
                arguments: ["allows_write": true, "allows_display": false, "identities": ["remote"]])
        }
        let response = try authority.call("write", instance: authorityInstance, at: at,
            arguments: ["parameter": id, "canonical_value": canonical, "identity": identity])
        writeDecisions[identity] = response["ok"] as? Bool == true ? "accepted" : ((response["error"] as? [String: Any])?["code"] as? String ?? "invalid_response")
        lastAuthorityError = fault == "drop_authority_error" ? nil : response["error"] as? [String: Any]
        if response["ok"] as? Bool != true && lastAuthorityError == nil && fault != "drop_authority_error" { throw CompositionError.shape("unreported_authority_error") }
        return response
    }

    public func invokeBoundAction(_ reference: String, actor: InputOrigin, at: Double) throws {
        guard registry.binding(reference, as: AgentRemoteBinding.self) != nil else { throw CompositionError.shape("action_reference") }
        _ = try registry.handle(instanceID: reference, input: .invoke(.init(pluginID: AgentPlugin.pluginID,
            actionID: AgentPlugin.primaryActionID, index: 1), origin: actor), at: at)
    }
    public func setOperationClock(_ at: Double) throws {
        guard at.isFinite else { throw CompositionError.shape("operation_clock") }; operationClock = at
    }
    public func checkCurrentJournalGap(at: Double) throws {
        operationClock = at
        do {
            _ = try session.events(instanceID: instanceID, epoch: session.expected.epoch, afterSequence: "0", at: at)
            lastJournalError = nil
        } catch let error as ControlContractError { lastJournalError = error.code }
    }

    public func supplementalFacts() throws -> [String: Any] {
        let approvalState = try approvalFacts(approvalRegistry)
        let approvalEvents = try JSONSerialization.jsonObject(with: JSONEncoder().encode(untrustedApprovalEvents))
        return ["write_decisions": writeDecisions, "remote_rejection": remoteRejection.map { $0 as Any } ?? NSNull(),
         "remote_dispatch_origins": remoteDispatchOrigins.map(\.rawValue),
         "spoof_parser_auxiliary": spoofParserAuxiliary,
         "approval_controls": approvalControls,
         "untrusted_approval_witness_after": approvalState,
         "untrusted_approval_events": approvalEvents,
         "policy_monotonic": policyMonotonic, "policy_wall": policyWall,
         "policy_server_time": lastPolicyServerTime.map { $0 as Any } ?? NSNull(),
         "clock_errors": clockErrors,
         "clock_witness_slots": clockWitness.slots.map { ["state": $0.state.rawValue, "updated_at": $0.lastUpdated] as [String: Any] },
         "actual_device_transmissions": deviceTransmissionEvidence.count]
    }

    private func approvalFacts(_ value: RemoteRegistry) throws -> [String: Any] {
        guard let binding = value.binding("approval.witness", as: AgentRemoteBinding.self), let slot = binding.plugin.slots.first else {
            throw CompositionError.shape("approval_witness")
        }
        return ["policy": binding.plugin.approvalPolicy.rawValue, "state": slot.state.rawValue,
            "status_key": slot.statusKey, "progress": slot.progress, "last_updated_diagnostic_clock": slot.lastUpdated,
            "journal": try value.journal.read(epoch: value.journal.epoch, after: 0).events.map {
                ["sequence": String($0.sequence), "code": $0.event.code, "instance": $0.instanceID]
            }]
    }

    private func exerciseApprovalControls(at: Double) throws {
        let time = 10 + at
        let before = try approvalFacts(approvalRegistry)
        var remoteControl = approvalRegistry
        var remoteError: [String: Any] = [:]
        do {
            _ = try remoteControl.call("surface_agent_primary", arguments: .object(["instance_id": .string("approval.witness"), "slot": .number(1)]),
                context: RemoteCallContext(time: time))
            throw CompositionError.shape("remote_approval_not_denied")
        } catch let error as RemoteFailure {
            remoteError = ["code": error.code, "fields": try JSONSerialization.jsonObject(with: JSONEncoder().encode(error.fields))]
        }
        var hardwareControl = approvalRegistry
        let localUpdate = try hardwareControl.handle(instanceID: "approval.witness", input: .invoke(.init(pluginID: AgentPlugin.pluginID,
            actionID: AgentPlugin.primaryActionID, index: 1), origin: .hardware), at: time)
        approvalControls = ["diagnostic_policy_time": time, "fixture_operation_time": at,
            "untrusted_before": before, "ordinary_remote_error": remoteError,
            "ordinary_remote_after": try approvalFacts(remoteControl),
            "true_local_hardware_after": try approvalFacts(hardwareControl),
            "true_local_hardware_events": try JSONSerialization.jsonObject(with: JSONEncoder().encode(localUpdate.events)),
            "original_witness_after_isolated_controls": try approvalFacts(approvalRegistry)]
    }

    public func actionJournalFacts() throws -> [[String: String]] {
        try registry.journal.read(epoch: registry.journal.epoch, after: baselineActionSequence).events.map {
            ["sequence": String($0.sequence), "instance": $0.instanceID, "code": $0.event.code]
        }
    }

    public static func undoRevocationAux(authority: AuthorityPort) throws -> [String: Any] {
        let id = "undo.aux"
        let definition: [String: Any] = ["id": "p1", "minimum": 0, "maximum": 127, "initial": 0]
        _ = try authority.call("create", instance: id, at: 1, arguments: ["definitions": [definition]])
        func permissions(_ identities: [String], at: Double) throws {
            let result = try authority.call("permissions", instance: id, at: at,
                arguments: ["allows_write": true, "allows_display": true, "identities": identities])
            guard result["ok"] as? Bool == true else { throw CompositionError.shape("aux_permissions") }
        }
        try permissions(["local", "remote", "history"], at: 1)
        _ = try authority.call("write", instance: id, at: 1.1, arguments: ["parameter": "p1", "canonical_value": 100, "identity": "local"])
        _ = try authority.call("end_history_group", instance: id, at: 1.1)
        try permissions(["local", "remote"], at: 1.2)
        let denied = try authority.call("undo", instance: id, at: 1.3)
        let deniedValues = try authority.values(instance: id, at: 1.3)
        try permissions(["local", "remote", "history"], at: 1.4)
        let allowed = try authority.call("undo", instance: id, at: 1.5)
        let allowedValues = try authority.values(instance: id, at: 1.5)
        _ = try authority.call("destroy", instance: id, at: 1.6)
        return ["denied": denied, "denied_values": deniedValues, "allowed": allowed, "allowed_values": allowedValues]
    }
}
