import Foundation
import MinimalDeviceAdapter
import SurfaceDeviceContracts
import SurfaceBindingContext
import SurfaceConnectionState

private enum Failure: Error { case missingInput, wrongValue(String), missingFailure }

@main
private struct CodecBoundaryRunner {
    static func main() {
        do { try run() }
        catch {
            try? FileHandle.standardError.write(contentsOf: Data((String(describing: error) + "\n").utf8))
            exit(1)
        }
    }
    static func run() throws {
        guard CommandLine.arguments.count == 2 else { throw Failure.wrongValue("output path") }
        let context = try DeviceContext(id: "lifecycle", generation: "epoch1", mappingRevision: "page1")
        let endpoint = try EndpointProvenance(endpointID: "owned.simulated.input", deviceID: nil, connectionGeneration: 1, transportOrigin: .localVirtual)
        let absolute = MinimalDeviceAdapter(mode: .absolute), relative = MinimalDeviceAdapter(mode: .relative)
        var absoluteModel = MinimalPhysicalModel(mode: .absolute)
        do { _ = try absoluteModel.turn(by: 20); throw Failure.missingFailure }
        catch MinimalCodecError.unknownAbsolutePosition {}
        let report = try absolute.decodePacket(.positionInContext(address: "knob.input", value: 127, hardwareContext: "context2"),
            context: context, endpoint: endpoint, source: .simulation, at: 0.1)
        absoluteModel.noteDecoded(report)
        let turn = try absoluteModel.turn(by: 20)
        let turned = try absolute.decodePacket(turn, context: context, endpoint: endpoint, source: .simulation, at: 0.2)
        guard turned.input?.kind == .absolute, case .number(let saturated) = turned.input?.value, saturated == 127 else { throw Failure.wrongValue("absolute saturation") }
        absoluteModel.noteDecoded(turned)
        var relativeModel = MinimalPhysicalModel(mode: .relative)
        var deltaSum = 0.0
        var decodedRelativePackets = 0
        for index in 0..<20 {
            let packet = try relativeModel.turn(by: 1)
            let decoded = try relative.decodePacket(packet, context: context, endpoint: endpoint, source: .simulation, at: Double(index) / 10)
            guard let input = decoded.input, input.kind == .relative, case .number(let value) = input.value else { throw Failure.missingInput }
            relativeModel.noteDecoded(decoded); deltaSum += value; decodedRelativePackets += 1
        }
        guard deltaSum == 20, relativeModel.lastReportedAbsolutePosition == nil else { throw Failure.wrongValue("relative invented position") }
        guard try relative.decode(.position(address: "knob.input", value: 20), context: context, endpoint: endpoint, source: .simulation, at: 2) == nil,
              try absolute.decode(.delta(address: "knob.delta", value: 1), context: context, endpoint: endpoint, source: .simulation, at: 2) == nil else {
            throw Failure.wrongValue("wrong-mode packet accepted")
        }
        let page1 = BindingContext(context: context, entries: [try ContextBinding(elementID: "knob", facetID: "page1", inputKind: .absolute, targetReferenceID: "p1")])
        var bindings = BindingContextState(page1)
        let page2Context = try DeviceContext(id: "lifecycle", generation: "epoch2", mappingRevision: "page2")
        let transition = bindings.apply(BindingContext(context: page2Context,
            entries: [try ContextBinding(elementID: "knob", facetID: "page2", inputKind: .absolute, targetReferenceID: "p2")]))
        guard transition.changed, absoluteModel.lastReportedHardwareContext == "context2",
              bindings.current.target(elementID: "knob", facetID: "page2", inputKind: .absolute) == "p2" else {
            throw Failure.wrongValue("software page replaced hardware evidence")
        }
        let untagged = try absolute.decodePacket(.position(address: "knob.input", value: 32), context: page2Context,
            endpoint: endpoint, source: .simulation, at: 2.1)
        absoluteModel.noteDecoded(untagged)
        guard untagged.observations.isEmpty, absoluteModel.lastReportedHardwareContext == "context2" else { throw Failure.wrongValue("UI filled hardware context") }
        let caps = try absolute.capabilities()
        let sameControlIO = caps.modes.contains { $0.elements.contains { !$0.inputs.isEmpty && !$0.displays.isEmpty } }
        guard caps.modes.map(\.id) == ["absolute", "relative"], caps.modes.allSatisfy({ $0.elements.map(\.elementID) == ["knob", "button", "lamp"] }),
              caps.modes.allSatisfy({ mode in !mode.elements.contains { !$0.inputs.isEmpty && !$0.displays.isEmpty } }) else {
            throw Failure.wrongValue("invented physical I/O role")
        }
        do {
            _ = try absolute.decodePacket(.contextReport(""), context: context, endpoint: endpoint, source: .simulation, at: 3)
            throw Failure.missingFailure
        } catch MinimalCodecError.emptyHardwareContext {}
        let brightness = try EffectDescriptor(id: "existing.reference", targetID: "lamp", affectedElements: ["lamp"], value: .number(64),
            classification: .display, sideEffects: [], context: context, endpoint: endpoint, source: .simulation, timing: .immediate, at: 3)
        guard let encoded = absolute.encode(brightness), try absolute.decode(encoded, context: context, endpoint: endpoint, source: .simulation, at: 3) == nil else {
            throw Failure.wrongValue("display became input")
        }
        let reportedBeforeReconnect = absoluteModel.lastReportedHardwareContext
        let initialRoute = try ConnectionSnapshot(inputID: "owned.input", outputID: "owned.output", transportGeneration: 1, isConnected: true, extra: EmptyConnectionIdentity())
        var connection = ConnectionState(snapshot: initialRoute, connectionGeneration: 1)
        let replaced = connection.apply(try ConnectionSnapshot(inputID: "owned.input", outputID: "owned.output", transportGeneration: 2, isConnected: true, extra: EmptyConnectionIdentity()))
        if replaced.invalidatesScope { absoluteModel.invalidateConnectionEvidence() }
        guard absoluteModel.lastReportedAbsolutePosition == nil, absoluteModel.lastReportedHardwareContext == nil else { throw Failure.wrongValue("reused connection evidence") }
        do { _ = try absoluteModel.turn(by: 1); throw Failure.missingFailure }
        catch MinimalCodecError.unknownAbsolutePosition {}
        let value: [String: Any] = ["artifact": "minimal-codec-boundary-auxiliary-only", "shared_scenarios_executed": 0,
            "source": "simulation", "absolute_saturation": saturated, "relative_packets": decodedRelativePackets, "relative_delta_sum": deltaSum,
            "relative_absolute_observation": relativeModel.lastReportedAbsolutePosition.map { $0 as Any } ?? NSNull(),
            "actual_reported_hardware_context_before_reconnect": reportedBeforeReconnect.map { $0 as Any } ?? NSNull(),
            "absolute_observation_after_reconnect": absoluteModel.lastReportedAbsolutePosition.map { $0 as Any } ?? NSNull(),
            "hardware_context_after_reconnect": absoluteModel.lastReportedHardwareContext.map { $0 as Any } ?? NSNull(),
            "software_mapping_revision": bindings.current.context.mappingRevision.map { $0 as Any } ?? NSNull(),
            "physical_roles": caps.modes[0].elements.map(\.elementID), "protocol_modes": caps.modes.map(\.id),
            "same_physical_control_independent_io": sameControlIO, "encoded_display_is_not_a_send": true]
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("CODEC_BOUNDARY_AUX_PASS modes=\(caps.modes.count) physical_roles=\(caps.modes[0].elements.count) relative_packets=\(decodedRelativePackets) shared_scenarios=0 output_attempts=0")
    }
}
