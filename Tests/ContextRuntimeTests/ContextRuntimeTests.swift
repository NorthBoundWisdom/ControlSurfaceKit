import XCTest
import SurfaceDeviceContracts
import SurfaceBindingContext
import SurfaceConnectionState

final class ContextRuntimeTests: XCTestCase {
    private struct Extra: Equatable, Sendable {
        var inputName: String? = nil
        var outputName: String? = nil
        var inputOrigin: EndpointTransportOrigin? = nil
        var outputOrigin: EndpointTransportOrigin? = nil
    }

    private func snapshot(input: String? = "input", output: String? = "output", generation: UInt64? = 4,
                          connected: Bool = true, extra: Extra = Extra()) throws -> ConnectionSnapshot<Extra> {
        try ConnectionSnapshot(inputID: input, outputID: output, transportGeneration: generation,
                               isConnected: connected, extra: extra)
    }

    private func context(id: String = "stable", generation: String = "epoch", mapping: String? = "map") throws -> DeviceContext {
        try DeviceContext(id: id, generation: generation, mappingRevision: mapping)
    }

    func testEveryMandatoryRouteDimensionInvalidatesIndependently() throws {
        let initial = try snapshot()
        let changed = [try snapshot(input: "new-input"), try snapshot(output: "new-output"),
                       try snapshot(generation: 5), try snapshot(input: nil),
                       try snapshot(output: nil), try snapshot(generation: nil)]
        for next in changed {
            var state = ConnectionState(snapshot: initial, connectionGeneration: 4)
            let result = state.apply(next)
            XCTAssertTrue(result.routeChanged)
            XCTAssertFalse(result.statusChanged)
            XCTAssertTrue(result.invalidatesScope)
            XCTAssertTrue(result.clearPending)
            XCTAssertTrue(result.becameAvailable)
            XCTAssertEqual(state.snapshot, next)
        }
    }

    func testStatusChangeAndRepeatedDisconnectedCallbackHaveDistinctInvalidation() throws {
        var state = ConnectionState(snapshot: try snapshot(generation: nil), connectionGeneration: 11)
        let disconnected = try snapshot(generation: nil, connected: false)
        let first = state.apply(disconnected)
        XCTAssertFalse(first.routeChanged)
        XCTAssertTrue(first.statusChanged)
        XCTAssertTrue(first.invalidatesScope)
        XCTAssertTrue(first.clearPending)
        XCTAssertFalse(first.becameAvailable)
        XCTAssertEqual(state.connectionGeneration, 12)
        let repeated = state.apply(disconnected)
        XCTAssertFalse(repeated.invalidatesScope)
        XCTAssertTrue(repeated.clearPending)
        XCTAssertEqual(state.connectionGeneration, 12)
        XCTAssertTrue(state.apply(try snapshot(generation: nil)).becameAvailable)
        XCTAssertEqual(state.connectionGeneration, 13)
    }

    func testUnchangedConnectedSnapshotPreservesGenerationAndDoesNothing() throws {
        let initial = try snapshot()
        var state = ConnectionState(snapshot: initial, connectionGeneration: 22)
        let result = state.apply(initial)
        XCTAssertFalse(result.routeChanged)
        XCTAssertFalse(result.statusChanged)
        XCTAssertFalse(result.invalidatesScope)
        XCTAssertFalse(result.clearPending)
        XCTAssertFalse(result.becameAvailable)
        XCTAssertEqual(result.previousGeneration, 22)
        XCTAssertEqual(result.currentGeneration, 22)
    }

    func testCallerTransportGenerationWinsWithoutInventingAnEpoch() throws {
        var state = ConnectionState(snapshot: try snapshot(), connectionGeneration: 99)
        let result = state.apply(try snapshot(generation: 6))
        XCTAssertEqual(result.currentGeneration, 6)
        XCTAssertEqual(state.connectionGeneration, 6)
        XCTAssertEqual(state.snapshot.transportGeneration, 6)
    }

    func testFallbackGenerationWrapMatchesExistingUnsignedSemantics() throws {
        var state = ConnectionState(snapshot: try snapshot(generation: nil), connectionGeneration: .max)
        XCTAssertEqual(state.apply(try snapshot(input: "new", generation: nil)).currentGeneration, 0)
    }

