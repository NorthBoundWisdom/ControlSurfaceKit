# Caller-driven feedback scheduling

`SurfaceFeedbackPlanning` provides scheduling values, separately from its
immutable plans, mandatory preflight and actual transport receipts. No scheduling
operation sends, reads a clock, creates an identity or grants output permission.
Every exposed value is Sendable; the existing owner supplies serialization.

## Queue and time

`FeedbackQueue<Key, Item>` owns the one ordered key/item queue and the bucket.
An item may contain the full native immutable plan, scope and attribution. Keys
and payloads are opaque; the kernel knows no device addresses or control count.

```swift
var queue = try FeedbackQueue<String, NativePlan>(
    rate: .bucket(perSecond: 120, burst: 4, failureCooldown: 1))
queue.enqueue(plan, for: queueKey)
let proposals = try queue.drain(at: suppliedInstant)
// For each entry.item: native current scope/proof/gates, then actual transport.
// A failed actual attempt can call noteFailure(at: suppliedFailureInstant).
```

Replacement preserves insertion position. Cancel and reinsert appends. Drain
removes FIFO and spends tokens for those removed items, not for accepted sends.
Failure sets a supplied-time deadline; it neither refunds tokens nor retries.
The caller may explicitly reenqueue as its own later input. Cooldown drain still
refills the bucket and anchors its supplied instant before returning no work.
Backward time resets tokens to zero and records the new anchor. Signed finite
instants are valid. Nonfinite time and cooldown overflow fail before mutation.
Clear discards the queue and resets burst/refill/deadline without replay. An
adapter replacing configuration constructs a new queue with the new rate.

`orderedKeys`, `orderedEntries`, `tokens`, `lastRefill` and `retryAfter` expose
complete scheduling facts for temporary independent comparison. They are not
physical observations, successful receipts or a state-restore API. `.unlimited`
is an explicit rate choice and does not bypass any native safety evaluation.

## Request equality and withheld intent

`FeedbackRequestState<Key, Value>` makes three scheduling phases explicit:

| RepeatedRequestPolicy | Meaning |
| --- | --- |
| proposeEveryRequest | Return a proposal for every invocation, including repeated identical requests after accepted output. Per-request acknowledgement remains native. |
| suppressAfterProposal | Compare only the caller-defined generated value. Updating this cache does not claim any transmission or receipt. |
| suppressAfterAcceptedReceipt | Suppress only after the caller explicitly records a real matching current-scope accepted receipt. A proposal alone changes no accepted cache. |

The caller's Equatable value must preserve the exact native equality domain.
Scope/generation belongs in that domain or is invalidated at the original native
lifecycle boundary. Do not compare whole captured metadata when the native cache
compares a wire projection, or omit scope when the native cache requires it.
The adapter must perform its original final receipt/scope/reentry checks before
calling `recordAccepted`; this operation cannot manufacture a transport fact.

`withhold` retains the latest caller intent without marking it proposed or sent.
`release` returns that owner's own retained value for fresh native evaluation.
Withdrawal invalidates caches and uses the explicit `WithdrawnIntentPolicy`:
`discard` removes retained intent; `retainLatest` keeps it until a later explicit
release/cancel/clear. Neither policy releases work automatically. Lifecycle
`clear` always discards all cached and retained state. No policy is an optional
touch/layer/motor gate.

## Proposed host choices and acceptance

BCR's proposed use of `proposeEveryRequest` and `discard` preserves a native
admission/transport receipt and callback for every synchronous invocation. Its
callback linearization remains native. Compact's proposed choice for generated
nonmotor caches is `suppressAfterProposal`. Its desired feedback, redraw
relationships, ordering, physical observations and contact/layer/motor policies
remain native. Each host must preserve its evidenced intent lifetime on
permission withdrawal. See the [One paper policy](new-device-example.md#proposed-scheduling-policy-for-one)
for an example of using `suppressAfterAcceptedReceipt` for display repaint.

The minimal hypothetical device's `CompleteDeviceRuntime` now uses the shared
queue for deferred immutable plans, flush and invalidation, with `.unlimited`.
Its device adapter contains no queue, bucket, cooldown or scheduling algorithm.
Original fixture operations/assertions, real authority process and native output
gates remain unchanged. Queue unit tests exercise finite rate/cooldown policies;
the original complete integration exercises the shared queue in applicable
scenarios. Host adoption still requires independent input-only zero-difference
comparison and exact-commit CI; merely adding this API does not switch a host.
