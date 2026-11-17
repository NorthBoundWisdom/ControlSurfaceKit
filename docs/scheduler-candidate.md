# Test-only scheduler candidate and v1 trace protocol

SurfaceDeviceConformance exports this candidate only as test support. No
production target may import Conformance. This is a fixed candidate policy for
real difference measurement, not adoption of a shared production scheduler.

## Input-only use

```swift
var candidate = SchedulerCandidate()
for data in inputRecords { // caller loads data; the library does no I/O
    let event = try SchedulerTraceCodec.decodeInput(data)
    let step = try candidate.apply(event)
    let completeOutput = try SchedulerTraceCodec.encodeStep(step)
    // caller stores completeOutput separately from original native output
}
```

The first event is initialize, owner is fixed thereafter, and ordinals start1
and remain contiguous. Failed events leave state/ordinal unchanged. Initialize
cannot restore state. Input decoder rejects output envelopes, unknown fields/
operations, duplicate JSON keys (including escaped equivalent keys), excessive
depth/size, nonfinite scalars and malformed canonical decimal cursors. Opaque
native objects preserve all fields; explicitnull differs from missing/unknown.
UInt64 fields are decimal strings. Wire byte arrays and all ordered lists retain
order and multiplicity. No field/ID/time normalization is performed.

Envelope keys are exactly schema_version,owner,ordinal,operation,arguments,context.
Context is required (null when absent); it preserves raw native context without
feeding it into queue state. The typed constructors and encodeInput avoid manual
JSON assembly. Each item's key is an opaque nonempty queue key; value is the whole
native item including ID/time/actor/optional attribution, scope the whole capture.

## Fixed candidate policy

- enqueue replaces the latest item without moving its insertion position;
  cancel/reinsert appends. Queue drain is FIFO. Direct requests bypass the bucket.
- bucket policy uses explicit supplied timestamps, a positive finite rate and
  bounded positive burst, and finite nonnegative cooldown. **Finite signed time
  is valid**:1970 expressed in reference-date seconds is negative. Negative
  elapsed **resets the balance to0**, not just zero refill preserving old tokens,
  then records the new lastRefill. This matches the measured B native rule.
- drain spends tokens for removed items/proposals. failure sets cooldown and
  never refunds tokens or silently requeues. Caller reenqueue is its own input.
- enqueue ingress is either externalRequest or
  derivedCallerRequeue(causeOrdinal:). Cause remains encoded in the raw input;
  the latter is not declared a fresh external desire and never clears prior
  drain/alignment differences. Root comparison must retain the whole chain.
- desired changes only on an actual enqueue/direct/style request, not when an
  old queued item drains. Style→projection relationship and refresh order are
  explicit device declarations. Redraw uses the candidate's own earlier desired
  value, not native generated redraw output. invalidateCache receives all
  protocol-affected keys, never the native cache's actually removed list.
- dedup uses **whole SchedulerItem equality** (key/value/scope) only after an
  actual matching accepted receipt in the current semantic scope. If value
  contains a new ID/time/actor, same wire bytes need not dedup; report that fixed
  key-policy difference. No temporary projection is used to make a host green.
- rejected preflight proposals retain the candidate's own latest withheld value
  until explicit release/cancel/clear; release still needs a new native proof.
  This can intentionally differ from native auth/mismatch withdrawal. It is
  not an authorization change and never produces actual I/O.
- clear resets queue/withheld/cache/bucket/cooldown but retains desired values,
  outstanding proposal/attempt association and persistent alignment history.
  A native caller owns already drained work independently from queue clear.

These differences from C generation-time planned dedup and native device-policy
withdrawal are measured, not hidden by an alternate device branch.

## Candidate-specific safety and actual receipt association

A SchedulerProposal is produced by the reducer and is never a send permit. The
adapter queries unchanged native device gates on this proposal's own encoded
item under the same fresh native policy facts, isolated where validation mutates
state. No native permitted-output/pending list or optional touch flag is accepted.

Build SchedulerTracePlan and SchedulerTraceProof from that evaluation. Plan
payload must equal proposedItem.value. Its full capturedEvidence must be
`SchedulerTraceCodec.queuedEvidence(for:nativeDispatch:)`, preserving the whole
queued item and richer native dispatch evidence. Then supply SchedulerGateRecord
with exact proposal ordinal/item/plan/proof and fresh current scope/snapshot.
The reducer validates this binding and uses actual766a FeedbackPreflight. No
record/default pass means no ready proposal. Semantic scope and complete evidence
remain separate; the physical/Mock/rehearsal domains retain their native rules.

An actual transport-boundary completion is SchedulerActualReceipt. Match full
item plus complete plan against the candidate's own ready proposals as an
ordered occurrence, without assuming globally unique references. An unmatched
native completion is a persistent alignment difference: it never creates an
imaginary candidate attempt/cache entry. Accepted old-scope completion can stay
accepted evidence but cannot update current cache. A matching rejected attempt
invalidates that current cache key without automatic replay. No-attempt does
not count as a successful transport.

The candidate never calls a sender, clock or callback. Full snapshots expose
queue/withheld/desired/cache/proposals, token/refill/cooldown values and persistent
alignment. Each step adds proposals, removal/replacement/dedup decisions, gates
and receipt associations. SchedulerTraceDiff compares complete supplied payloads
recursively and exactly, including absent-versus-null and array order; it has no
ignore list, tolerance, identity remap or native-file reader.

## Native adapters and evidence

B hooks real init/enqueue/cancel/drain/failure/clear inputs, including cooldown
early returns and derived caller requeue. C hooks intent entries before planned
dedup, actual physical/lifecycle changes and explicit release; starting at its
filtered send array or replaying J3index changes would lose the behavior tested.
Style's nested native redraw remains an output, not another candidate input.
Compare pre-gate proposals as well as permitted outcomes so safety cannot hide
wrong candidate state. Native output stays in a separate file.

Live shadow records candidate-specific gate results as input responses; replay
must reproduce the same own proposal sequence from that input alone. A gate
for a different candidate policy/proposal fails binding instead of reseeding.
Preserve first/all differences and causal/alignment records. Classify rate/order/
merge, whole-item key choice, planned-versus-accepted dedup, device-policy gate/
withdrawal, native inconsistency, candidate defect or downstream alignment.
Unit/mutation tests establish this implementation; only actual full native hook
records establish each host's scheduling differences. They do not authorize cut.
