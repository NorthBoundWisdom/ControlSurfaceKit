import XCTest
import SurfaceDeviceConformance

final class ArchitectureTests: XCTestCase {
    func testAllTargetBoundariesAreLinked() {
        XCTAssertEqual(ConformanceBoundary.dependencies, ["contracts", "binding", "connection", "feedback"])
    }
}
