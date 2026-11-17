import Foundation

/// Strict value decoding without normalization or scheduler schema admission.
/// The legacy Data decoder retains its original lexical guard/error ordering.
struct SchedulerStrictJSON: Sendable {
    private let bytes: [UInt8]
    // One private decoder per validation call; never shared across calls/tasks.
    private let scalarDecoder = JSONDecoder()
    private var index = 0

    static func decode(_ data: Data) throws -> ScenarioPayload {
        guard data.count <= 1_048_576 else { throw SchedulerCandidateError.invalid("trace size") }
        guard String(data: data, encoding: .utf8) != nil else { throw SchedulerCandidateError.invalid("JSON UTF8") }
        var parser = SchedulerStrictJSON(bytes: Array(data))
        let payload = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw SchedulerCandidateError.invalid("trailing JSON") }
        return payload
    }
    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }
    private func digit(_ byte: UInt8?) -> Bool { byte.map { (48...57).contains($0) } ?? false }
    private func hex(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }
    private mutating func whitespace() {
        while let byte = current, [9, 10, 13, 32].contains(byte) { index += 1 }
    }
    private mutating func take(_ byte: UInt8) throws {
        whitespace()
        guard current == byte else { throw SchedulerCandidateError.invalid("JSON punctuation") }
        index += 1
    }
    private mutating func string() throws -> String {
        whitespace()
        guard current == 34 else { throw SchedulerCandidateError.invalid("JSON string") }
        let start = index
        index += 1
        while let byte = current {
            index += 1
            if byte == 34 {
                // Foundation preserves the existing escaped-key/Unicode rules.
                return try scalarDecoder.decode(String.self, from: Data(bytes[start..<index]))
            }
            guard byte >= 32 else { throw SchedulerCandidateError.invalid("JSON string control") }
            if byte == 92 {
                guard let escape = current else { throw SchedulerCandidateError.invalid("JSON escape") }
                index += 1
                if escape == 117 {
                    for _ in 0..<4 {
                        guard let byte = current, hex(byte) else { throw SchedulerCandidateError.invalid("JSON unicode escape") }
                        index += 1
                    }
                } else if ![34, 47, 92, 98, 102, 110, 114, 116].contains(escape) {
                    throw SchedulerCandidateError.invalid("JSON escape")
                }
            }
        }
        throw SchedulerCandidateError.invalid("unterminated string")
    }
    private mutating func literal(_ expected: [UInt8]) throws {
        for byte in expected {
            guard current == byte else { throw SchedulerCandidateError.invalid("JSON literal") }
            index += 1
        }
    }
    private mutating func number() throws -> Double {
        let start = index
        if current == 45 { index += 1 }
        if current == 48 {
            index += 1
            guard !digit(current) else { throw SchedulerCandidateError.invalid("JSON number") }
        } else {
            guard let byte = current, (49...57).contains(byte) else { throw SchedulerCandidateError.invalid("JSON number") }
            repeat { index += 1 } while digit(current)
        }
        if current == 46 {
            index += 1
            guard digit(current) else { throw SchedulerCandidateError.invalid("JSON number") }
            repeat { index += 1 } while digit(current)
        }
        if current == 69 || current == 101 {
            index += 1
            if current == 43 || current == 45 { index += 1 }
            guard digit(current) else { throw SchedulerCandidateError.invalid("JSON number") }
            repeat { index += 1 } while digit(current)
        }
        // Match Foundation's legacy Double token acceptance (including extreme
        // zero exponents and rejected nonzero underflow), not Double(String)'s
        // broader conversion-to-zero behavior. No recursive value decoding.
        let value = try scalarDecoder.decode(Double.self, from: Data(bytes[start..<index]))
        guard value.isFinite else {
            throw SchedulerCandidateError.invalid("nonfinite JSON number")
        }
        return value
    }
    private mutating func value(depth: Int) throws -> ScenarioPayload {
        guard depth <= 128 else { throw SchedulerCandidateError.invalid("JSON depth") }
        whitespace()
        guard let byte = current else { throw SchedulerCandidateError.invalid("missing JSON value") }
        switch byte {
        case 123:
            index += 1; whitespace()
            if current == 125 { index += 1; return .object([:]) }
            var values: [String: ScenarioPayload] = [:]
            while true {
                let key = try string()
                guard values[key] == nil else { throw SchedulerCandidateError.invalid("duplicate JSON key") }
                try take(58); values[key] = try value(depth: depth + 1); whitespace()
                if current == 125 { index += 1; return .object(values) }
                try take(44)
            }
        case 91:
            index += 1; whitespace()
            if current == 93 { index += 1; return .array([]) }
            var values: [ScenarioPayload] = []
            while true {
                values.append(try value(depth: depth + 1)); whitespace()
                if current == 93 { index += 1; return .array(values) }
                try take(44)
            }
        case 34: return .scalar(.text(try string()))
        case 116: try literal([116, 114, 117, 101]); return .scalar(.flag(true))
        case 102: try literal([102, 97, 108, 115, 101]); return .scalar(.flag(false))
        case 110: try literal([110, 117, 108, 108]); return .scalar(.null)
        case 45, 48...57: return .scalar(.number(try number()))
        default: throw SchedulerCandidateError.invalid("JSON value")
        }
    }
}
