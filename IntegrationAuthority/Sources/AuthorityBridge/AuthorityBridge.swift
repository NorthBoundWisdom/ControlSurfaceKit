import Foundation
import CoreFoundation
import BCRSurfaceDomain
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private enum BridgeFailure: Error { case invalid(String), forbiddenIO }

private func exactKeys(_ object: [String: Any], required: Set<String>, optional: Set<String> = []) throws {
    guard required.isSubset(of: Set(object.keys)), Set(object.keys).isSubset(of: required.union(optional)) else {
        throw BridgeFailure.invalid("fields")
    }
}

private func identifier(_ value: Any?) throws -> String {
    guard let value = value as? String, !value.isEmpty, value.utf8.count <= 128 else { throw BridgeFailure.invalid("identifier") }
    return value
}

private func number(_ value: Any?) throws -> Double {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else {
        throw BridgeFailure.invalid("number")
    }
    return value.doubleValue
}

private func boolean(_ value: Any?) throws -> Bool {
    guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw BridgeFailure.invalid("boolean") }
    return value.boolValue
}

@MainActor
private final class ManualClock { var value = 0.0 }

@MainActor
private final class BridgeDiagnostics {
    var hardwareSendAttempts = 0
    var monitorOutputCalls = 0
    var forbiddenCallbackCalls = 0
    func assertNoIO() throws {
        guard hardwareSendAttempts == 0, monitorOutputCalls == 0, forbiddenCallbackCalls == 0 else { throw BridgeFailure.forbiddenIO }
    }
    var values: [String: Any] {
        ["hardware_send_attempts": hardwareSendAttempts, "monitor_output_calls": monitorOutputCalls,
         "forbidden_callbacks": forbiddenCallbackCalls]
    }
}

@MainActor
private final class NoIODevice: SurfaceDevice {
    let diagnostics: BridgeDiagnostics
    let connection = MIDIConnectionSnapshot()
    var onMessages: (@MainActor ([MIDIVoiceMessage]) -> Void)?
    var onConnection: (@MainActor (MIDIConnectionSnapshot) -> Void)?
    private(set) var attempts = 0
    init(diagnostics: BridgeDiagnostics) { self.diagnostics = diagnostics }
    func send(_ message: MIDIVoiceMessage) throws {
        attempts += 1
        diagnostics.hardwareSendAttempts += 1
        throw BridgeFailure.forbiddenIO
    }
}

@MainActor
private final class AuthorityInstance {
    let clock = ManualClock()
    let noIO: NoIODevice
    let diagnostics: BridgeDiagnostics
    let session: SurfaceSession
    private var monitorOutputCalls = 0
    private var replies: [String: ParameterAuthorityDecision] = [:]

    init(id: String, definitions: [[String: Any]], at: Double, diagnostics: BridgeDiagnostics) throws {
        self.diagnostics = diagnostics
        self.noIO = NoIODevice(diagnostics: diagnostics)
        guard !definitions.isEmpty, definitions.count <= 32 else { throw BridgeFailure.invalid("definitions") }
        let parameters = try definitions.map { fields -> ParameterDefinition in
            try exactKeys(fields, required: ["id", "minimum", "maximum", "initial"], optional: ["step"])
            let definition = ParameterDefinition(
                id: .init(rawValue: try identifier(fields["id"])), name: try identifier(fields["id"]),
                minimum: try number(fields["minimum"]), maximum: try number(fields["maximum"]),
                defaultValue: try number(fields["initial"]), step: try fields["step"].map { try number($0) })
            try definition.validate()
            return definition
        }
        guard Set(parameters.map(\.id)).count == parameters.count else { throw BridgeFailure.invalid("duplicate_parameter") }
        clock.value = at
        let clock = self.clock
        let configuration = SurfaceConfiguration(name: "isolated authority", parameters: parameters, assignments: [])
        session = SurfaceSession(
            hardwareDevice: noIO, configuration: configuration,
            hardwareOutput: .observe, hardwareLifecycleFeedback: false,
            now: { Date(timeIntervalSinceReferenceDate: clock.value) },
            historyTime: .init(now: { clock.value }, sleep: { _ in
                diagnostics.forbiddenCallbackCalls += 1
                throw BridgeFailure.forbiddenIO
            }),
            generationFactory: { id + ".authority.epoch" },
            saveHardwareMap: { _ in diagnostics.forbiddenCallbackCalls += 1; throw BridgeFailure.forbiddenIO },
            saveConfiguration: { _ in diagnostics.forbiddenCallbackCalls += 1; throw BridgeFailure.forbiddenIO })
        _ = session.observeMonitor { [weak self] event, _ in
            if event.direction == .output {
                diagnostics.monitorOutputCalls += 1
                self?.monitorOutputCalls += 1
            }
        }
        session.parameterAuthority = { [weak self] request in
            guard let self else { throw BridgeFailure.invalid("destroyed") }
            return self.replies[request.parameter.rawValue] ?? .accept
        }
        try invariants()
    }

