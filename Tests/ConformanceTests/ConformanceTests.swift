import Foundation
import XCTest
import SurfaceDeviceContracts
import SurfaceDeviceConformance

final class ConformanceTests: XCTestCase {
    func fixture() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("fixtures/controller-regression-v1.json"))
    }

    func testCatalogDecodesAllOriginalScenariosAndStepsFromCallerData() throws {
        let catalog = try ScenarioCatalog.decode(data: fixture())
        XCTAssertEqual(catalog.scenarios.map(\.id), (1...30).map { String(format: "T%02d", $0) })
        XCTAssertEqual(catalog.scenarios.flatMap(\.steps).count, 78)
        XCTAssertEqual(catalog.scenarios[0].steps[0].operation, "receive_input")
        XCTAssertEqual(catalog.scenarios[0].steps[0].arguments,
                       .object(["element_id": .scalar(.text("axis")), "value": .scalar(.number(10)), "context": .scalar(.text("context1"))]))
    }

    func testExplicitNullAssertionSurvivesTypedDecodeAndEncode() throws {
        let catalog = try ScenarioCatalog.decode(data: fixture())
        let nulls = catalog.scenarios.flatMap(\.steps).flatMap(\.expect).filter { $0.value == .null }
        XCTAssertEqual(nulls.count, 2)
        let decoded = try JSONDecoder().decode(ScenarioAssertion.self, from: JSONEncoder().encode(nulls[0]))
        XCTAssertEqual(decoded.value, .null)
        XCTAssertTrue(try AssertionEvaluator.evaluate(decoded, instanceID: "primary", before: [:], after: ["primary": [decoded.metric: .null]]))
    }

    func testAllSixRelationsAreExactAndNumbersDoNotEqualBooleans() throws {
        let before: TraceObservations = ["primary": ["count": .number(2)]]
        let after: TraceObservations = ["primary": ["count": .number(3)]]
        for assertion in [ScenarioAssertion(metric: "count", relation: .equals, value: .number(3)),
                          ScenarioAssertion(metric: "count", relation: .notEquals, value: .number(2)),
                          ScenarioAssertion(metric: "count", relation: .increased),
                          ScenarioAssertion(metric: "count", relation: .increasedBy, value: .number(1)),
                          ScenarioAssertion(metric: "count", relation: .atLeast, value: .number(3))] {
            XCTAssertTrue(try AssertionEvaluator.evaluate(assertion, instanceID: "primary", before: before, after: after))
        }
        XCTAssertTrue(try AssertionEvaluator.evaluate(ScenarioAssertion(metric: "count", relation: .unchanged), instanceID: "primary", before: after, after: after))
        XCTAssertFalse(try AssertionEvaluator.evaluate(ScenarioAssertion(metric: "count", relation: .equals, value: .flag(true)), instanceID: "primary", before: [:], after: ["primary": ["count": .number(1)]]))
        XCTAssertFalse(try AssertionEvaluator.evaluate(ScenarioAssertion(metric: "count", relation: .equals, value: .number(3.nextUp)), instanceID: "primary", before: before, after: after))
    }

    func testAssertionMissingObservationAndWrongNumericTypeAreErrors() throws {
        XCTAssertThrowsError(try AssertionEvaluator.evaluate(ScenarioAssertion(metric: "absent", relation: .equals, value: .null), instanceID: "primary", before: [:], after: [:]))
        XCTAssertThrowsError(try AssertionEvaluator.evaluate(ScenarioAssertion(metric: "x", relation: .equals), instanceID: "primary", before: [:], after: ["primary": ["x": .number(1)]]))
        XCTAssertThrowsError(try AssertionEvaluator.evaluate(ScenarioAssertion(metric: "x", relation: .increased), instanceID: "primary", before: ["primary": ["x": .number(1)]], after: ["primary": ["x": .flag(true)]]))
        XCTAssertThrowsError(try AssertionEvaluator.evaluate(ScenarioAssertion(metric: "x", relation: .unchanged), instanceID: "primary", before: [:], after: ["primary": ["x": .null]]))
    }

    func testAssertionUsesExplicitOtherInstanceWithoutFallback() throws {
        let assertion = ScenarioAssertion(metric: "count", relation: .equals, value: .number(8), instanceID: "secondary")
        XCTAssertTrue(try AssertionEvaluator.evaluate(assertion, instanceID: "primary", before: [:], after: ["primary": ["count": .number(9)], "secondary": ["count": .number(8)]]))
        XCTAssertThrowsError(try AssertionEvaluator.evaluate(assertion, instanceID: "primary", before: [:], after: ["primary": ["count": .number(8)]]))
    }

    func testNonFiniteObservationAndOverflowCannotPassAssertions() throws {
        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try AssertionEvaluator.evaluate(ScenarioAssertion(metric: "x", relation: .equals, value: .number(bad)), instanceID: "primary", before: [:], after: ["primary": ["x": .number(bad)]]))
        }
        XCTAssertThrowsError(try AssertionEvaluator.evaluate(ScenarioAssertion(metric: "x", relation: .increasedBy, value: .number(1)), instanceID: "primary", before: ["primary": ["x": .number(-Double.greatestFiniteMagnitude)]], after: ["primary": ["x": .number(Double.greatestFiniteMagnitude)]]))
    }

    func sample(step: Int = 0, decision: ShadowDecision = .accepted, generation: UInt64 = 1,
                contextGeneration: String = "binding.1", revoked: [String] = ["queued.a", "queued.a"],
                value: Double = 1, transport: [String] = ["opaque.a", "opaque.b"]) throws -> ShadowSample {
        let endpoint = try EndpointProvenance(endpointID: "endpoint.1", deviceID: "device.1", connectionGeneration: generation, transportOrigin: .localVirtual)
        let context = try DeviceContext(id: "context.1", generation: contextGeneration, mappingRevision: "map.1")
        let observation = try DeviceObservation(targetID: "axis", value: .number(2), state: .observed, evidence: .deviceReport,
                                                context: context, endpoint: endpoint, source: .hardware, at: 1)
        let effect = try EffectDescriptor(id: "effect.1", targetID: "lamp", affectedElements: ["lamp"], value: .number(value), classification: .display,
                                          sideEffects: [], context: context, endpoint: endpoint, source: .hardware, timing: .immediate, at: 1)
        let evidence = try TransmissionEvidence(effectID: effect.id, targetID: effect.targetID, context: context, endpoint: endpoint, source: .hardware, at: 1, outcome: .accepted)
        return ShadowSample(stepIndex: step, operationID: "operation.1", decision: decision, context: context, endpoint: endpoint,
                            pendingQueueItems: ["pending.a"], revokedQueueItems: revoked, observations: [observation], feedback: [effect],
                            transmissions: [evidence], transportSequence: transport)
    }

    func testShadowEqualSamplesHaveZeroDifferences() throws {
        XCTAssertEqual(try ShadowComparator.compare(reference: [sample(), sample(step: 1)], candidate: [sample(), sample(step: 1)]), [])
    }

    func testShadowDetectsFeedbackValueChangedByOneRepresentableStep() throws {
        let differences = try ShadowComparator.compare(reference: [sample()], candidate: [sample(value: 1.nextUp)])
        XCTAssertEqual(differences.map(\.field), ["feedback"])
    }

    func testShadowDetectsStepOrderAndMissingSteps() throws {
        XCTAssertFalse(try ShadowComparator.compare(reference: [sample(), sample(step: 1)], candidate: [sample(step: 1), sample()]).isEmpty)
        XCTAssertEqual(try ShadowComparator.compare(reference: [sample()], candidate: []).map(\.field), ["stepCount"])
    }

    func testShadowPreservesDuplicateRevocationMultiplicityAndOrder() throws {
        XCTAssertEqual(try ShadowComparator.compare(reference: [sample()], candidate: [sample(revoked: ["queued.a"])]).map(\.field), ["revokedQueueItems"])
        XCTAssertEqual(try ShadowComparator.compare(reference: [sample(revoked: ["a", "b"])], candidate: [sample(revoked: ["b", "a"])]).map(\.field), ["revokedQueueItems"])
    }

    func testShadowDetectsDecisionReasonAndBothGenerations() throws {
        XCTAssertEqual(try ShadowComparator.compare(reference: [sample(decision: .rejected(reason: "identity"))], candidate: [sample(decision: .rejected(reason: "permission"))]).map(\.field), ["decision"])
        let connection = try ShadowComparator.compare(reference: [sample()], candidate: [sample(generation: 2)])
        XCTAssertEqual(Set(connection.map(\.field)), ["endpoint", "observations", "feedback", "transmissions"])
        let binding = try ShadowComparator.compare(reference: [sample()], candidate: [sample(contextGeneration: "binding.2")])
        XCTAssertEqual(Set(binding.map(\.field)), ["context", "observations", "feedback", "transmissions"])
    }

    func testShadowDoesNotNormalizeTransportOrder() throws {
        XCTAssertEqual(try ShadowComparator.compare(reference: [sample()], candidate: [sample(transport: ["opaque.b", "opaque.a"])]).map(\.field), ["transportSequence"])
    }

    func testOriginalResultStepTraceRetainsScalarsAndEffectOrder() throws {
        let trace = ScenarioStepTrace(index: 0, operation: "publish_display", status: .pass, reason: nil, before: [:],
                                       after: ["primary": ["count": .number(2)]],
                                       effects: [ScenarioEffectTrace(instanceID: "primary", kinds: [.display, .valueProjection], endpoint: "axis.display", value: .number(8), accepted: true),
                                                 ScenarioEffectTrace(instanceID: "primary", kinds: [.display], endpoint: "meter.display", value: .flag(true), accepted: false)])
        let decoded = try JSONDecoder().decode(ScenarioStepTrace.self, from: JSONEncoder().encode(trace))
        XCTAssertEqual(trace, decoded)
        XCTAssertTrue(try decoded.evaluate(ScenarioAssertion(metric: "count", relation: .equals, value: .number(2)), instanceID: "primary"))
        XCTAssertEqual(decoded.effects.map(\.accepted), [true, false])
    }
    func replacing(_ value: ShadowSample, operationID: String? = nil, decision: ShadowDecision? = nil,
                   pending: [String]? = nil, observations: [DeviceObservation]? = nil,
                   feedback: [EffectDescriptor]? = nil, transmissions: [TransmissionEvidence]? = nil) -> ShadowSample {
        ShadowSample(stepIndex: value.stepIndex, operationID: operationID ?? value.operationID,
                     decision: decision ?? value.decision, context: value.context, endpoint: value.endpoint,
                     pendingQueueItems: pending ?? value.pendingQueueItems, revokedQueueItems: value.revokedQueueItems,
                     observations: observations ?? value.observations, feedback: feedback ?? value.feedback,
                     transmissions: transmissions ?? value.transmissions, transportSequence: value.transportSequence)
    }

    func testShadowMutationProbeCoversEveryRemainingFieldWithNonemptyReference() throws {
        let original = try sample()
        XCTAssertFalse(original.observations.isEmpty)
        XCTAssertFalse(original.feedback.isEmpty)
        XCTAssertFalse(original.transmissions.isEmpty)
        let rejected = try TransmissionEvidence(effectID: "effect.1", targetID: "lamp", context: original.context,
                                                 endpoint: original.endpoint, source: .hardware, at: 1, outcome: .rejected(reason: "transport.failure"))
        let cases: [(String, ShadowSample)] = [
            ("operationID", replacing(original, operationID: "operation.other")),
            ("decision", replacing(original, decision: .ignored(reason: "echo"))),
            ("pendingQueueItems", replacing(original, pending: [])),
            ("observations", replacing(original, observations: [])),
            ("feedback", replacing(original, feedback: [])),
            ("transmissions", replacing(original, transmissions: [rejected])),
        ]
        for (field, changed) in cases {
            XCTAssertEqual(ShadowComparator.compare(reference: [original], candidate: [changed]).map(\.field), [field])
        }
    }

    func testShadowDetectsFeedbackOrderWithDifferentNonemptyPayloads() throws {
        let first = try sample(value: 1)
        let second = try sample(value: 2)
        let reference = replacing(first, feedback: first.feedback + second.feedback)
        let changed = replacing(first, feedback: second.feedback + first.feedback)
        XCTAssertEqual(ShadowComparator.compare(reference: [reference], candidate: [changed]).map(\.field), ["feedback"])
    }

    func testStepTraceEncodesFrozenRequiredNullableReasonForEveryStatus() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("docs/controller-regression-results.schema.json"))) as? [String: Any])
        var stepSchema: Any = schema
        for key in ["properties", "results", "items", "properties", "steps", "items"] {
            stepSchema = try XCTUnwrap((stepSchema as? [String: Any])?[key])
        }
        let required = Set(try XCTUnwrap((stepSchema as? [String: Any])?["required"] as? [String]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let cases: [(ScenarioStatus, String?)] = [(.pass, nil), (.fail, "denied"), (.notApplicable, "missing_physical_feature")]
        for (status, reason) in cases {
            let trace = ScenarioStepTrace(index: 0, operation: "inspect", status: status, reason: reason, before: [:], after: [:], effects: [])
            let data = try encoder.encode(trace)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            if status == .pass {
                print("REQUIRED_NULLABLE_REASON_PROBE " + String(decoding: data, as: UTF8.self))
                if let output = ProcessInfo.processInfo.environment["CSK_CODEC_PROBE_OUTPUT"] {
                    try data.write(to: URL(fileURLWithPath: output))
                }
            }
            XCTAssertEqual(Set(object.keys), required, "Frozen result-step schema requires every key, including reason")
            if let reason { XCTAssertEqual(object["reason"] as? String, reason) }
            else { XCTAssertTrue(object["reason"] is NSNull, "A required nil reason must encode as explicit JSON null") }
            XCTAssertEqual(try JSONDecoder().decode(ScenarioStepTrace.self, from: data), trace)
        }
    }

    func testEffectTracePreservesRequiredNullableValueAsExplicitNull() throws {
        let effect = ScenarioEffectTrace(instanceID: "primary", kinds: [.display], endpoint: "axis.display", value: .null, accepted: true)
        let encoded = try JSONEncoder().encode(effect)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertTrue(object.keys.contains("value"))
        XCTAssertTrue(object["value"] is NSNull)
        XCTAssertEqual(try JSONDecoder().decode(ScenarioEffectTrace.self, from: encoded), effect)
    }

    func testOpaqueSetupPayloadPreservesRequiredNullableEndpointFields() throws {
        let catalog = try ScenarioCatalog.decode(data: fixture())
        let encoded = try JSONEncoder().encode(catalog.scenarios[0].setup)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let controls = try XCTUnwrap(object["controls"] as? [[String: Any]])
        for control in controls {
            for key in ["input_endpoint", "feedback_endpoint", "touch_endpoint"] {
                XCTAssertTrue(control.keys.contains(key), "Required nullable setup field must remain present")
            }
        }
        let meter = try XCTUnwrap(controls.first(where: { $0["id"] as? String == "meter" }))
        XCTAssertTrue(meter["input_endpoint"] is NSNull)
        XCTAssertTrue(meter["touch_endpoint"] is NSNull)
        XCTAssertEqual(try JSONDecoder().decode(ScenarioPayload.self, from: encoded), catalog.scenarios[0].setup)
    }

}
