import Foundation
import PlatformRuntime
import SurfaceDeviceConformance

private struct Row: Encodable {
    let id: String
    let completeOriginalScenario = true
    let status: ScenarioStatus
    let steps: [ScenarioStepTrace]
    let assertionsChecked: Int
    let failures: [String]
    let providerFacts: ScenarioPayload
    let actionJournal: [[String: String]]
}
private struct Artifact: Encodable {
    let artifact = "authority-parser-clock-checkpoints-not-final-j5"
    let fullInventoryAcceptance = false
    let fault: String
    let rows: [Row]
}

@main
private struct ControlCheckpointRunner {
    static func main() {
        do { try run() }
        catch {
            try? FileHandle.standardError.write(contentsOf: Data((String(describing: error) + "\n").utf8))
            exit(1)
        }
    }
    static func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 7 else { throw CompositionError.shape("usage: fixture output fault bridge helper sdk-root evidence-dir") }
        let catalog = try ScenarioCatalog.decode(data: Data(contentsOf: URL(fileURLWithPath: args[0])))
        let fault = args[2]
        guard ["none", "bypass_remote_permission", "accept_spoof", "use_wall_clock"].contains(fault) else { throw CompositionError.shape("fault") }
        let evidence = URL(fileURLWithPath: args[6])
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let authority = try AuthorityPort(executable: args[3])
        var rows: [Row] = []
        for id in ["T18", "T23", "T26"] {
            guard let scenario = catalog.scenarios.first(where: { $0.id == id }), let first = scenario.steps.first else { throw CompositionError.shape("scenario") }
            let needsAuthority = scenario.steps.contains { ["configure_permissions", "write_parameter"].contains($0.operation) }
            let runtime = try PlatformRuntime(setup: scenario.setup, requestedInstance: first.instanceID, authority: authority,
                authorityInstance: id + ".authority", needsAuthority: needsAuthority, helper: args[4], sdkRoot: args[5], fault: fault)
            var steps: [ScenarioStepTrace] = [], failures: [String] = []
            var checked = 0
            for (index, step) in scenario.steps.enumerated() {
                let before = try runtime.metrics()
                var operationError: String?
                do { try runtime.execute(operation: step.operation, arguments: step.arguments, at: Double(index + 1) / 10) }
                catch { operationError = String(describing: error) }
                let after = try runtime.metrics()
                var passed = operationError == nil
                for assertion in step.expect {
                    checked += 1
                    if try !AssertionEvaluator.evaluate(assertion, instanceID: step.instanceID, before: before, after: after) {
                        passed = false; failures.append(step.operation + ":" + assertion.metric)
                    }
                }
                if let operationError { failures.append(step.operation + ":" + operationError) }
                steps.append(ScenarioStepTrace(index: index, operation: step.operation, status: passed ? .pass : .fail,
                    reason: operationError ?? (passed ? nil : "original_assertion_failed"), before: before, after: after, effects: []))
            }
            rows.append(Row(id: id, status: failures.isEmpty ? .pass : .fail, steps: steps, assertionsChecked: checked, failures: failures,
                providerFacts: try JSONDecoder().decode(ScenarioPayload.self, from: JSONSerialization.data(withJSONObject: runtime.supplementalFacts())),
                actionJournal: try runtime.actionJournalFacts()))
        }
        try authority.finish(at: 3, evidence: evidence)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Artifact(fault: fault, rows: rows)).write(to: URL(fileURLWithPath: args[1]))
        let passed = rows.filter { $0.status == .pass }.count
        print("CONTROL_CHECKPOINT complete_scenarios=3 pass=\(passed) fail=\(3-passed) operations=\(rows.reduce(0) { $0+$1.steps.count }) assertions=\(rows.reduce(0) { $0+$1.assertionsChecked }) full_inventory=false fault=\(fault)")
        if passed != rows.count { exit(1) }
    }
}
