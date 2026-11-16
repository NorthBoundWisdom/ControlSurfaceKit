import Foundation
import XCTest
import SurfaceDeviceContracts

final class DeviceContractTests: XCTestCase {
    func endpoint(_ origin: EndpointTransportOrigin = .localVirtual, generation: UInt64 = 7) throws -> EndpointProvenance {
        try EndpointProvenance(endpointID: "endpoint.input", deviceID: nil,
                               connectionGeneration: generation, transportOrigin: origin)
    }

    func context() throws -> DeviceContext {
        try DeviceContext(id: "context.active", generation: "generation.current", mappingRevision: "mapping.current")
    }

    func testUnknownEndpointIsExplicitAndNeverFilledFromOtherFacts() throws {
        let value = try EndpointProvenance(endpointID: nil, deviceID: nil, connectionGeneration: 0, transportOrigin: .unknown)
        XCTAssertNil(value.endpointID)
        XCTAssertNil(value.deviceID)
        XCTAssertEqual(value.transportOrigin, .unknown)
        for origin in [EndpointTransportOrigin.physicalUSB, .localVirtual, .remoteVirtual] {
            let partial = try EndpointProvenance(endpointID: nil, deviceID: nil, connectionGeneration: 1, transportOrigin: origin)
            XCTAssertNil(partial.endpointID)
            XCTAssertNil(partial.deviceID)
            XCTAssertEqual(partial.transportOrigin, origin)
        }
        XCTAssertThrowsError(try EndpointProvenance(endpointID: "", deviceID: nil, connectionGeneration: 1, transportOrigin: .unknown))
    }

