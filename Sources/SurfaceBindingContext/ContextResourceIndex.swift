import Foundation

/// Owns resource identity and order; payloads remain in their single native store.
/// It is not a sender, scheduler, parameter authority or observation store.
public struct ContextResourceIndex<ID: Hashable & Sendable, Scope: Equatable & Sendable>: Sendable {
    private struct Entry: Sendable { let scope: Scope }
    private var entries: [ID: Entry] = [:]
    public private(set) var orderedIDs: [ID] = []

    public init() {}
    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }
    public func contains(_ id: ID) -> Bool { entries[id] != nil }
    public func scope(for id: ID) -> Scope? { entries[id]?.scope }

    /// Replacing an existing resource does not move it behind later resources.
    public mutating func upsert(_ id: ID, scope: Scope) {
        if entries[id] == nil { orderedIDs.append(id) }
        entries[id] = Entry(scope: scope)
    }

    @discardableResult
    public mutating func remove(_ id: ID) -> Bool {
        guard entries.removeValue(forKey: id) != nil else { return false }
        orderedIDs.removeAll { $0 == id }
        return true
    }

    @discardableResult
    public mutating func removeFirst(_ count: Int) throws -> [ID] {
        guard count >= 0 else { throw BindingContextError.negativeRemovalCount }
        let removed = Array(orderedIDs.prefix(count))
        for id in removed { entries.removeValue(forKey: id) }
        orderedIDs.removeFirst(removed.count)
        return removed
    }

    @discardableResult
    public mutating func removeAll() -> [ID] {
        let removed = orderedIDs
        entries.removeAll()
        orderedIDs.removeAll()
        return removed
    }

    /// Explicit invalidation removes mismatching resources in registration order.
    /// Owners invoke it only at their established cancellation boundary.
    @discardableResult
    public mutating func invalidate(current scope: Scope) -> [ID] {
        let removed = orderedIDs.filter { entries[$0]?.scope != scope }
        for id in removed { entries.removeValue(forKey: id) }
        orderedIDs.removeAll { entries[$0] == nil }
        return removed
    }
}
