import Foundation
import PlatformRuntime
import SurfaceDeviceConformance

private struct Row: Encodable {
    let id: String
    let completeOriginalScenario: Bool
    let originalStepCount: Int
    let unexecutedStepIndices: [Int]
    let status: ScenarioStatus
    let steps: [ScenarioStepTrace]
    let assertionsChecked: Int
    let failures: [String]
    let actionJournal: [[String: String]]
    let transportFacts: ScenarioPayload?
}
private struct Artifact: Encodable {
    let artifact = "minimal-platform-checkpoints-not-final-j5"
    let fullInventoryAcceptance = false
    let fault: String
    let rows: [Row]
    let auxiliaryUndo: ScenarioPayload
}

@main
private struct PlatformCheckpointRunner {
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
        guard ["none", "retry_lost_action", "drop_authority_error", "wrong_render", "truncate_journal"].contains(fault) else { throw CompositionError.shape("fault") }
        let evidence = URL(fileURLWithPath: args[6])
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let authority = try AuthorityPort(executable: args[3])
        var rows: [Row] = []
        for id in ["T24", "T25", "T27"] {
            guard let scenario = catalog.scenarios.first(where: { $0.id == id }) else { throw CompositionError.shape("scenario") }
            // This stage declares one partial checkpoint explicitly; it does not
            // classify an unexecuted motor-continuity operation as passed or NA.
            let indices = id == "T25" ? scenario.steps.indices.filter { scenario.steps[$0].operation == "overflow_journal" } : Array(scenario.steps.indices)
            let needsAuthority = indices.contains { ["authority_reply", "write_parameter"].contains(scenario.steps[$0].operation) }
            guard let firstIndex = indices.first else { throw CompositionError.shape("empty_checkpoint") }
            let runtime = try PlatformRuntime(setup: scenario.setup, requestedInstance: scenario.steps[firstIndex].instanceID, authority: authority,
                authorityInstance: id + ".authority", needsAuthority: needsAuthority,
                helper: args[4], sdkRoot: args[5], fault: fault)
            var steps: [ScenarioStepTrace] = [], failures: [String] = []
            var checked = 0
            for index in indices {
                let step = scenario.steps[index], before = try runtime.metrics()
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
            rows.append(Row(id: id, completeOriginalScenario: indices.count == scenario.steps.count,
                originalStepCount: scenario.steps.count, unexecutedStepIndices: scenario.steps.indices.filter { !indices.contains($0) },
                status: failures.isEmpty ? .pass : .fail, steps: steps, assertionsChecked: checked, failures: failures,
                actionJournal: try runtime.actionJournalFacts(),
                transportFacts: runtime.remoteTransportFacts.isEmpty ? nil : try JSONDecoder().decode(ScenarioPayload.self,
                    from: JSONSerialization.data(withJSONObject: runtime.remoteTransportFacts, options: [.sortedKeys]))))
        }
        let auxiliary = try PlatformRuntime.undoRevocationAux(authority: authority)
        let denied = auxiliary["denied"] as? [String: Any], allowed = auxiliary["allowed"] as? [String: Any]
        let error = denied?["error"] as? [String: Any]
        let auxPassed = denied?["ok"] as? Bool == false && error?["code"] as? String == "denied"
            && (auxiliary["denied_values"] as? [String: Double])?["p1"] == 100
            && allowed?["ok"] as? Bool == true && (auxiliary["allowed_values"] as? [String: Double])?["p1"] == 0
        try authority.finish(at: 3, evidence: evidence)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Artifact(fault: fault, rows: rows,
            auxiliaryUndo: try JSONDecoder().decode(ScenarioPayload.self,
                from: JSONSerialization.data(withJSONObject: auxiliary, options: [.sortedKeys])))).write(to: URL(fileURLWithPath: args[1]))
        let complete = rows.filter(\.completeOriginalScenario)
        print("PLATFORM_CHECKPOINT complete_scenarios=\(complete.count) complete_pass=\(complete.filter { $0.status == .pass }.count) partial_steps=\(rows.filter { !$0.completeOriginalScenario }.reduce(0) { $0 + $1.steps.count }) operations=\(rows.reduce(0) { $0 + $1.steps.count }) assertions=\(rows.reduce(0) { $0 + $1.assertionsChecked }) nonmotor_undo_aux=\(auxPassed ? "pass" : "fail") full_inventory=false fault=\(fault)")
        if !auxPassed || rows.contains(where: { $0.status != .pass }) { exit(1) }
    }
}
