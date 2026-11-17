import Foundation
import MinimalDeviceAdapter
import SurfaceDeviceContracts
import SurfaceBindingContext
import SurfaceConnectionState
import SurfaceDeviceConformance
import SurfacePluginContracts
import SurfaceControlContracts
import RemoteToolContracts
import AgentPlugin
import AgentRemoteBinding

private enum CheckpointError: Error {
    case shape(String)
    case requiresJ4Dispatch
    case unsupportedOperation(String)
}

private func object(_ payload: ScenarioPayload) throws -> [String: ScenarioPayload] {
    guard case .object(let fields) = payload else { throw CheckpointError.shape("object") }
    return fields
}
private func text(_ value: ScenarioPayload?) throws -> String {
    guard case .scalar(.text(let text)) = value else { throw CheckpointError.shape("text") }
    return text
}
private func number(_ value: ScenarioPayload?) throws -> Double {
    guard case .scalar(.number(let number)) = value else { throw CheckpointError.shape("number") }
    return number
}

/// Caller-owned test composition. Execution receives no ScenarioAssertion value.
private struct CheckpointDevice {
    let instanceID: String
    let adapter = MinimalDeviceAdapter()
    let capabilities: DeviceCapabilities
    let bindings: BindingContext
    var connection: ConnectionState<EmptyConnectionIdentity>
    var session: SurfaceControlSession
    var registry: RemoteRegistry
    let actionBaseline: UInt64
    let capturedAuthorization: ContextScope
    var currentEndpoint: EndpointProvenance
    var pending = ContextResourceIndex<String, ContextScope>()
    var displayPayloads: [String: EffectDescriptor] = [:]
    var revokedIDs: [String] = []
    var transportOutputs: [MinimalPacket] = []
    var attachments: [(incoming: EndpointProvenance, captured: EndpointProvenance)] = []
    // Explicit provider qualification evidence. No endpoint operation can create
    // a qualification record; none exists for this hypothetical offline device.
    let verifiedQualificationRecords: [String] = []

    init(instanceID: String, deviceID: String, generation: UInt64, wrongBinding: Bool) throws {
        self.instanceID = instanceID
        capabilities = try adapter.capabilities()
        let route = try ConnectionSnapshot(inputID: "endpoint." + instanceID + ".input",
            outputID: "endpoint." + instanceID + ".output", transportGeneration: generation,
            isConnected: true, extra: EmptyConnectionIdentity())
        connection = ConnectionState(snapshot: route, connectionGeneration: generation)
        currentEndpoint = try EndpointProvenance(endpointID: route.outputID, deviceID: deviceID,
            connectionGeneration: generation, transportOrigin: .localVirtual)
        let profile = ControlProfile(id: "minimal.offline", version: "1.4", controls: [
            .init(id: "axis", inputKind: .absolute, encoding: .scalar, range: .init(minimum: 0, maximum: 127),
                  feedbackKinds: [.value], mapping: .init(kind: .parameter, id: "p1"), acceptsInput: false),
            .init(id: "button", inputKind: .button, encoding: .boolean,
                  mapping: .init(kind: .action, id: "fire1"), acceptsInput: false),
            .init(id: "meter", inputKind: .absolute, encoding: .scalar, range: .init(minimum: 0, maximum: 127),
                  feedbackKinds: [.value], acceptsInput: false)
        ], capabilities: ["hardware", "input.absolute", "input.button", "feedback.value", "controls.input_declared"])
        session = try SurfaceControlSession(instanceID: instanceID, epoch: instanceID + ".bootstrap", profile: profile)
        try session.transitionHardware(epoch: instanceID + ".connection." + String(generation), linkState: .connected, at: 0)
        let context = try DeviceContext(id: instanceID, generation: session.expected.epoch, mappingRevision: session.expected.mapping_revision)
        var entries = try [
            ContextBinding(elementID: "knob", facetID: "page1", inputKind: .absolute, targetReferenceID: "p1"),
            ContextBinding(elementID: "button", facetID: "page1", inputKind: .press, targetReferenceID: "fire1")
        ]
        if wrongBinding {
            entries.append(try ContextBinding(elementID: "lamp", facetID: "page1", inputKind: .absolute, targetReferenceID: "enable"))
        }
        bindings = BindingContext(context: context, entries: entries)
        capturedAuthorization = ContextScope(source: .hardware, context: context, endpoint: currentEndpoint)
        registry = try RemoteRegistry(epoch: instanceID + ".actions", eventCapacity: 16)
        for action in ["fire1", "fire2"] {
            try registry.install(AgentRemoteBinding(instanceID: action, plugin: AgentPlugin(slotCount: 1)))
            _ = try registry.handle(instanceID: action, input: .start, at: 0)
        }
        actionBaseline = try registry.journal.read(epoch: registry.journal.epoch, after: 0).latestSequence
    }

