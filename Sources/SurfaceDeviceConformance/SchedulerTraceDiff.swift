import Foundation

public struct SchedulerTraceDifference: Equatable, Sendable {
    public let path: String
    public let reference: ScenarioPayload?
    public let candidate: ScenarioPayload?
}

/// Exact recursive comparison, no projection, tolerance, ignored field or
/// identifier remapping. Absent fields differ from explicit null.
public enum SchedulerTraceDiff: Sendable {
    public static func compare(reference: ScenarioPayload, candidate: ScenarioPayload) -> [SchedulerTraceDifference] {
        var differences: [SchedulerTraceDifference] = []
        visit(reference, candidate, path: "$", into: &differences)
        return differences
    }
    private static func visit(_ reference: ScenarioPayload?, _ candidate: ScenarioPayload?, path: String,
                              into differences: inout [SchedulerTraceDifference]) {
        switch (reference, candidate) {
        case (.object(let left), .object(let right)):
            for key in Set(left.keys).union(right.keys).sorted() { visit(left[key], right[key], path: path + "." + key, into: &differences) }
        case (.array(let left), .array(let right)):
            for index in 0..<max(left.count, right.count) {
                visit(index < left.count ? left[index] : nil, index < right.count ? right[index] : nil,
                      path: path + "[" + String(index) + "]", into: &differences)
            }
        default:
            if reference != candidate { differences.append(SchedulerTraceDifference(path: path, reference: reference, candidate: candidate)) }
        }
    }
}
