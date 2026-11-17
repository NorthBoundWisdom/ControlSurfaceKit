import SurfaceDeviceContracts

public enum MinimalPacket: Equatable, Sendable {
    case position(address: String, value: Double)
    case delta(address: String, value: Double)
    case positionInContext(address: String, value: Double, hardwareContext: String)
    case deltaInContext(address: String, value: Double, hardwareContext: String)
    case contextReport(String)
    case button(address: String, pressed: Bool)
    case brightness(address: String, value: Double)
}

public enum MinimalProtocolMode: String, Equatable, Sendable, CaseIterable { case absolute, relative }
public enum MinimalCodecError: Error, Equatable, Sendable { case invalidValue, emptyHardwareContext, unknownAbsolutePosition }
public struct MinimalDecodedPacket: Sendable {
    public let input: DeviceInputEvent?
    public let observations: [DeviceObservation]
}

/// Hypothetical protocol/layout only; no fixture, authority or runtime imports.
public struct MinimalDeviceAdapter: Sendable {
    public let mode: MinimalProtocolMode
    public init(mode: MinimalProtocolMode = .absolute) { self.mode = mode }
    public func capabilities() throws -> DeviceCapabilities {
        let button = try ElementCapability(elementID: "button", inputs: [InputCapability(kind: .press, valueKind: .flag), InputCapability(kind: .release, valueKind: .flag)], displays: [], effects: [])
        let lamp = try ElementCapability(elementID: "lamp", inputs: [], displays: [DisplayCapability(kind: "brightness", valueKind: .number)],
            effects: [EffectCapability(kind: "brightness", classification: .display, sideEffects: [])])
        let modes = try MinimalProtocolMode.allCases.map { mode in
            let knob = try ElementCapability(elementID: "knob", inputs: [InputCapability(kind: mode == .absolute ? .absolute : .relative, valueKind: .number)], displays: [], effects: [])
            return try ProtocolModeCapability(id: mode.rawValue, elements: [knob, button, lamp])
        }
        return try DeviceCapabilities(profileID: "minimal.offline", modes: modes)
    }
    public func decode(_ packet: MinimalPacket, context: DeviceContext, endpoint: EndpointProvenance,
                       source: DeviceSource, at: Double) throws -> DeviceInputEvent? {
        try decodePacket(packet, context: context, endpoint: endpoint, source: source, at: at).input
    }
    public func decodePacket(_ packet: MinimalPacket, context: DeviceContext, endpoint: EndpointProvenance,
                             source: DeviceSource, at: Double) throws -> MinimalDecodedPacket {
        let input: DeviceInputEvent?
        var hardwareContext: String?
        switch packet {
        case let .position(address, value) where address == "knob.input" && mode == .absolute:
            guard value.isFinite, (0...127).contains(value) else { throw MinimalCodecError.invalidValue }
            input = try DeviceInputEvent(elementID: "knob", kind: .absolute, value: .number(value), context: context, endpoint: endpoint, source: source, at: at)
        case let .delta(address, value) where address == "knob.delta" && mode == .relative:
            guard value.isFinite, (-127...127).contains(value) else { throw MinimalCodecError.invalidValue }
            input = try DeviceInputEvent(elementID: "knob", kind: .relative, value: .number(value), context: context, endpoint: endpoint, source: source, at: at)
        case let .positionInContext(address, value, tag):
            guard !tag.isEmpty else { throw MinimalCodecError.emptyHardwareContext }
            let facet = try DeviceContext(id: context.id + ".reported." + tag, generation: context.generation, mappingRevision: context.mappingRevision)
            input = try decode(.position(address: address, value: value), context: facet, endpoint: endpoint, source: source, at: at)
            if input != nil { hardwareContext = tag }
        case let .deltaInContext(address, value, tag):
            guard !tag.isEmpty else { throw MinimalCodecError.emptyHardwareContext }
            let facet = try DeviceContext(id: context.id + ".reported." + tag, generation: context.generation, mappingRevision: context.mappingRevision)
            input = try decode(.delta(address: address, value: value), context: facet, endpoint: endpoint, source: source, at: at)
            if input != nil { hardwareContext = tag }
        case let .contextReport(tag):
            guard !tag.isEmpty else { throw MinimalCodecError.emptyHardwareContext }
            hardwareContext = tag; input = nil
        case let .button(address, pressed) where address == "button.input":
            input = try DeviceInputEvent(elementID: "button", kind: pressed ? .press : .release, value: .flag(pressed), context: context, endpoint: endpoint, source: source, at: at)
        default: input = nil
        }
        let observations = try hardwareContext.map { tag in
            [try DeviceObservation(targetID: "device.hardware-context", value: .text(tag), state: .observed, evidence: .deviceReport,
                context: context, endpoint: endpoint, source: source, at: at)]
        } ?? []
        return MinimalDecodedPacket(input: input, observations: observations)
    }
    public func encode(_ effect: EffectDescriptor) -> MinimalPacket? {
        guard effect.targetID == "lamp", effect.requiredDirections == [.display],
              case .number(let value) = effect.value, (0...127).contains(value) else { return nil }
        return .brightness(address: "lamp.output", value: value)
    }
}