    func scope() throws -> ContextScope {
        ContextScope(source: .hardware,
            context: try DeviceContext(id: instanceID, generation: session.expected.epoch, mappingRevision: session.expected.mapping_revision),
            endpoint: currentEndpoint)
    }

    func metrics() throws -> [String: TraceValue] {
        let actions = try registry.journal.read(epoch: registry.journal.epoch, after: actionBaseline).events
        return [
            "route_generation": .number(Double(connection.connectionGeneration)),
            "old_authorization_valid": .flag(try scope().matches(capturedAuthorization)),
            "device_output_count": .number(Double(transportOutputs.count)),
            "pending_display_count": .number(Double(pending.count)),
            "revoked_display_count": .number(Double(revokedIDs.count)),
            "control_sequence": .text(session.discovery().latest_sequence),
            "enable_binding_count": .number(Double(bindings.entries.filter { $0.targetReferenceID == "enable" }.count)),
            "action_fire1_count": .number(Double(actions.filter { $0.instanceID == "fire1" }.count)),
            "provenance_preserved": .flag(attachments.allSatisfy { $0.incoming == $0.captured }),
            "qualification_upgraded": .flag(!verifiedQualificationRecords.isEmpty)
        ]
    }

    mutating func execute(operation: String, arguments: ScenarioPayload, at: Double, wrongRoute: Bool) throws {
        let arguments = try object(arguments)
        switch operation {
        case "prepare_display":
            // J2 immutable descriptor and actual J3 scoped inventory, not a J4
            // send permit or fabricated transport acceptance.
            let id = instanceID + ".pending." + String(pending.count)
            let scope = try scope()
            let effect = try EffectDescriptor(id: id, targetID: "lamp", affectedElements: ["lamp"],
                value: .number(try number(arguments["value"])), classification: .display, sideEffects: [],
                context: scope.context, endpoint: currentEndpoint, source: .hardware, timing: .immediate, at: at)
            displayPayloads[id] = effect
            pending.upsert(id, scope: scope)
        case "replace_route":
            let supplied = try number(arguments["route_generation"])
            guard let generation = UInt64(exactly: supplied) else { throw CheckpointError.shape("generation") }
            let newGeneration = wrongRoute ? connection.connectionGeneration : generation
            let snapshot = try ConnectionSnapshot(inputID: connection.snapshot.inputID,
                outputID: connection.snapshot.outputID, transportGeneration: newGeneration,
                isConnected: true, extra: EmptyConnectionIdentity())
            let transition = connection.apply(snapshot)
            if transition.clearPending {
                let removed = pending.removeAll()
                revokedIDs += removed
                for id in removed { displayPayloads.removeValue(forKey: id) }
            }
            if transition.invalidatesScope {
                currentEndpoint = try EndpointProvenance(endpointID: snapshot.outputID, deviceID: currentEndpoint.deviceID,
                    connectionGeneration: connection.connectionGeneration, transportOrigin: currentEndpoint.transportOrigin)
                try session.transitionHardware(epoch: instanceID + ".connection." + String(connection.connectionGeneration), linkState: .connected, at: at)
            }
        case "flush":
            // Only a cancellation-complete flush is executable at this J3 stage.
            // Positive dispatch must use the real J4 implementation later.
            guard pending.isEmpty else { throw CheckpointError.requiresJ4Dispatch }
        case "receive_unconfigured":
            let element = try text(arguments["element_id"])
            let address = element == "meter" ? "lamp.input" : element + ".input"
            let packet = MinimalPacket.position(address: address, value: try number(arguments["value"]))
            let current = try scope()
            if let event = try adapter.decode(packet, context: current.context, endpoint: currentEndpoint, source: .hardware, at: at) {
                // No supported decoder input exists for these addresses. A future
                // valid input needs the actual authority bridge, not a fake value.
                _ = bindings.target(elementID: event.elementID, facetID: "page1", inputKind: event.kind)
                throw CheckpointError.unsupportedOperation("supported parameter input requires authority integration")
            }
        case "attach_endpoint":
            let endpoint = try text(arguments["endpoint_id"])
            let rawOrigin = try text(arguments["provenance"])
            let origin: EndpointTransportOrigin
            switch rawOrigin {
            case "remote_virtual": origin = .remoteVirtual
            case "physical_usb": origin = .physicalUSB
            default: throw CheckpointError.shape("provenance")
            }
            let generation = connection.connectionGeneration + 1
            let incoming = try EndpointProvenance(endpointID: endpoint, deviceID: nil,
                connectionGeneration: generation, transportOrigin: origin)
            let transition = connection.apply(try ConnectionSnapshot(inputID: endpoint, outputID: endpoint,
                transportGeneration: generation, isConnected: true, extra: EmptyConnectionIdentity()))
            if transition.clearPending {
                let removed = pending.removeAll(); revokedIDs += removed
                for id in removed { displayPayloads.removeValue(forKey: id) }
            }
            currentEndpoint = incoming
            attachments.append((incoming, currentEndpoint))
            try session.transitionHardware(epoch: instanceID + ".connection." + String(generation), linkState: .connected, at: at)
        default: throw CheckpointError.unsupportedOperation(operation)
        }
    }
}

