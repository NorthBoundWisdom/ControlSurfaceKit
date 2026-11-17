import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum PortError: Error { case invalid(String), ended }

/// Bounded subprocess framing only. It implements no parameter or action policy.
final class LineProcess {
    let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private var pending = Data()
    private(set) var receivedFrames = 0

    init(executable: String, arguments: [String]) throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        try process.run()
    }

    func send(_ object: [String: Any]) throws {
        var bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard bytes.count <= 65536 else { throw PortError.invalid("request_size") }
        bytes.append(10)
        try input.fileHandleForWriting.write(contentsOf: bytes)
    }

    func receive() throws -> [String: Any] {
        while true {
            if let end = pending.firstIndex(of: 10) {
                guard end <= 65536, receivedFrames < 2048 else { throw PortError.invalid("response_size") }
                let line = Data(pending[..<end]); pending.removeSubrange(...end); receivedFrames += 1
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw PortError.invalid("response") }
                return object
            }
            guard pending.count <= 65536 else { throw PortError.invalid("response_size") }
            let capacity = min(4096, 65537 - pending.count)
            var bytes = [UInt8](repeating: 0, count: capacity)
            let count = bytes.withUnsafeMutableBytes { read(output.fileHandleForReading.fileDescriptor, $0.baseAddress, capacity) }
            if count < 0 {
                if errno == EINTR { continue }
                throw PortError.invalid("read")
            }
            let chunk = Data(bytes.prefix(count))
            guard !chunk.isEmpty else { throw PortError.ended }
            pending.append(chunk)
        }
    }

    func close() throws -> (Int32, String) {
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let stderr = try errors.fileHandleForReading.read(upToCount: 65537) ?? Data()
        guard stderr.count <= 65536 else { throw PortError.invalid("stderr_size") }
        return (process.terminationStatus, String(decoding: stderr, as: UTF8.self))
    }

    deinit { if process.isRunning { process.terminate() } }
}

public final class AuthorityPort {
    private let transport: LineProcess
    private var nextID = 0
    private var instances: Set<String> = []
    private var log: [[String: Any]] = []
    public init(executable: String) throws { transport = try LineProcess(executable: executable, arguments: []) }

    public func call(_ op: String, instance: String, at: Double, arguments: [String: Any] = [:]) throws -> [String: Any] {
        guard at.isFinite, nextID < 2048 else { throw PortError.invalid("request_bound") }
        nextID += 1
        let request: [String: Any] = ["version": 1, "id": nextID, "op": op, "instance": instance, "at": at, "arguments": arguments]
        try transport.send(request)
        let response = try transport.receive()
        guard response["version"] as? Int == 1, response["id"] as? Int == nextID,
              response["instance"] as? String == instance, let ok = response["ok"] as? Bool else { throw PortError.invalid("response_pin") }
        log.append(["request": request, "response": response])
        if ok && op == "create" { instances.insert(instance) }
        if ok && op == "destroy" { instances.remove(instance) }
        return response
    }

    public func values(instance: String, at: Double) throws -> [String: Double] {
        let snapshot = try canonicalSnapshot(instance: instance, at: at)
        guard let values = snapshot["values"] as? [String: Double] else { throw PortError.invalid("canonical_values") }
        return values
    }

    public func canonicalSnapshot(instance: String, at: Double) throws -> [String: Any] {
        let response = try call("snapshot", instance: instance, at: at)
        guard response["ok"] as? Bool == true, let snapshot = response["snapshot"] as? [String: Any] else { throw PortError.invalid("canonical_snapshot") }
        return snapshot
    }

    public func finish(at: Double, evidence: URL) throws {
        for id in instances.sorted() { _ = try call("destroy", instance: id, at: at) }
        let result = try call("finish", instance: "suite", at: at)
        guard result["ok"] as? Bool == true else { throw PortError.invalid("finish") }
        let (code, stderr) = try transport.close()
        try JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted, .sortedKeys]).write(to: evidence.appendingPathComponent("authority-port-ledger.json"))
        try Data(stderr.utf8).write(to: evidence.appendingPathComponent("authority-port.stderr.log"))
        guard code == 0 else { throw PortError.invalid("authority_exit") }
    }
}