    func testExtraNativeIdentityRetainsNilVersusExplicitUnknown() throws {
        let initial = try snapshot()
        let variants = [Extra(inputName: "renamed"), Extra(outputName: "renamed"),
                        Extra(inputOrigin: .unknown), Extra(outputOrigin: .unknown)]
        for extra in variants {
            var state = ConnectionState(snapshot: initial, connectionGeneration: 4)
            XCTAssertTrue(state.apply(try snapshot(extra: extra)).routeChanged)
        }
        let common = try ConnectionSnapshot(inputID: "input", outputID: "output", transportGeneration: 4,
                                            isConnected: true, extra: EmptyConnectionIdentity())
        var minimal = ConnectionState(snapshot: common, connectionGeneration: 4)
        XCTAssertFalse(minimal.apply(common).invalidatesScope)
    }

    func testUnknownEndpointIdentityRemainsUnknownAndEmptyIdentityIsRejected() throws {
        let unknown = try snapshot(input: nil, output: nil, generation: nil, connected: false)
        var state = ConnectionState(snapshot: unknown, connectionGeneration: 0)
        _ = state.apply(unknown)
        XCTAssertNil(state.snapshot.inputID)
        XCTAssertNil(state.snapshot.outputID)
        XCTAssertNil(state.snapshot.transportGeneration)
        XCTAssertThrowsError(try snapshot(input: ""))
        XCTAssertThrowsError(try snapshot(output: ""))
    }

    func testBindingLookupPreservesFirstMatchAndSeparatesPhysicalFacetAndInputRole() throws {
        let entries = try [
            ContextBinding(elementID: "dial", facetID: "one", inputKind: .absolute, targetReferenceID: "first"),
            ContextBinding(elementID: "dial", facetID: "one", inputKind: .absolute, targetReferenceID: "later"),
            ContextBinding(elementID: "dial", facetID: "two", inputKind: .absolute, targetReferenceID: "other-facet"),
            ContextBinding(elementID: "dial", facetID: "one", inputKind: .press, targetReferenceID: "action")
        ]
        let bindings = BindingContext(context: try context(), entries: entries)
        XCTAssertEqual(bindings.entries, entries)
        XCTAssertEqual(bindings.target(elementID: "dial", facetID: "one", inputKind: .absolute), "first")
        XCTAssertEqual(bindings.target(elementID: "dial", facetID: "two", inputKind: .absolute), "other-facet")
        XCTAssertEqual(bindings.target(elementID: "dial", facetID: "one", inputKind: .press), "action")
        XCTAssertNil(bindings.target(elementID: "dial", facetID: "unknown", inputKind: .absolute))
        XCTAssertNil(bindings.target(elementID: "missing", facetID: "one", inputKind: .absolute))
        XCTAssertNil(bindings.target(elementID: "dial", facetID: "one", inputKind: .release))
    }

    func testBindingReplacementDoesNotConflateEpochMappingAndExplicitInvalidation() throws {
        let initial = BindingContext(context: try context(), entries: [])
        var state = BindingContextState(initial)
        XCTAssertFalse(state.apply(initial).changed)
        let epochOnly = BindingContext(context: try context(generation: "new-epoch"), entries: [])
        XCTAssertTrue(state.apply(epochOnly).contextChanged)
        XCTAssertEqual(state.current.context.mappingRevision, "map")
        let mapOnly = BindingContext(context: try context(generation: "new-epoch", mapping: "new-map"), entries: [])
        XCTAssertTrue(state.apply(mapOnly).contextChanged)
        XCTAssertEqual(state.current.context.generation, "new-epoch")
        let entry = try ContextBinding(elementID: "dial", facetID: "one", inputKind: .absolute, targetReferenceID: "reference")
        let changed = state.apply(BindingContext(context: mapOnly.context, entries: [entry]))
        XCTAssertFalse(changed.contextChanged)
        XCTAssertTrue(changed.bindingsChanged)
        var pending = ContextResourceIndex<String, String>()
        pending.upsert("deferred", scope: "same")
        XCTAssertFalse(state.apply(state.current).changed)
        XCTAssertEqual(pending.removeAll(), ["deferred"])
    }

    func testBindingRejectsEmptyReferencesWithoutDefiningBusinessSemantics() throws {
        for fields in [("", "facet", "target"), ("role", "", "target"), ("role", "facet", "")] {
            XCTAssertThrowsError(try ContextBinding(elementID: fields.0, facetID: fields.1,
                                                    inputKind: .press, targetReferenceID: fields.2))
        }
    }

