import Foundation

public enum FeedbackQueueError: Error, Equatable, Sendable {
    case invalidRate
    case nonfiniteTime
    case cooldownOverflow
}

/// Scheduling only. Removing an entry never authorizes or acknowledges output.
public enum FeedbackQueueRate: Equatable, Sendable {
    case unlimited
    case bucket(perSecond: Double, burst: Int, failureCooldown: Double)

    fileprivate func validate() throws {
        if case let .bucket(rate, burst, cooldown) = self {
            guard rate.isFinite, rate > 0, burst > 0, burst <= 1_000_000,
                  cooldown.isFinite, cooldown >= 0 else { throw FeedbackQueueError.invalidRate }
        }
    }
}

public struct FeedbackQueueEntry<Key: Hashable & Sendable, Item: Sendable>: Sendable {
    public let key: Key
    public let item: Item
    public init(key: Key, item: Item) { self.key = key; self.item = item }
}
extension FeedbackQueueEntry: Equatable where Item: Equatable {}

/// A value-owned FIFO with last-value replacement, explicit time and no I/O.
/// Caller-owned payload includes whatever scope and attribution it must retain.
public struct FeedbackQueue<Key: Hashable & Sendable, Item: Sendable>: Sendable {
    public let rate: FeedbackQueueRate
    private var items: [Key: Item] = [:]
    public private(set) var orderedKeys: [Key] = []
    public private(set) var tokens: Double?
    public private(set) var lastRefill: Double?
    public private(set) var retryAfter: Double?

    public init(rate: FeedbackQueueRate) throws {
        try rate.validate()
        self.rate = rate
        if case let .bucket(_, burst, _) = rate { tokens = Double(burst) }
    }

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }
    public var orderedEntries: [FeedbackQueueEntry<Key, Item>] {
        orderedKeys.map { FeedbackQueueEntry(key: $0, item: items[$0]!) }
    }
    public func item(for key: Key) -> Item? { items[key] }

    /// Replacement retains the original position. Cancel and reinsert appends.
    @discardableResult
    public mutating func enqueue(_ item: Item, for key: Key) -> Item? {
        if items[key] == nil { orderedKeys.append(key) }
        return items.updateValue(item, forKey: key)
    }

    @discardableResult
    public mutating func cancel(_ key: Key) -> Item? {
        guard let removed = items.removeValue(forKey: key) else { return nil }
        orderedKeys.removeAll { $0 == key }
        return removed
    }

    /// A failed input leaves every field unchanged. Finite signed instants are
    /// valid. Backwards time resets the balance to zero, then anchors refill.
    public mutating func drain(at instant: Double) throws -> [FeedbackQueueEntry<Key, Item>] {
        guard instant.isFinite else { throw FeedbackQueueError.nonfiniteTime }
        if case let .bucket(perSecond, burst, _) = rate {
            if let previous = lastRefill {
                let elapsed = instant - previous
                tokens = elapsed < 0 ? 0 : min(Double(burst), tokens! + elapsed * perSecond)
            }
            lastRefill = instant
        }
        guard retryAfter.map({ instant < $0 }) != true else { return [] }
        let amount = min(orderedKeys.count, tokens.map(Int.init) ?? orderedKeys.count)
        let keys = Array(orderedKeys.prefix(amount))
        let removed = keys.map { FeedbackQueueEntry(key: $0, item: items.removeValue(forKey: $0)!) }
        orderedKeys.removeFirst(amount)
        if tokens != nil { tokens! -= Double(removed.count) }
        return removed
    }

    /// Failure does not refund tokens or automatically reinsert drained work.
    public mutating func noteFailure(at instant: Double) throws {
        guard instant.isFinite else { throw FeedbackQueueError.nonfiniteTime }
        if case let .bucket(_, _, cooldown) = rate {
            let deadline = instant + cooldown
            guard deadline.isFinite else { throw FeedbackQueueError.cooldownOverflow }
            retryAfter = deadline
        }
    }

    /// Lifecycle invalidation resets the bucket and discards queued work. The
    /// adapter invalidates its independent scope, native evidence and receipts.
    @discardableResult
    public mutating func clear() -> [Key] {
        let removed = orderedKeys
        items.removeAll(); orderedKeys.removeAll(); lastRefill = nil; retryAfter = nil
        if case let .bucket(_, burst, _) = rate { tokens = Double(burst) }
        return removed
    }
}
