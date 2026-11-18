import XCTest
import SurfaceFeedbackPlanning

final class FeedbackSchedulingTests: XCTestCase {
    private typealias Queue = FeedbackQueue<String, String>

    func testReplacementKeepsFIFOAndCancelReinsertAppends() throws {
        var queue = try Queue(rate: .unlimited)
        XCTAssertNil(queue.enqueue("a1", for: "a"))
        queue.enqueue("b1", for: "b")
        XCTAssertEqual(queue.enqueue("a2", for: "a"), "a1")
        XCTAssertEqual(queue.orderedKeys, ["a", "b"])
        XCTAssertEqual(queue.orderedEntries.map(\.item), ["a2", "b1"])
        XCTAssertEqual(queue.cancel("a"), "a2")
        XCTAssertNil(queue.cancel("missing"))
        queue.enqueue("a3", for: "a")
        XCTAssertEqual(try queue.drain(at: -42).map(\.item), ["b1", "a3"])
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.tokens)
        XCTAssertNil(queue.lastRefill)
    }

    func testBurstRefillFractionAndSaturation() throws {
        var queue = try Queue(rate: .bucket(perSecond: 2, burst: 2, failureCooldown: 1))
        for key in ["a", "b", "c", "d", "e"] { queue.enqueue(key, for: key) }
        XCTAssertEqual(try queue.drain(at: -10).map(\.key), ["a", "b"])
        XCTAssertEqual(queue.tokens, 0)
        XCTAssertTrue(try queue.drain(at: -9.75).isEmpty)
        XCTAssertEqual(queue.tokens, 0.5)
        XCTAssertEqual(try queue.drain(at: -9.5).map(\.key), ["c"])
        XCTAssertEqual(queue.tokens, 0)
        XCTAssertEqual(try queue.drain(at: 100).map(\.key), ["d", "e"])
        XCTAssertEqual(queue.tokens, 0)
        XCTAssertEqual(queue.lastRefill, 100)
    }

    func testBackwardsTimeResetsPositiveBalanceAndUsesNewAnchor() throws {
        var queue = try Queue(rate: .bucket(perSecond: 2, burst: 4, failureCooldown: 1))
        queue.enqueue("first", for: "a")
        XCTAssertEqual(try queue.drain(at: 8).count, 1)
        XCTAssertEqual(queue.tokens, 3)
        queue.enqueue("second", for: "b")
        XCTAssertTrue(try queue.drain(at: 7).isEmpty)
        XCTAssertEqual(queue.tokens, 0)
        XCTAssertEqual(queue.lastRefill, 7)
        XCTAssertEqual(try queue.drain(at: 7.5).map(\.item), ["second"])
    }

    func testFailureDoesNotRefundRequeueOrSkipRefillDuringCooldown() throws {
        var queue = try Queue(rate: .bucket(perSecond: 2, burst: 2, failureCooldown: 1))
        queue.enqueue("a", for: "a"); queue.enqueue("b", for: "b")
        XCTAssertEqual(try queue.drain(at: 0).map(\.key), ["a", "b"])
        try queue.noteFailure(at: 0)
        XCTAssertEqual(queue.tokens, 0)
        XCTAssertTrue(queue.isEmpty)
        queue.enqueue("c", for: "c")
        XCTAssertTrue(try queue.drain(at: 0.5).isEmpty)
        XCTAssertEqual(queue.tokens, 1)
        XCTAssertEqual(queue.lastRefill, 0.5)
        XCTAssertEqual(queue.retryAfter, 1)
        XCTAssertEqual(try queue.drain(at: 1).map(\.key), ["c"])
        XCTAssertEqual(queue.tokens, 1)
        XCTAssertEqual(queue.retryAfter, 1)
    }

    func testClearResetsAllSchedulingStateWithoutReplayingDrainedItems() throws {
        var queue = try Queue(rate: .bucket(perSecond: 1, burst: 1, failureCooldown: 2))
        queue.enqueue("a", for: "a"); queue.enqueue("b", for: "b")
        _ = try queue.drain(at: 10); try queue.noteFailure(at: 10)
        XCTAssertEqual(queue.clear(), ["b"])
        XCTAssertEqual(queue.tokens, 1)
        XCTAssertNil(queue.lastRefill); XCTAssertNil(queue.retryAfter)
        XCTAssertTrue(try queue.drain(at: 10).isEmpty)
    }

    func testNonfiniteInputsAndCooldownOverflowAreAtomic() throws {
        var queue = try Queue(rate: .bucket(perSecond: 1, burst: 3, failureCooldown: Double.greatestFiniteMagnitude))
        queue.enqueue("a", for: "a")
        _ = try queue.drain(at: 1)
        queue.enqueue("b", for: "b")
        try queue.noteFailure(at: 0)
        let entries = queue.orderedEntries, tokens = queue.tokens, refill = queue.lastRefill, retry = queue.retryAfter
        for bad in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try queue.drain(at: bad)) { XCTAssertEqual($0 as? FeedbackQueueError, .nonfiniteTime) }
            XCTAssertThrowsError(try queue.noteFailure(at: bad)) { XCTAssertEqual($0 as? FeedbackQueueError, .nonfiniteTime) }
        }
        XCTAssertThrowsError(try queue.noteFailure(at: .greatestFiniteMagnitude)) {
            XCTAssertEqual($0 as? FeedbackQueueError, .cooldownOverflow)
        }
        XCTAssertEqual(queue.orderedEntries, entries); XCTAssertEqual(queue.tokens, tokens)
        XCTAssertEqual(queue.lastRefill, refill); XCTAssertEqual(queue.retryAfter, retry)
    }

    func testInvalidRatePoliciesAreRejected() {
        let bad: [FeedbackQueueRate] = [
            .bucket(perSecond: 0, burst: 1, failureCooldown: 0),
            .bucket(perSecond: -.infinity, burst: 1, failureCooldown: 0),
            .bucket(perSecond: .nan, burst: 1, failureCooldown: 0),
            .bucket(perSecond: 1, burst: 0, failureCooldown: 0),
            .bucket(perSecond: 1, burst: 1_000_001, failureCooldown: 0),
            .bucket(perSecond: 1, burst: 1, failureCooldown: -1),
            .bucket(perSecond: 1, burst: 1, failureCooldown: .infinity),
        ]
        for rate in bad { XCTAssertThrowsError(try Queue(rate: rate)) { XCTAssertEqual($0 as? FeedbackQueueError, .invalidRate) } }
    }

    func testQueueCopiesOwnIndependentPayloadOrderAndBucket() throws {
        var original = try Queue(rate: .bucket(perSecond: 1, burst: 2, failureCooldown: 1))
        original.enqueue("a", for: "a"); original.enqueue("b", for: "b")
        var copied = original
        copied.enqueue("changed", for: "a"); _ = try copied.drain(at: 0); try copied.noteFailure(at: 0)
        XCTAssertEqual(original.orderedEntries.map(\.item), ["a", "b"])
        XCTAssertEqual(original.tokens, 2); XCTAssertNil(original.lastRefill); XCTAssertNil(original.retryAfter)
        XCTAssertTrue(copied.isEmpty)
    }

    func testEveryRequestPreservesEachInvocationAfterIdenticalReceipt() {
        var state = FeedbackRequestState<String, String>(repeatedRequestPolicy: .proposeEveryRequest, withdrawnIntentPolicy: .discard)
        XCTAssertEqual(state.request("same", for: "a"), "same")
        state.recordAccepted("same", for: "a")
        XCTAssertEqual(state.request("same", for: "a"), "same")
        XCTAssertEqual(state.request("same", for: "a"), "same")
    }

    func testProposalAndReceiptPhasesAreIndependent() {
        var generated = FeedbackRequestState<String, String>(repeatedRequestPolicy: .suppressAfterProposal, withdrawnIntentPolicy: .discard)
        XCTAssertEqual(generated.request("same", for: "a"), "same")
        XCTAssertNil(generated.request("same", for: "a"))
        XCTAssertTrue(generated.accepted.isEmpty)
        var receipt = FeedbackRequestState<String, String>(repeatedRequestPolicy: .suppressAfterAcceptedReceipt, withdrawnIntentPolicy: .retainLatest)
        XCTAssertEqual(receipt.request("same", for: "a"), "same")
        XCTAssertEqual(receipt.request("same", for: "a"), "same")
        XCTAssertTrue(receipt.proposed.isEmpty)
        receipt.recordAccepted("same", for: "a")
        XCTAssertNil(receipt.request("same", for: "a"))
        XCTAssertEqual(receipt.request("changed", for: "a"), "changed")
        receipt.invalidate(["a"])
        XCTAssertEqual(receipt.request("same", for: "a"), "same")
    }

    func testWithheldLatestValueAndWithdrawalPoliciesDoNotProposeOrAcknowledge() {
        for policy in [WithdrawnIntentPolicy.discard, .retainLatest] {
            var state = FeedbackRequestState<String, String>(repeatedRequestPolicy: .suppressAfterProposal, withdrawnIntentPolicy: policy)
            _ = state.request("old", for: "a"); state.recordAccepted("old", for: "a")
            state.withhold("first", for: "a"); state.withhold("b", for: "b"); state.withhold("latest", for: "a")
            XCTAssertEqual(state.withheldKeys, ["a", "b"])
            state.withdraw(["a"])
            XCTAssertNil(state.proposed["a"]); XCTAssertNil(state.accepted["a"])
            XCTAssertEqual(state.release("a"), policy == .retainLatest ? "latest" : nil)
            XCTAssertNil(state.proposed["a"]); XCTAssertNil(state.accepted["a"])
            state.cancel("b")
            XCTAssertTrue(state.withheld.isEmpty); XCTAssertTrue(state.withheldKeys.isEmpty)
        }
    }

    func testScopeInvalidationAndCopyIndependence() {
        struct Intent: Equatable, Sendable { let scope: Int; let value: Int }
        var state = FeedbackRequestState<String, Intent>(repeatedRequestPolicy: .suppressAfterAcceptedReceipt, withdrawnIntentPolicy: .retainLatest)
        let old = Intent(scope: 1, value: 3), new = Intent(scope: 2, value: 3)
        state.recordAccepted(old, for: "a"); state.withhold(old, for: "b")
        XCTAssertEqual(state.request(new, for: "a"), new)
        var copy = state
        copy.clear()
        XCTAssertTrue(copy.accepted.isEmpty); XCTAssertNil(copy.release("b"))
        XCTAssertNil(state.request(old, for: "a")); XCTAssertEqual(state.release("b"), old)
        state.invalidate(["a"])
        XCTAssertEqual(state.request(old, for: "a"), old)
    }
}
