import Foundation
import XCTest
import SurfaceDeviceContracts
import SurfaceDeviceConformance

final class MinimalAdapterTests: XCTestCase {
    func testDeviceKnowledgeProducesNeutralInputsAndDisplayWithoutRuntimePolicy() throws {
        let adapter = MinimalDeviceAdapter()
        let capabilities = try adapter.capabilities()
        XCTAssertEqual(capabilities.modes[0].elements.map(\.elementID), ["knob", "button", "lamp"])
        let context = try DeviceContext(id: "context1", generation: "binding.1", mappingRevision: nil)
        let endpoint = try EndpointProvenance(endpointID: "endpoint.minimal", deviceID: nil, connectionGeneration: 1, transportOrigin: .localVirtual)
        let button = try XCTUnwrap(adapter.decode(.buttonPressed(true), context: context, endpoint: endpoint, source: .simulation, at: 0))
        XCTAssertEqual(button.elementID, "button")
        XCTAssertEqual(button.kind, .press)
        XCTAssertEqual(button.value, .flag(true))
        XCTAssertNil(try adapter.decode(.lampLevel(20), context: context, endpoint: endpoint, source: .simulation, at: 0))
        let unsafe = try EffectDescriptor(id: "unsafe", targetID: "lamp", affectedElements: ["lamp"], value: .number(20), classification: .display,
                                          sideEffects: [.mechanism], context: context, endpoint: endpoint, source: .simulation, timing: .immediate, at: 0)
        XCTAssertNil(adapter.encode(unsafe))
    }

    func testSharedT01InputAndDisplayTranslationSubsetDoesNotClaimScenarioPass() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try ScenarioCatalog.decode(data: Data(contentsOf: root.appendingPathComponent("fixtures/controller-regression-v1.json")))
        let scenario = try XCTUnwrap(catalog.scenarios.first(where: { $0.id == "T01" }))
        let adapter = MinimalDeviceAdapter()
        let context = try DeviceContext(id: "context1", generation: "binding.1", mappingRevision: nil)
        var translatedSteps = 0
        for (index, step) in scenario.steps.enumerated() {
            guard case .object(let arguments) = step.arguments else { return XCTFail("fixture arguments") }
            guard case .scalar(.number(let value)) = arguments["value"] else { continue }
            let endpoint = try EndpointProvenance(endpointID: "endpoint." + step.instanceID, deviceID: nil, connectionGeneration: 1, transportOrigin: .localVirtual)
            switch step.operation {
            case "receive_input":
                let event = try XCTUnwrap(adapter.decode(.knobPosition(value), context: context, endpoint: endpoint, source: .simulation, at: Double(index)))
                XCTAssertEqual(event.elementID, "knob")
                XCTAssertEqual(event.value, .number(value))
                XCTAssertEqual(event.endpoint.endpointID, "endpoint." + step.instanceID)
                translatedSteps += 1
            case "publish_display":
                let effect = try EffectDescriptor(id: "effect." + String(index), targetID: "lamp", affectedElements: ["lamp"], value: .number(value),
                                                  classification: .display, sideEffects: [], context: context, endpoint: endpoint, source: .simulation, timing: .immediate, at: Double(index))
                XCTAssertEqual(adapter.encode(effect), .lampLevel(value))
                translatedSteps += 1
            default: XCTFail("unexpected translation operation")
            }
        }
        XCTAssertEqual(translatedSteps, 3)
        // Parameter values, authorization, journal and page behavior are absent.
        // This is translation evidence only, never a full fixture execution.
        print("MINIMAL_ADAPTER_EVIDENCE translated_contract_steps=\(translatedSteps) complete_shared_scenarios=0")
    }
}