    func testDeviceValueDecoderAndEncoderRejectNonFinitePayloads() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        for raw in [#"{"number":"NaN"}"#, #"{"number":"Infinity"}"#, #"{"number":"-Infinity"}"#] {
            XCTAssertThrowsError(try decoder.decode(DeviceValue.self, from: Data(raw.utf8)))
        }
        XCTAssertThrowsError(try JSONEncoder().encode(DeviceValue.number(.nan)))
        for value in [DeviceValue.number(2), .flag(true), .text("opaque"), .none] {
            XCTAssertEqual(try decoder.decode(DeviceValue.self, from: JSONEncoder().encode(value)), value)
        }
    }

    func testConnectionGenerationAndOriginAreIndependentOfDeviceQualification() throws {
        let knownEndpoint = try endpoint(.physicalUSB, generation: 19)
        XCTAssertNil(knownEndpoint.deviceID)
        XCTAssertEqual(knownEndpoint.connectionGeneration, 19)
        XCTAssertNotEqual(knownEndpoint, try endpoint(.physicalUSB, generation: 20))
        XCTAssertNotEqual(knownEndpoint, try endpoint(.remoteVirtual, generation: 19))
    }

    func testInputCarriesAllCallerFactsAndDoesNotInterpretContext() throws {
        let value = try DeviceInputEvent(elementID: "element.axis", kind: .relative, value: .number(-3),
                                        context: context(), endpoint: endpoint(), source: .simulation, at: 2.25)
        XCTAssertEqual(value.value, .number(-3))
        XCTAssertEqual(value.context.generation, "generation.current")
        XCTAssertEqual(value.endpoint.connectionGeneration, 7)
        XCTAssertEqual(value.source, .simulation)
        XCTAssertEqual(value.at, 2.25)
    }

    func testInputRejectsNonFiniteTimeAndPayloadWithoutSubstitution() throws {
        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try DeviceInputEvent(elementID: "axis", kind: .absolute, value: .number(1),
                                                     context: context(), endpoint: endpoint(), source: .hardware, at: bad))
            XCTAssertThrowsError(try DeviceInputEvent(elementID: "axis", kind: .absolute, value: .number(bad),
                                                     context: context(), endpoint: endpoint(), source: .hardware, at: 1))
        }
    }

    func testUnknownAndExpiredObservationCannotSilentlyBecomeObserved() throws {
        let unknown = try DeviceObservation(targetID: "axis", value: nil, state: .unknown, evidence: nil,
                                            context: context(), endpoint: endpoint(), source: .hardware, at: 1)
        XCTAssertNil(unknown.value)
        XCTAssertThrowsError(try DeviceObservation(targetID: "axis", value: .number(0), state: .unknown, evidence: nil,
                                                   context: context(), endpoint: endpoint(), source: .hardware, at: 1))
        XCTAssertThrowsError(try DeviceObservation(targetID: "axis", value: .number(0), state: .observed, evidence: nil,
                                                   context: context(), endpoint: endpoint(), source: .hardware, at: 1))
        let expired = try DeviceObservation(targetID: "axis", value: .number(0.3), state: .expired, evidence: .deviceReport,
                                            context: context(), endpoint: endpoint(), source: .hardware, at: 1)
        XCTAssertEqual(expired.state, .expired)
        XCTAssertEqual(expired.value, .number(0.3))
    }

    func testTransportAcceptanceHasSeparateEvidenceAndNoObservationMutation() throws {
        let observation = try DeviceObservation(targetID: "axis", value: nil, state: .unknown, evidence: nil,
                                                context: context(), endpoint: endpoint(), source: .hardware, at: 1)
        let sent = try TransmissionEvidence(effectID: "effect.1", targetID: "axis", context: context(), endpoint: endpoint(),
                                            source: .hardware, at: 2, outcome: .accepted)
        XCTAssertEqual(sent.outcome, .accepted)
        XCTAssertEqual(sent.effectID, "effect.1")
        XCTAssertEqual(observation.state, .unknown)
        XCTAssertNil(observation.value)
        XCTAssertThrowsError(try TransmissionEvidence(effectID: "effect.1", targetID: "axis", context: context(), endpoint: endpoint(),
                                                       source: .hardware, at: 2, outcome: .rejected(reason: "")))
    }

    func testEffectPermissionIsSideEffectUnionAndPayloadIsPreserved() throws {
        let value = try EffectDescriptor(id: "effect.1", targetID: "display", affectedElements: ["axis", "display"],
                                         value: .number(0.2), classification: .display, sideEffects: [.mechanism, .management],
                                         context: context(), endpoint: endpoint(), source: .hardware, timing: .deferred(until: 3), at: 2)
        XCTAssertEqual(value.requiredDirections, [.display, .mechanism, .management])
        XCTAssertEqual(value.value, .number(0.2))
        XCTAssertEqual(value.timing, .deferred(until: 3))
        XCTAssertThrowsError(try EffectDescriptor(id: "bad", targetID: "display", affectedElements: [], value: .number(.nan),
                                                  classification: .display, sideEffects: [], context: context(), endpoint: endpoint(),
                                                  source: .simulation, timing: .immediate, at: 1))
        XCTAssertThrowsError(try EffectDescriptor(id: "bad", targetID: "display", affectedElements: [], value: .flag(true),
                                                  classification: .display, sideEffects: [], context: context(), endpoint: endpoint(),
                                                  source: .simulation, timing: .deferred(until: .infinity), at: 1))
    }

    func testStructuredCapabilityRejectsDuplicateElementAndModeIdentities() throws {
        let effect = try EffectCapability(kind: "brightness", classification: .display, sideEffects: [])
        let element = try ElementCapability(elementID: "lamp", inputs: [],
                                             displays: [DisplayCapability(kind: "brightness", valueKind: .number)], effects: [effect])
        let mode = try ProtocolModeCapability(id: "mode.native", elements: [element])
        let profile = try DeviceCapabilities(profileID: "profile.test", modes: [mode])
        XCTAssertEqual(profile.modes[0].elements[0].effects[0].requiredDirections, [.display])
        XCTAssertThrowsError(try ProtocolModeCapability(id: "mode.native", elements: [element, element]))
        XCTAssertThrowsError(try DeviceCapabilities(profileID: "profile.test", modes: [mode, mode]))
    }
}