    func invariants() throws {
        try diagnostics.assertNoIO()
        guard session.source == .mock,
              session.engine.configuration.allAssignmentSets.allSatisfy(\.isEmpty),
              noIO.attempts == 0, monitorOutputCalls == 0 else {
            throw BridgeFailure.forbiddenIO
        }
    }

    func snapshot() throws -> [String: Any] {
        try invariants()
        let authorization: Any = session.parameterWriteContext.map { context -> [String: Any] in
            ["source": context.source.rawValue, "generation": context.generation, "mapping_revision": context.mappingRevision,
             "identities": context.identities.map(\.rawValue).sorted(),
             "parameters": context.parameters.map { $0.map(\.rawValue).sorted() } as Any? ?? NSNull(),
             "allows_write": context.allowsWrite, "allows_display": context.allowsDisplay]
        } ?? NSNull()
        return ["values": session.parameterSnapshot().values, "can_undo": session.canUndo,
                "can_redo": session.canRedo, "source": session.source.rawValue,
                "input_epoch": session.inputEvents.generation, "binding_revision": session.mappingContextRevision,
                "hardware_send_attempts": noIO.attempts, "monitor_output_calls": monitorOutputCalls,
                "forbidden_callbacks": diagnostics.forbiddenCallbackCalls,
                "authorization": authorization,
                "assignment_count": session.engine.configuration.allAssignmentSets.reduce(0) { $0 + $1.count }]
    }

    func run(_ op: String, arguments: [String: Any], at: Double) throws {
        try invariants()
        clock.value = at
        switch op {
        case "permissions":
            try exactKeys(arguments, required: ["allows_write", "allows_display", "identities"], optional: ["parameters"])
            guard let rawIdentities = arguments["identities"] as? [String], rawIdentities.count <= 3 else { throw BridgeFailure.invalid("identities") }
            let identities = try rawIdentities.map { raw -> ParameterWriteIdentity in
                guard let identity = ParameterWriteIdentity(rawValue: raw) else { throw BridgeFailure.invalid("identity") }
                return identity
            }
            var parameterNames: [String]?
            if let raw = arguments["parameters"] {
                guard let names = raw as? [String], names.count <= 32 else { throw BridgeFailure.invalid("parameters") }
                parameterNames = try names.map { try identifier($0) }
            }
            session.configureParameterWrites(allowsWrite: try boolean(arguments["allows_write"]),
                allowsDisplay: try boolean(arguments["allows_display"]), identities: Set(identities),
                parameters: parameterNames.map { Set($0.map { .init(rawValue: $0) }) })
        case "authority_reply":
            try exactKeys(arguments, required: ["parameter", "accepted"], optional: ["actual_value", "reason"])
            let parameter = try identifier(arguments["parameter"])
            guard session.engine.configuration.parameter(.init(rawValue: parameter)) != nil else { throw BridgeFailure.invalid("parameter") }
            if try boolean(arguments["accepted"]) {
                guard arguments["actual_value"] == nil, arguments["reason"] == nil else { throw BridgeFailure.invalid("accept_fields") }
                replies[parameter] = .accept
            } else {
                replies[parameter] = .reject(actual: try number(arguments["actual_value"]), reason: try identifier(arguments["reason"]))
            }
        case "write":
            try exactKeys(arguments, required: ["parameter", "canonical_value", "identity"])
            guard let identity = ParameterWriteIdentity(rawValue: try identifier(arguments["identity"])) else { throw BridgeFailure.invalid("identity") }
            let parameter = try identifier(arguments["parameter"])
            guard session.engine.configuration.parameter(.init(rawValue: parameter)) != nil else { throw BridgeFailure.invalid("parameter") }
            let value = try number(arguments["canonical_value"])
            try session.withWriteOrigin(identity == .remote ? .agent : .software) {
                try session.setAuthorizedParameter(.init(rawValue: parameter), to: value, identity: identity)
            }
        case "snapshot": try exactKeys(arguments, required: [])
        case "end_history_group":
            try exactKeys(arguments, required: [])
            session.endParameterHistoryGroup()
        case "undo":
            try exactKeys(arguments, required: [])
            try session.undo()
        case "redo":
            try exactKeys(arguments, required: [])
            try session.redo()
        default: throw BridgeFailure.invalid("operation")
        }
        try invariants()
    }
}

