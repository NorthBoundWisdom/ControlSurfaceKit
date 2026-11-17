import Foundation

/// Small lexical guard for duplicate object keys/depth/size. JSONDecoder remains
/// the value decoder; this prevents its last-key-wins behavior hiding an input.
struct SchedulerJSONGuard: Sendable {
    private let bytes: [UInt8]
    private var index = 0

    static func validate(_ data: Data) throws {
        guard data.count <= 1_048_576 else { throw SchedulerCandidateError.invalid("trace size") }
        var guardValue = SchedulerJSONGuard(bytes: Array(data))
        try guardValue.value(depth: 0)
        guardValue.whitespace()
        guard guardValue.index == guardValue.bytes.count else { throw SchedulerCandidateError.invalid("trailing JSON") }
    }
    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }
    private mutating func whitespace() {
        while let byte = current, [9, 10, 13, 32].contains(byte) { index += 1 }
    }
    private mutating func take(_ expected: UInt8) throws {
        whitespace()
        guard current == expected else { throw SchedulerCandidateError.invalid("JSON punctuation") }
        index += 1
    }
    private mutating func string() throws -> String {
        whitespace()
        guard current == 34 else { throw SchedulerCandidateError.invalid("JSON string") }
        let start = index; index += 1
        while let byte = current {
            index += 1
            if byte == 34 {
                return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
            }
            if byte == 92 {
                guard current != nil else { throw SchedulerCandidateError.invalid("JSON escape") }
                index += 1
            }
        }
        throw SchedulerCandidateError.invalid("unterminated string")
    }
    private mutating func value(depth: Int) throws {
        guard depth <= 128 else { throw SchedulerCandidateError.invalid("JSON depth") }
        whitespace()
        guard let byte = current else { throw SchedulerCandidateError.invalid("missing JSON value") }
        switch byte {
        case 123:
            index += 1; whitespace()
            if current == 125 { index += 1; return }
            var keys: Set<String> = []
            while true {
                let key = try string()
                guard keys.insert(key).inserted else { throw SchedulerCandidateError.invalid("duplicate JSON key") }
                try take(58); try value(depth: depth + 1); whitespace()
                if current == 125 { index += 1; return }
                try take(44)
            }
        case 91:
            index += 1; whitespace()
            if current == 93 { index += 1; return }
            while true {
                try value(depth: depth + 1); whitespace()
                if current == 93 { index += 1; return }
                try take(44)
            }
        case 34: _ = try string()
        default:
            let start = index
            while let byte = current, ![9, 10, 13, 32, 44, 93, 125].contains(byte) { index += 1 }
            guard index > start else { throw SchedulerCandidateError.invalid("JSON scalar") }
        }
    }
}
