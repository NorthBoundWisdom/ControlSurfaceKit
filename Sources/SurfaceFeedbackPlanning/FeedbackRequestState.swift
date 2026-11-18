import Foundation

/// Equality phase is a scheduling choice, never a transport acknowledgement.
public enum RepeatedRequestPolicy: Equatable, Sendable {
    case proposeEveryRequest
    case suppressAfterProposal
    case suppressAfterAcceptedReceipt
}

public enum WithdrawnIntentPolicy: Equatable, Sendable {
    case discard
    case retainLatest
}

/// Opaque cache and withheld intents only. The caller defines exact value/scope
/// equality and supplies lifecycle invalidation; this is no device safety gate.
public struct FeedbackRequestState<Key: Hashable & Sendable, Value: Equatable & Sendable>: Sendable {
    public let repeatedRequestPolicy: RepeatedRequestPolicy
    public let withdrawnIntentPolicy: WithdrawnIntentPolicy
    public private(set) var proposed: [Key: Value] = [:]
    public private(set) var accepted: [Key: Value] = [:]
    public private(set) var withheld: [Key: Value] = [:]
    public private(set) var withheldKeys: [Key] = []

    public init(repeatedRequestPolicy: RepeatedRequestPolicy, withdrawnIntentPolicy: WithdrawnIntentPolicy) {
        self.repeatedRequestPolicy = repeatedRequestPolicy
        self.withdrawnIntentPolicy = withdrawnIntentPolicy
    }

    /// Returned values are proposals. Every-request mode never suppresses an
    /// invocation, even if identical output previously received acceptance.
    public mutating func request(_ value: Value, for key: Key) -> Value? {
        switch repeatedRequestPolicy {
        case .proposeEveryRequest: return value
        case .suppressAfterProposal:
            guard proposed[key] != value else { return nil }
            proposed[key] = value
            return value
        case .suppressAfterAcceptedReceipt:
            return accepted[key] == value ? nil : value
        }
    }

    /// Call only for a real, matched, successful receipt in the current scope,
    /// after the adapter's reentry/lifecycle checks. No receipt is fabricated.
    public mutating func recordAccepted(_ value: Value, for key: Key) {
        accepted[key] = value
    }

    /// A withheld value has not been proposed, sent, accepted or observed.
    public mutating func withhold(_ value: Value, for key: Key) {
        if withheld[key] == nil { withheldKeys.append(key) }
        withheld[key] = value
    }

    /// Returns this value owner's latest retained intent for fresh native
    /// evaluation. Release itself is neither a proposal nor permission to send.
    public mutating func release(_ key: Key) -> Value? {
        guard let value = withheld.removeValue(forKey: key) else { return nil }
        withheldKeys.removeAll { $0 == key }
        return value
    }

    /// Explicit withdrawal always invalidates caches. Retained intent cannot be
    /// sent until an explicit release and a new mandatory native evaluation.
    public mutating func withdraw(_ keys: [Key]) {
        invalidate(keys)
        if withdrawnIntentPolicy == .discard {
            for key in keys { _ = release(key) }
        }
    }

    public mutating func invalidate(_ keys: [Key]) {
        for key in keys { proposed.removeValue(forKey: key); accepted.removeValue(forKey: key) }
    }

    public mutating func cancel(_ key: Key) {
        _ = release(key)
        invalidate([key])
    }

    /// Connection/scope replacement never replays old retained intent.
    public mutating func clear() {
        proposed.removeAll(); accepted.removeAll(); withheld.removeAll(); withheldKeys.removeAll()
    }
}
