import SurfaceDeviceContracts

/// Hypothetical device protocol/physical evidence only; never a business value store.
public struct MinimalPhysicalModel: Sendable {
    public let mode: MinimalProtocolMode
    public private(set) var lastReportedAbsolutePosition: Double?
    public private(set) var lastReportedHardwareContext: String?
    public init(mode: MinimalProtocolMode) { self.mode = mode }

    /// New transport evidence starts unknown; it never restores a desired value.
    public mutating func invalidateConnectionEvidence() {
        lastReportedAbsolutePosition = nil
        lastReportedHardwareContext = nil
    }

    public mutating func noteDecoded(_ decoded: MinimalDecodedPacket) {
        if mode == .absolute, let input = decoded.input, input.kind == .absolute, input.elementID == "knob",
           case .number(let value) = input.value { lastReportedAbsolutePosition = value }
        for observation in decoded.observations where observation.targetID == "device.hardware-context" && observation.state == .observed && observation.evidence == .deviceReport {
            if case .text(let context) = observation.value { lastReportedHardwareContext = context }
        }
    }

    public mutating func turn(by delta: Double) throws -> MinimalPacket {
        guard delta.isFinite, (-127...127).contains(delta) else { throw MinimalCodecError.invalidValue }
        if mode == .relative { return .delta(address: "knob.delta", value: delta) }
        guard let previous = lastReportedAbsolutePosition else { throw MinimalCodecError.unknownAbsolutePosition }
        let value = min(max(previous + delta, 0), 127)
        lastReportedAbsolutePosition = value
        return .position(address: "knob.input", value: value)
    }
}
