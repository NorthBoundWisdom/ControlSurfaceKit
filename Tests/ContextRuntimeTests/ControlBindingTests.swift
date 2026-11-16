import XCTest
import SurfaceDeviceContracts
import SurfaceBindingContext

final class ControlBindingTests: XCTestCase {
    private func context() throws -> DeviceContext {
        try DeviceContext(id: "stable", generation: "epoch", mappingRevision: "mapping")
    }

    func testControlLookupDoesNotInventOrRequireAnInputRole() throws {
        let binding = try ControlBinding(elementID: "control", facetID: "facet", targetReferenceID: "configuration")
        let index = BindingContext(context: try context(), controlEntries: [binding])
        XCTAssertEqual(index.targetForControl(elementID: "control", facetID: "facet"), "configuration")
        for kind in [InputKind.absolute, .relative, .press, .release, .contactBegan, .contactEnded] {
            XCTAssertNil(index.target(elementID: "control", facetID: "facet", inputKind: kind))
        }
        XCTAssertNil(index.targetForControl(elementID: "missing", facetID: "facet"))
        XCTAssertNil(index.targetForControl(elementID: "control", facetID: "missing"))
    }

    func testControlFirstMatchRetainsOrderAndChangesWhenEntriesAreReordered() throws {
        let first = try ControlBinding(elementID: "control", facetID: "facet", targetReferenceID: "first")
        let second = try ControlBinding(elementID: "control", facetID: "facet", targetReferenceID: "second")
        let original = BindingContext(context: try context(), controlEntries: [first, second])
        let reordered = BindingContext(context: original.context, controlEntries: [second, first])
        XCTAssertEqual(original.controlEntries, [first, second])
        XCTAssertEqual(original.targetForControl(elementID: "control", facetID: "facet"), "first")
        XCTAssertEqual(reordered.targetForControl(elementID: "control", facetID: "facet"), "second")
    }

    func testControlFacetAndPhysicalIdentityRemainIndependent() throws {
        let entries = try [
            ControlBinding(elementID: "control", facetID: "one", targetReferenceID: "target-one"),
            ControlBinding(elementID: "control", facetID: "two", targetReferenceID: "target-two"),
            ControlBinding(elementID: "other", facetID: "one", targetReferenceID: "target-other")
        ]
        let index = BindingContext(context: try context(), controlEntries: entries)
        XCTAssertEqual(index.targetForControl(elementID: "control", facetID: "one"), "target-one")
        XCTAssertEqual(index.targetForControl(elementID: "control", facetID: "two"), "target-two")
        XCTAssertEqual(index.targetForControl(elementID: "other", facetID: "one"), "target-other")
    }

    func testControlAndRoleLookupsHaveIndependentFirstMatchesAndNoFallback() throws {
        let roleFirst = try ContextBinding(elementID: "control", facetID: "facet", inputKind: .relative, targetReferenceID: "role-first")
        let roleLater = try ContextBinding(elementID: "control", facetID: "facet", inputKind: .relative, targetReferenceID: "role-later")
        let controlFirst = try ControlBinding(elementID: "control", facetID: "facet", targetReferenceID: "control-first")
        let controlLater = try ControlBinding(elementID: "control", facetID: "facet", targetReferenceID: "control-later")
        let original = BindingContext(context: try context(), entries: [roleFirst, roleLater], controlEntries: [controlFirst, controlLater])
        let reordered = BindingContext(context: original.context, entries: original.entries, controlEntries: [controlLater, controlFirst])
        XCTAssertEqual(original.targetForControl(elementID: "control", facetID: "facet"), "control-first")
        XCTAssertEqual(reordered.targetForControl(elementID: "control", facetID: "facet"), "control-later")
        XCTAssertEqual(original.target(elementID: "control", facetID: "facet", inputKind: .relative), "role-first")
        XCTAssertEqual(reordered.target(elementID: "control", facetID: "facet", inputKind: .relative), "role-first")
        XCTAssertNil(original.target(elementID: "control", facetID: "facet", inputKind: .absolute))
        XCTAssertNil(original.target(elementID: "control", facetID: "facet", inputKind: .press))
        let rolesOnly = BindingContext(context: original.context, entries: original.entries)
        XCTAssertTrue(rolesOnly.controlEntries.isEmpty)
        XCTAssertNil(rolesOnly.targetForControl(elementID: "control", facetID: "facet"))
    }

    func testControlEntryChangesParticipateInBindingTransitionWithoutMintingContext() throws {
        let first = try ControlBinding(elementID: "control", facetID: "facet", targetReferenceID: "first")
        let second = try ControlBinding(elementID: "control", facetID: "facet", targetReferenceID: "second")
        let initial = BindingContext(context: try context(), controlEntries: [first, second])
        var state = BindingContextState(initial)
        XCTAssertFalse(state.apply(initial).changed)
        let reordered = BindingContext(context: initial.context, controlEntries: [second, first])
        let transition = state.apply(reordered)
        XCTAssertTrue(transition.bindingsChanged)
        XCTAssertTrue(transition.changed)
        XCTAssertFalse(transition.contextChanged)
        XCTAssertEqual(state.current.context, initial.context)
        XCTAssertEqual(state.current.targetForControl(elementID: "control", facetID: "facet"), "second")
        let removed = state.apply(BindingContext(context: initial.context, entries: []))
        XCTAssertTrue(removed.bindingsChanged)
        XCTAssertFalse(removed.contextChanged)
        XCTAssertNil(state.current.targetForControl(elementID: "control", facetID: "facet"))
    }

    func testControlBindingRejectsEachEmptyIdentifier() throws {
        for fields in [("", "facet", "target"), ("control", "", "target"), ("control", "facet", "")] {
            XCTAssertThrowsError(try ControlBinding(elementID: fields.0, facetID: fields.1, targetReferenceID: fields.2)) {
                XCTAssertEqual($0 as? BindingContextError, .emptyIdentifier(fields.0.isEmpty ? "elementID" : fields.1.isEmpty ? "facetID" : "targetReferenceID"))
            }
        }
    }
}
