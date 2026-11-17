import MinimalDeviceAdapter
import SurfaceDeviceContracts
import SurfaceBindingContext
import SurfaceDeviceConformance
import SurfaceControlContracts
import PlatformRuntime

/// Device-specific assembly for this fixture consumer. This is counted in
/// addition to the protocol/physical/receiver files, never hidden in runtime LOC.
/// Logical axis/button/meter are fixture vocabulary; knob/lamp are physical roles.
enum MinimalFixtureWiring {
    static let endpointDisplayName = "minimal offline"
    static func contextReport(_ tag: String) -> MinimalPacket { .contextReport(tag) }
    static let inputRole = "knob"
    static let outputRole = "lamp"
    static func physicalInput(for logical: String) -> String { logical == "axis" ? inputRole : logical }
    static func logicalInput(for physical: String) -> String { physical == inputRole ? "axis" : physical }
    static func bindingKind(logical: String, mode: MinimalProtocolMode) -> InputKind {
        logical == "button" ? .press : (mode == .absolute ? .absolute : .relative)
    }
    static func input(logical: String, value: Double, context: String) -> MinimalPacket {
        .positionInContext(address: "knob.input", value: value, hardwareContext: context)
    }
    static func button(_ pressed: Bool) -> MinimalPacket { .button(address: "button.input", pressed: pressed) }
    static func relative(_ value: Double, context: String) -> MinimalPacket {
        .deltaInContext(address: "knob.delta", value: value, hardwareContext: context)
    }
    static func untaggedAbsolute(_ value: Double) -> MinimalPacket { .position(address: "knob.input", value: value) }
    static func unconfigured(logical: String, value: Double) -> MinimalPacket {
        .position(address: logical == "meter" ? "lamp.input" : logical + ".input", value: value)
    }
    static func displayValue(_ packet: MinimalPacket) -> Double? {
        if case .brightness(_, let value) = packet { return value }; return nil
    }
    static func packetRecord(_ packet: MinimalPacket) -> [String: Any] {
        switch packet {
        case let .position(address, value): return ["kind": "position", "address": address, "value": value]
        case let .delta(address, value): return ["kind": "delta", "address": address, "value": value]
        case let .positionInContext(address, value, tag): return ["kind": "positionInContext", "address": address, "value": value, "hardware_context": tag]
        case let .deltaInContext(address, value, tag): return ["kind": "deltaInContext", "address": address, "value": value, "hardware_context": tag]
        case let .contextReport(tag): return ["kind": "contextReport", "hardware_context": tag]
        case let .button(address, pressed): return ["kind": "button", "address": address, "pressed": pressed]
        case let .brightness(address, value): return ["kind": "brightness", "address": address, "value": value]
        }
    }
    static func profile(pages: [String: [[String: ScenarioPayload]]], page: String, mode: MinimalProtocolMode, source: DeviceSource) throws -> ControlProfile {
        guard let bindings = pages[page] else { throw CompositionError.shape("page") }
        let axis = try bindings.first(where: { try string($0["element_id"]) == "axis" }).map { try string($0["target_id"]) }
        let button = try bindings.first(where: { try string($0["element_id"]) == "button" }).map { try string($0["target_id"]) }
        let relative = mode == .relative
        return ControlProfile(id: "minimal.complete", version: source == .hardware ? "1.4" : "1.3", controls: [
            .init(id: "axis", inputKind: relative ? .relative : .absolute, encoding: relative ? .signedDelta : .scalar,
                range: .init(minimum: relative ? -127 : 0, maximum: 127), feedbackRange: .init(minimum: 0, maximum: 127), feedbackKinds: [.value],
                mapping: axis.map { .init(kind: .parameter, id: $0) }, acceptsInput: source == .simulation),
            .init(id: "button", inputKind: .button, encoding: .boolean, mapping: button.map { .init(kind: .action, id: $0) }, acceptsInput: source == .simulation)
        ], capabilities: [source == .hardware ? "hardware" : "simulation", "controls.input_declared", relative ? "input.relative" : "input.absolute", "input.button", "feedback.value", "feedback.unsequenced"])
    }
    static func bindings(pages: [String: [[String: ScenarioPayload]]], page: String, mode: MinimalProtocolMode, context: DeviceContext) throws -> BindingContext {
        guard let rows = pages[page] else { throw CompositionError.shape("page") }
        let entries = try rows.map { row -> ContextBinding in
            let logical = try string(row["element_id"])
            return try ContextBinding(elementID: physicalInput(for: logical), facetID: page,
                inputKind: bindingKind(logical: logical, mode: mode), targetReferenceID: string(row["target_id"]))
        }
        return BindingContext(context: context, entries: entries)
    }
}
