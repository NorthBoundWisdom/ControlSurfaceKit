import Foundation
import CompleteDeviceRuntime
import PlatformRuntime
import SurfaceDeviceConformance

private struct ResultRow: Encodable {
    let id: String
    let status: ScenarioStatus
    let reason: TraceValue
    let steps: [ScenarioStepTrace]
}
private struct Report: Encodable {
    let schema_version = 1
    let artifact = "neutral-controller-regression-results"
    let fixture_sha256 = "546fbc2a6f1d20f9e116a91558f4dd67891bfaba797b9778e85d975fe4cd3384"
    let host_revision: String
    let host_id = "minimal-offline"
    let qualification = "test-only-fake-device"
    let features = ["absolute_input", "relative_input", "hardware_context"]
    let results: [ResultRow]
}

@main
private struct CompleteScenarioRunner {
    static func main() {
        do { try run() }
        catch {
            try? FileHandle.standardError.write(contentsOf: Data((String(describing: error) + "\n").utf8)); exit(1)
        }
    }
    static func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 8 else { throw CompositionError.shape("fixture output-dir fault bridge helper sdk-root revision results-schema") }
        let fixture = URL(fileURLWithPath: args[0]), output = URL(fileURLWithPath: args[1]), fault = args[2]
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let catalog = try ScenarioCatalog.decode(data: Data(contentsOf: fixture))
        let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[7]))) as! [String: Any]
        let defs = schema["$defs"] as! [String: Any], observations = defs["observations"] as! [String: Any]
        let primary = (observations["properties"] as! [String: Any])["primary"] as! [String: Any]
        let allowed = Set((primary["properties"] as! [String: Any]).keys)
        let authority = try AuthorityPort(executable: args[3])
        let features: Set<String> = ["absolute_input", "relative_input", "hardware_context"]
        var rows: [ResultRow] = [], raw: [[String: Any]] = []
        var passedSteps = 0, naSteps = 0, failedSteps = 0, assertionCount = 0
        for scenario in catalog.scenarios {
            let missing = Set(scenario.requiresFeatures).subtracting(features).sorted()
            if !missing.isEmpty {
                let reason = "physical feature absent: " + missing.joined(separator: ",")
                let steps = scenario.steps.enumerated().map { index, step in
                    ScenarioStepTrace(index: index, operation: step.operation, status: .notApplicable, reason: reason, before: [:], after: [:], effects: [])
                }
                rows.append(ResultRow(id: scenario.id, status: .notApplicable, reason: .text(reason), steps: [])); naSteps += steps.count
                continue
            }
            let setup = try fields(scenario.setup)
            guard case .array(let instances) = setup["instances"] else { throw CompositionError.shape("instances") }
            var devices: [String: CompleteDeviceRuntime] = [:]
            for instance in instances {
                let id = try string(fields(instance)["id"])
                devices[id] = try CompleteDeviceRuntime(setup: scenario.setup, instance: id,
                    mode: scenario.requiresFeatures.contains("relative_input") ? .relative : .absolute,
                    authority: authority, authorityInstance: scenario.id + "." + id,
                    helper: args[4], sdkRoot: args[5], fault: fault)
            }
            func metrics() throws -> TraceObservations {
                var result: TraceObservations = [:]
                for (id, device) in devices { result[id] = try device.metrics().filter { allowed.contains($0.key) } }
                return result
            }
            var stepRows: [ScenarioStepTrace] = [], rowFailures: [String] = []
            for (index, step) in scenario.steps.enumerated() {
                let stepMissing = Set(step.requiresFeatures).subtracting(features).sorted()
                let before = try metrics()
                if !stepMissing.isEmpty {
                    let reason = "physical feature absent: " + stepMissing.joined(separator: ",")
                    stepRows.append(ScenarioStepTrace(index: index, operation: step.operation, status: .notApplicable, reason: reason,
                        before: [:], after: [:], effects: [])); naSteps += 1
                    continue
                }
                guard let device = devices[step.instanceID] else { throw CompositionError.shape("step_instance") }
                let counts = devices.mapValues(\.attemptCount)
                var operationError: String?
                do { try device.execute(operation: step.operation, arguments: step.arguments, at: Double(index + 1) / 10) }
                catch { operationError = String(describing: error) }
                let after = try metrics()
                var failures: [String] = []
                // Expect is only consulted after all operation/provider work.
                for assertion in step.expect {
                    assertionCount += 1
                    do {
                        if try !AssertionEvaluator.evaluate(assertion, instanceID: step.instanceID, before: before, after: after) {
                            failures.append(assertion.metric)
                        }
                    } catch { failures.append(assertion.metric + ":" + String(describing: error)) }
                }
                if let operationError { failures.append(operationError) }
                let passed = failures.isEmpty
                let effects = devices.keys.sorted().flatMap { devices[$0]!.effectTraces(since: counts[$0]!) }
                stepRows.append(ScenarioStepTrace(index: index, operation: step.operation, status: passed ? .pass : .fail,
                    reason: passed ? nil : failures.joined(separator: ";"), before: before, after: after, effects: effects))
                if passed { passedSteps += 1 } else { failedSteps += 1; rowFailures += failures.map { step.operation + ":" + $0 } }
                raw.append(["scenario": scenario.id, "step": index, "operation": step.operation,
                    "failures": failures, "devices": try devices.keys.sorted().map { try devices[$0]!.detail() }])
            }
            rows.append(ResultRow(id: scenario.id, status: rowFailures.isEmpty ? .pass : .fail,
                reason: rowFailures.isEmpty ? .null : .text(rowFailures.joined(separator: ";").prefix(512).description), steps: stepRows))
            for device in devices.values { _ = try authority.call("destroy", instance: device.authorityID, at: Double(scenario.steps.count + 1) / 10) }
        }
        // Supplemental provenance exercise is separate from the 35 fixture steps.
        // Attachment alone never creates an input or output; subsequent packets
        // and display requests below are explicitly independent auxiliary work.
        let endpointDevice = try CompleteDeviceRuntime(setup: catalog.scenarios[0].setup, instance: "primary", mode: .absolute,
            authority: authority, authorityInstance: "endpoint.aux", helper: args[4], sdkRoot: args[5], fault: fault)
        let attach: ScenarioPayload = .object(["endpoint_id": .scalar(.text("aux.remote.route")), "provenance": .scalar(.text("remote_virtual")), "name": .scalar(.text("USB cosmetic name"))])
        try endpointDevice.execute(operation: "attach_endpoint", arguments: attach, at: 0.1)
        let attachOnly = try endpointDevice.detail()
        var endpointErrors: [String] = []
        do { try endpointDevice.execute(operation: "receive_input", arguments: .object(["element_id": .scalar(.text("axis")), "value": .scalar(.number(9)), "context": .scalar(.text("context1"))]), at: 0.2) }
        catch { endpointErrors.append(String(describing: error)) }
        do { try endpointDevice.execute(operation: "publish_display", arguments: .object(["element_id": .scalar(.text("axis")), "value": .scalar(.number(11))]), at: 0.3) }
        catch { endpointErrors.append(String(describing: error)) }
        let auxMetrics = try endpointDevice.metrics()
        let endpointPassed = endpointErrors.isEmpty && auxMetrics["provenance_preserved"] == .flag(true) && auxMetrics["qualification_upgraded"] == .flag(false)
        let endpointAux: [String: Any] = ["separate_from_fixture": true, "passed": endpointPassed, "errors": endpointErrors,
            "attach_only": attachOnly, "after_explicit_input_and_display": try endpointDevice.detail()]
        _ = try authority.call("destroy", instance: endpointDevice.authorityID, at: 0.4)
        let aux = try PlatformRuntime.undoRevocationAux(authority: authority)
        try authority.finish(at: 3, evidence: output)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Report(host_revision: args[6], results: rows)).write(to: output.appendingPathComponent("report.json"))
        try JSONSerialization.data(withJSONObject: ["raw_steps": raw, "nonmotor_undo_aux": aux, "endpoint_auxiliary": endpointAux, "full_scope": "development-under-test"], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("raw.json"))
        let pass = rows.filter { $0.status == .pass }.count, failed = rows.filter { $0.status == .fail }.count, na = rows.filter { $0.status == .notApplicable }.count
        let summary: [String: Any] = ["scenarios_pass": pass, "scenarios_fail": failed, "scenarios_physical_na": na,
            "applicable_steps_pass": passedSteps, "applicable_steps_fail": failedSteps, "physical_na_steps": naSteps,
            "original_assertions_checked": assertionCount, "fixture_data_unchanged": true, "fault": fault,
            "qualification": "test-only-fake-device", "endpoint_auxiliary_pass": endpointPassed, "nonmotor_aux": aux]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("summary.json"))
        print("MINIMAL_FULL scenarios_pass=\(pass) fail=\(failed) physical_NA=\(na) applicable_steps_pass=\(passedSteps) fail=\(failedSteps) step_NA=\(naSteps) assertions=\(assertionCount)")
        if failed > 0 || !endpointPassed { exit(1) }
    }
}