private struct FramedInput {
    private var pending = Data()
    private let input = FileHandle.standardInput
    mutating func next() throws -> Data? {
        while true {
            if let boundary = pending.firstIndex(of: 10) {
                guard boundary <= 65536 else { throw BridgeFailure.invalid("frame_size") }
                let line = Data(pending[..<boundary])
                pending.removeSubrange(...boundary)
                guard !line.isEmpty else { throw BridgeFailure.invalid("empty_frame") }
                return line
            }
            guard pending.count <= 65536 else { throw BridgeFailure.invalid("frame_size") }
            // FileHandle.read(upToCount:) may fill the requested size while the
            // peer waits for a reply. A bounded POSIX pipe read returns available
            // bytes immediately, preserving interactive request/response framing.
            let capacity = min(4096, 65537 - pending.count)
            var bytes = [UInt8](repeating: 0, count: capacity)
            let count = bytes.withUnsafeMutableBytes { read(input.fileDescriptor, $0.baseAddress, capacity) }
            if count < 0 {
                if errno == EINTR { continue }
                throw BridgeFailure.invalid("read")
            }
            let chunk = Data(bytes.prefix(count))
            if chunk.isEmpty {
                guard pending.isEmpty else { throw BridgeFailure.invalid("incomplete_frame") }
                return nil
            }
            pending.append(chunk)
        }
    }
}

@main
@MainActor
private struct AuthorityBridge {
    static func errorValue(_ error: any Error) -> [String: Any] {
        if let failure = error as? ParameterWriteFailure {
            switch failure {
            case .denied: return ["code": "denied"]
            case .staleContext: return ["code": "stale_context"]
            case .invalidAuthority: return ["code": "invalid_authority"]
            case .authorityRejected(let reason): return ["code": "authority_rejected", "reason": String(reason.prefix(128))]
            }
        }
        if case BridgeFailure.invalid(let field) = error { return ["code": "invalid_frame", "field": field] }
        return ["code": "bridge_failure"]
    }

    static func emit(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count <= 65536 else { throw BridgeFailure.invalid("response_size") }
        data.append(10)
        try FileHandle.standardOutput.write(contentsOf: data)
    }

    static func main() {
        var reader = FramedInput()
        var instances: [String: AuthorityInstance] = [:]
        let diagnostics = BridgeDiagnostics()
        var previousID = 0
        var commands = 0
        do {
            while let line = try reader.next() {
                commands += 1
                guard commands <= 2048,
                      let request = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw BridgeFailure.invalid("request") }
                try exactKeys(request, required: ["version", "id", "op", "instance", "at", "arguments"])
                guard try number(request["version"]) == 1,
                      let id = Int(exactly: try number(request["id"])), id > previousID,
                      let arguments = request["arguments"] as? [String: Any] else { throw BridgeFailure.invalid("header") }
                previousID = id
                let op = try identifier(request["op"])
                let instanceID = try identifier(request["instance"])
                let at = try number(request["at"])
                if op == "finish" {
                    try exactKeys(arguments, required: [])
                    guard instances.isEmpty else { throw BridgeFailure.invalid("live_instances") }
                    try diagnostics.assertNoIO()
                    try emit(["version": 1, "id": id, "instance": instanceID, "ok": true,
                              "result": ["commands": commands, "live_instances": instances.count,
                                         "no_io": diagnostics.values]])
                    return
                }
                do {
                    if op == "create" {
                        try exactKeys(arguments, required: ["definitions"])
                        guard instances[instanceID] == nil, instances.count < 8,
                              let definitions = arguments["definitions"] as? [[String: Any]] else { throw BridgeFailure.invalid("instance") }
                        instances[instanceID] = try AuthorityInstance(id: instanceID, definitions: definitions, at: at, diagnostics: diagnostics)
                    } else if op == "destroy" {
                        try exactKeys(arguments, required: [])
                        guard let instance = instances[instanceID] else { throw BridgeFailure.invalid("instance") }
                        try instance.invariants()
                        instances.removeValue(forKey: instanceID)
                    } else {
                        guard let instance = instances[instanceID] else { throw BridgeFailure.invalid("instance") }
                        try instance.run(op, arguments: arguments, at: at)
                    }
                    try emit(["version": 1, "id": id, "instance": instanceID, "ok": true,
                              "snapshot": try instances[instanceID]?.snapshot() ?? NSNull()])
                } catch {
                    if case BridgeFailure.forbiddenIO = error { throw error }
                    try emit(["version": 1, "id": id, "instance": instanceID, "ok": false,
                              "error": errorValue(error), "snapshot": try instances[instanceID]?.snapshot() ?? NSNull()])
                }
            }
            throw BridgeFailure.invalid("unfinished_eof")
        } catch {
            try? emit(["version": 1, "id": previousID, "ok": false, "fatal": true, "error": errorValue(error)])
            exit(1)
        }
    }
}
