import SurfaceDeviceContracts

/// Actual in-memory native receiver for this hypothetical protocol. Acceptance
/// validates/updates the lamp only; it emits no operator input or observation.
public struct MinimalDisplayBackend: Sendable {
    public private(set) var received: [MinimalPacket] = []
    public private(set) var lastAcceptedBrightness: Double?
    public init() {}
    public mutating func receive(_ packet: MinimalPacket) throws {
        guard case .brightness(let address, let value) = packet, address == "lamp.output",
              value.isFinite, (0...127).contains(value) else { throw MinimalCodecError.invalidValue }
        lastAcceptedBrightness = value
        received.append(packet)
    }
}