private struct CheckpointRow: Encodable {
    let id: String
    let status: ScenarioStatus
    let steps: [ScenarioStepTrace]
    let assertionsChecked: Int
    let failedAssertions: [String]
    let pendingIDs: [String]
    let revokedIDs: [String]
    let endpoint: TraceValue
    let endpointDeviceID: TraceValue
    let endpointOrigin: String
    let attachmentOrigins: [String]
    let sourceSequence: String
    let capabilityPhysicalRoles: [String]
    let qualificationRecordCount: Int
}

private struct CheckpointArtifact: Encodable {
    let artifact = "minimal-device-j3-checkpoint-only"
    let fullInventoryAcceptance = false
    let selectedScenarioIDs: [String]
    let fault: String
    let rows: [CheckpointRow]
}

@main
private struct CheckpointRunner {
    static func main() {
        do { try run() }
        catch {
            try? FileHandle.standardError.write(contentsOf: Data((String(describing: error) + "\n").utf8))
            exit(1)
        }
    }

    static func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 3 else { throw CheckpointError.shape("usage: fixture output fault") }
        let catalog = try ScenarioCatalog.decode(data: Data(contentsOf: URL(fileURLWithPath: args[0])))
        let selected = ["T12", "T28", "T30"]
        let fault = args[2]
        guard ["none", "wrong_route", "wrong_binding"].contains(fault) else { throw CheckpointError.shape("fault") }
        var rows: [CheckpointRow] = []
        for id in selected {
            guard let scenario = catalog.scenarios.first(where: { $0.id == id }),
                  case .array(let instances) = try object(scenario.setup)["instances"],
                  let first = instances.first else { throw CheckpointError.shape("setup") }
            let setup = try object(first)
            var device = try CheckpointDevice(instanceID: text(setup["id"]), deviceID: text(setup["device_id"]),
                generation: UInt64(exactly: number(setup["route_generation"]))!, wrongBinding: fault == "wrong_binding")
            var steps: [ScenarioStepTrace] = []
            var failed: [String] = []
            var assertionsChecked = 0
            for (index, step) in scenario.steps.enumerated() {
                let before: TraceObservations = [device.instanceID: try device.metrics()]
                var error: String?
                do {
                    try device.execute(operation: step.operation, arguments: step.arguments, at: Double(index + 1) / 10, wrongRoute: fault == "wrong_route")
                } catch let failure { error = String(describing: failure) }
                let after: TraceObservations = [device.instanceID: try device.metrics()]
                // Expectations are accessed only after execution is complete.
                for assertion in step.expect {
                    assertionsChecked += 1
                    if try !AssertionEvaluator.evaluate(assertion, instanceID: step.instanceID, before: before, after: after) {
                        failed.append(step.operation + ":" + assertion.metric)
                    }
                }
                if let error { failed.append(step.operation + ":" + error) }
                let passed = error == nil && step.expect.allSatisfy {
                    (try? AssertionEvaluator.evaluate($0, instanceID: step.instanceID, before: before, after: after)) == true
                }
                steps.append(ScenarioStepTrace(index: index, operation: step.operation, status: passed ? .pass : .fail,
                    reason: error ?? (passed ? nil : "original_assertion_failed"), before: before, after: after, effects: []))
            }
            rows.append(CheckpointRow(id: id, status: failed.isEmpty ? .pass : .fail, steps: steps,
                assertionsChecked: assertionsChecked, failedAssertions: failed, pendingIDs: device.pending.orderedIDs,
                revokedIDs: device.revokedIDs, endpoint: device.currentEndpoint.endpointID.map(TraceValue.text) ?? .null,
                endpointDeviceID: device.currentEndpoint.deviceID.map(TraceValue.text) ?? .null,
                endpointOrigin: device.currentEndpoint.transportOrigin.rawValue,
                attachmentOrigins: device.attachments.map { $0.captured.transportOrigin.rawValue },
                sourceSequence: device.session.discovery().latest_sequence,
                capabilityPhysicalRoles: device.capabilities.modes[0].elements.map(\.elementID),
                qualificationRecordCount: device.verifiedQualificationRecords.count))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let artifact = CheckpointArtifact(selectedScenarioIDs: selected, fault: fault, rows: rows)
        try encoder.encode(artifact).write(to: URL(fileURLWithPath: args[1]))
        let passed = rows.filter { $0.status == .pass }.count
        print("J3_CHECKPOINT scenarios=\(rows.count) pass=\(passed) fail=\(rows.count - passed) steps=\(rows.reduce(0) { $0 + $1.steps.count }) assertions=\(rows.reduce(0) { $0 + $1.assertionsChecked }) full_inventory=false fault=\(fault)")
        if passed != rows.count { exit(1) }
    }
}
