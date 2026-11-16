import SurfaceDeviceContracts

// Hypothetical device knowledge only. No parameter authority or runtime reducer.
enum MinimalPacket: Equatable, Sendable {
    case knobPosition(Double)
    case buttonPressed(Bool)
    case lampLevel(Double)
}

struct MinimalDeviceAdapter: Sendable {
    func capabilities() throws -> DeviceCapabilities {
        let knob = try ElementCapability(elementID: "knob", inputs: [InputCapability(kind: .absolute, valueKind: .number)], displays: [], effects: [])
        let button = try ElementCapability(elementID: "button", inputs: [InputCapability(kind: .press, valueKind: .flag), InputCapability(kind: .release, valueKind: .flag)], displays: [], effects: [])
        let lamp = try ElementCapability(elementID: "lamp", inputs: [], displays: [DisplayCapability(kind: "brightness", valueKind: .number)],
                                         effects: [EffectCapability(kind: "brightness", classification: .display, sideEffects: [])])
        return try DeviceCapabilities(profileID: "minimal.test", modes: [ProtocolModeCapability(id: "native", elements: [knob, button, lamp])])
    }

    func decode(_ packet: MinimalPacket, context: DeviceContext, endpoint: EndpointProvenance,
                source: DeviceSource, at: Double) throws -> DeviceInputEvent? {
        switch packet {
        case .knobPosition(let value):
            return try DeviceInputEvent(elementID: "knob", kind: .absolute, value: .number(value), context: context, endpoint: endpoint, source: source, at: at)
        case .buttonPressed(let pressed):
            return try DeviceInputEvent(elementID: "button", kind: pressed ? .press : .release, value: .flag(pressed), context: context, endpoint: endpoint, source: source, at: at)
        case .lampLevel: return nil
        }
    }

    func encode(_ effect: EffectDescriptor) -> MinimalPacket? {
        guard effect.targetID == "lamp", effect.requiredDirections == [.display],
              case .number(let value) = effect.value, (0...127).contains(value) else { return nil }
        return .lampLevel(value)
    }
}