    func testEveryScopeIdentityFieldParticipatesInExactAdmission() throws {
        let endpoint = try EndpointProvenance(endpointID: "output", deviceID: "device", connectionGeneration: 4, transportOrigin: .localVirtual)
        let original = ContextScope(source: .simulation, context: try context(), endpoint: endpoint)
        let variants = try [
            ContextScope(source: .hardware, context: context(), endpoint: endpoint),
            ContextScope(source: .simulation, context: context(id: "other"), endpoint: endpoint),
            ContextScope(source: .simulation, context: context(generation: "other"), endpoint: endpoint),
            ContextScope(source: .simulation, context: context(mapping: nil), endpoint: endpoint),
            ContextScope(source: .simulation, context: context(), endpoint: nil),
            ContextScope(source: .simulation, context: context(), endpoint: EndpointProvenance(endpointID: nil, deviceID: "device", connectionGeneration: 4, transportOrigin: .localVirtual)),
            ContextScope(source: .simulation, context: context(), endpoint: EndpointProvenance(endpointID: "output", deviceID: nil, connectionGeneration: 4, transportOrigin: .localVirtual)),
            ContextScope(source: .simulation, context: context(), endpoint: EndpointProvenance(endpointID: "output", deviceID: "device", connectionGeneration: 5, transportOrigin: .localVirtual)),
            ContextScope(source: .simulation, context: context(), endpoint: EndpointProvenance(endpointID: "output", deviceID: "device", connectionGeneration: 4, transportOrigin: .unknown))
        ]
        XCTAssertTrue(original.matches(original))
        for variant in variants { XCTAssertFalse(original.matches(variant)) }
    }

    func testResourceReplacementCancellationAndDrainOwnExactOrder() throws {
        var index = ContextResourceIndex<String, String>()
        index.upsert("first", scope: "old")
        index.upsert("second", scope: "current")
        index.upsert("first", scope: "current")
        XCTAssertEqual(index.orderedIDs, ["first", "second"])
        XCTAssertTrue(index.remove("first"))
        XCTAssertFalse(index.remove("first"))
        index.upsert("first", scope: "current")
        XCTAssertEqual(index.orderedIDs, ["second", "first"])
        XCTAssertEqual(try index.removeFirst(1), ["second"])
        XCTAssertEqual(index.orderedIDs, ["first"])
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(try index.removeFirst(99), ["first"])
        XCTAssertTrue(index.isEmpty)
        XCTAssertEqual(try index.removeFirst(0), [])
    }

    func testNegativeRemovalRejectsWithoutMutation() throws {
        var index = ContextResourceIndex<String, String>()
        index.upsert("pending", scope: "scope")
        XCTAssertThrowsError(try index.removeFirst(-1))
        XCTAssertEqual(index.orderedIDs, ["pending"])
        XCTAssertEqual(index.scope(for: "pending"), "scope")
    }

    func testOldQueuedScopeIsImmediatelyInadmissibleButRemovalTimingRemainsExplicit() throws {
        let old = ContextScope(source: .simulation, context: try context(), endpoint: nil)
        let current = ContextScope(source: .simulation, context: try context(mapping: "next"), endpoint: nil)
        var index = ContextResourceIndex<String, ContextScope>()
        index.upsert("queued", scope: old)
        XCTAssertFalse(current.matches(try XCTUnwrap(index.scope(for: "queued"))))
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(try index.removeFirst(1), ["queued"])
        XCTAssertTrue(index.isEmpty)
        XCTAssertEqual(index.invalidate(current: current), [])
    }

    func testStaleResourcesAreRevokedWithoutReplayAndOptionalScopeIsNotInvented() {
        var index = ContextResourceIndex<String, String?>()
        index.upsert("old-one", scope: "old")
        index.upsert("current", scope: "new")
        index.upsert("unknown", scope: nil)
        index.upsert("old-two", scope: "old")
        XCTAssertTrue(index.contains("unknown"))
        XCTAssertEqual(index.invalidate(current: "new"), ["old-one", "unknown", "old-two"])
        XCTAssertEqual(index.orderedIDs, ["current"])
        XCTAssertEqual(index.removeAll(), ["current"])
        XCTAssertTrue(index.isEmpty)
        XCTAssertEqual(index.invalidate(current: "new"), [])
        XCTAssertEqual(index.removeAll(), [])
        index.upsert("unknown-again", scope: nil)
        XCTAssertEqual(index.invalidate(current: nil), [])
        XCTAssertTrue(index.contains("unknown-again"))
    }

    func testValueCopiesDoNotShareMutableResourceOrConnectionState() throws {
        var first = ContextResourceIndex<String, String>()
        first.upsert("id", scope: "old")
        var second = first
        XCTAssertEqual(second.removeAll(), ["id"])
        XCTAssertEqual(first.orderedIDs, ["id"])
        let connected = try snapshot()
        let original = ConnectionState(snapshot: connected, connectionGeneration: 4)
        var candidate = original
        _ = candidate.apply(try snapshot(connected: false))
        XCTAssertTrue(original.snapshot.isConnected)
        XCTAssertFalse(candidate.snapshot.isConnected)
    }
}
