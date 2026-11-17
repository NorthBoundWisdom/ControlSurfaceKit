# Executable scheduler candidate — review proposal

This proposes an additive **test-support-only** API in the existing
SurfaceDeviceConformance product. It is not permission to implement/commit it
before supervisor review. The supervisor approved this interface; implementation
is now in Conformance pending its separate commit review. No sixth production target, source dependency on a
host/SP, real I/O or production scheduling adoption is proposed. The earlier
plan/preflight/receipt block remains commit766a.

## One implementation, two adapters

Place the pure candidate and neutral input/output DTOs in Conformance, whose
existing dependencies already include Contracts/Binding/Connection/Feedback.
Both hosts lock the same subsequent reviewed remote SHA and compile that shared
implementation through their managed dependency. They provide adapters/hooks,
not copied queue algorithms. Main J5 can use the same product as test support.

Use existing ScenarioPayload/TraceValue for opaque native item/scope values in
the *trace-facing* candidate API: complete structured objects, arrays, typed
booleans, explicitnulls and exact strings. Encode UInt64 IDs/cursors/generations
as decimal strings, not potentially lossy JSON numbers. Wire bytes are ordered
arrays or an opaque exact string, never a normalized subset. Objects may use
canonical sorted-key JSON for storage; ordered item/output arrays keep order and
duplicate multiplicity. Native equality/format conversion remains an adapter job.

Proposed values (all Sendable, equality explicit; no callbacks):

```swift
struct SchedulerItem {
    let key: String                 // opaque native queue identity
    let value: ScenarioPayload      // whole wire item + origin + attribution
    let scope: ScenarioPayload      // whole captured queue attribution
}
enum SchedulerRate {
    case unlimited
    case bucket(perSecond: Double, burst: Int, errorCooldown: Double)
}
enum SchedulerInput {
    case initialize(SchedulerRate)
    case enqueue(SchedulerItem)
    case cancel(key: String)
    case drain(at: Double)
    case failure(at: Double)
    case clear
    case requestDirect(SchedulerItem)
    case changeStyle(style: SchedulerItem, projectionKey: String)
    case invalidateCache(affectedKeys: [String])
    case refreshDesired(order: [String])
    case release(key: String)
    case gate(SchedulerGateRecord)
    case receipt(SchedulerActualReceipt)
}
```

An envelope adds schemaVersion1, owner and monotonically increasing *test-only*
ordinal. It does not consume an existing native factory. Only operations that
already possess a time argument carry a time; recording enqueue/cancel must not
read the clock. Timestamps may be **finite signed** values: a1970Date expressed
in the native reference-date domain is legitimately negative. Nonfinite time,
nonpositive/nonfinite rates, nonpositive burst, negative/nonfinite cooldown,
invalid field sets and duplicate/missing ordinals fail visibly. Native output is a separate envelope/file and is
not accepted by the reducer's input decoder.

## Concrete candidate behavior (no device branches)

The first candidate policy is fixed and documented: last-value-per-key queue
replacement retains insertion position; cancel/reinsert appends; clear resets
bucket/cooldown; token refill/drain uses the supplied time. On **negative elapsed
the token balance is reset to0**, matching B's native rule; this is stronger than
adding zero refill while preserving a prior positive balance. It then retains
the new supplied lastRefill value. Drain spends tokens for removed proposals;
failure sets supplied-time
cooldown but performs no hidden requeue. B's actual caller reenqueue operations
are recorded as actual queue ingress, not synthesized from native drain results.
Unlimited rate is a genuine C policy input, not a bypass of its safety gate.

Direct requests propose immediately unless the candidate's own successful-
receipt cache already has the same key/value/semantic scope. The cache updates
only for a matching accepted actual attempt. This intentionally may differ from
C's generated-plan dedup; do not add a device-specific planned-cache branch just
to force zero. A rejected preflight proposal is retained as the candidate's own
latest withheld intent until explicit release/cancel/clear; release proposes its
own retained value and requires a new native proof. Auth/mismatch cases may thus
produce queue-policy differences, but can never bypass the unchanged native gate.
The candidate is shadow-only and never executes its proposals.

Candidate state owns its own ordered queue, withheld intents, proposals awaiting
gate/outcome, successful-receipt cache, tokens/refill/cooldown and local proposal
ordinal. It starts empty. It does not accept native pending IDs, native removed
lists, native token/cache values or a restore-state input. Reusing J3's index
does not substitute for implementing/testing these real scheduling algorithms.

The direct display family owns its own last requested value per key. changeStyle
declares the adapter-known style→projection relationship, not a native redraw
output: after checking its own successful-style cache, the candidate invalidates
its own projection cache and proposes its own earlier desired projection. A raw
local redraw supplies all **protocol-affected** keys (including keys absent from
native cache), never the keys native actually removed. invalidateCache changes
candidate validity only; an actual caller refresh operation uses refreshDesired
with the adapter's complete declared restoration order, not a native nonempty
output list. The candidate chooses existing desired values itself. Thus C's
style/ring/button relationships stay device declarations, not candidate device
branches or copied native generated output.

`SchedulerStep` returns complete candidate state plus ordered proposals, withheld/
canceled/replaced IDs, dedup decisions, gate/receipt associations and any alignment
differences. A proposal is not a permitted send or a receipt.

## Plan-specific native safety resolution

The adapter receives each candidate **own** proposed SchedulerItem. It decodes
that item's native wire payload and evaluates the *original native gates* on the
same fresh native physical/permission/target facts, using an isolated policy
value where the existing validator mutates state. It must not ask "what native
sent" or copy a permitted-output/pending list. Current desired value/physical
observation is an authority/policy input; native scheduling decisions are not.

Normalize that proposed item into a complete trace-facing766a plan:

```swift
typealias SchedulerTracePlan = FeedbackPlan<
    ScenarioPayload, ScenarioPayload, ScenarioPayload,
    ScenarioPayload, ScenarioPayload>
typealias SchedulerTraceProof = FeedbackProof<SchedulerTracePlan, ScenarioPayload>
struct SchedulerGateRecord {
    let proposalOrdinal: UInt64
    let proposedItem: SchedulerItem
    let dispatchPlan: SchedulerTracePlan
    let proof: SchedulerTraceProof
    let currentScope: ScenarioPayload
    let currentNativeSnapshot: ScenarioPayload
}
```

dispatchPlan.payload contains the complete proposedItem.value; queued attribution
is retained in capturedEvidence, alongside actual current dispatch metadata.
Record creation makes no additional time/identity request. Original optional
legacy fields remain explicitnull, even when current dispatch source is known.

The candidate rejects a missing/wrong proposal, mismatching proposedItem/value
or substituted payload. It then uses actual FeedbackPreflight.evaluate with the
complete bound proof and current facts. No gate record, defaulttrue, touch flag
or native list means no permitted proposal. All three physical domains from766a
still apply. The gate record is a native evaluator response for *this proposal*,
not a native scheduler result used to seed the candidate.

`SchedulerActualReceipt` contains an actual transport-boundary outcome, its
complete item/dispatch-plan attribution and current semantic scope. It is an
external outcome input, not native queue state. Match against the candidate's
own outstanding proposal as an ordered occurrence, not by globally unique ref.
If actual native output diverged so no candidate operation matches, emit an
alignment difference and do not invent a candidate attempt or update its cache.
Only real clear/reset operations may realign state. Preserve all downstream diffs.

## Host hook mapping (native continues deciding product behavior)

| Native point | Input hook | Native output recorded separately |
|---|---|---|
| B scheduler init | initialize(full supplied rate/burst/cooldown); enabled/raw policy retained as trace context | Initial ordered payload/scope, tokens/refill/retry fields |
| B enqueue/cancel | Actual full method args before mutation; null source/endpoint/context/mapping retained | Full resulting ordered native items and removed/replaced identity |
| B drain, including cooldown early return | Actual existing supplied Date converted toDouble once; no extra now call | Ordered drained whole items, full pending items, tokens,lastRefill,retryAfter |
| B noteFailure/clear | Existing supplied time or explicit clear | Actual retry/reset state; no candidate requeue from native result |
| B direct dispatch/receipt | requestDirect from original plan input, native gate query for candidate's proposal, actual outcome | Native disposition/accepted callback order/full output bytes and current eligibility |
| C setFader/button/ring/style | Intent input **before generation-time dedup**, with complete payload/current semantic facts | Native proposed/withheld messages, planned-cache validity/payload and pending facts |
| C style's nested ring redraw | Parent/root-operation tag; this is derived native output, **not another candidate external input** | Actual style→redraw order; candidate derives redraw from its own state |
| C touch/release/target/lifecycle/auth changes | Actual raw logical event and fresh native policy facts; release(key) uses own withheld item | Exact native cancellation/pending/cache validity and actual message order |
| C final boundary | Candidate-specific unchanged native gate resolution and actual native receipts | Pre/post-record scope/cutoff eligibility and native result; no real candidate I/O |

C must not begin only at send(messages), because generation-time dedup already
removed relevant requests. It must not feed J3 pendingIndex.upsert/remove output
as candidate enqueue/cancel input. Explicit caller operations such as connection
clear remain genuine inputs, while derived native internal operations are tagged
as outputs. Where C native policy withdraws obsolete intents but the fixed neutral
candidate retains them, report the real difference instead of copying removal.

## Replay files, comparisons and tests

Hooks preserve scheduler-inputs.jsonl and scheduler-native-output.jsonl separately.
Candidate replay is given only inputs (including recorded candidate-specific
gate resolutions/external actual receipts), starts empty and emits candidate
output. It cannot read the native output file. Live shadow can run the same
reducer to obtain proposals for gate queries before saving the complete input
stream; replay must reproduce that own proposal sequence exactly. A gate reply
for another candidate policy/proposal is a visible binding error, not a reseed.

Compare every input ordinal: full queue/withheld/proposal order+payload+scopes,
replacement/cancellation multiplicity, ratio/tokens/refill/cooldown/time fields,
pre-gate proposals, native proof/preflight, actual receipt matching and ordered
permitted/attempted output. Compare pre-gate proposals too, so a wrong candidate
cannot look equal merely because safety blocked both actual streams. Use exact
values, no epsilon, posthoc ID/time remap or ignored attribution fields.

Required candidate unit negatives: dropped/reordered ordinal, replacement moves
position, FIFO reorder, failure refunds tokens or synthesizes requeue, backward
time refill, wrong cached phase, missing/other-plan gate, stale proof, release
reads native instead of own target, unmatched actual receipt, and attempted
native-state restore. A mutation runner must produce concrete expected diffs.
Existing original native tests/goldens exercise actual hooks; synthetic unit
inputs prove the candidate implementation only, never host scheduler equivalence.

Classify each real difference as rate/order/merge policy, generated-vs-accepted
dedup, native device-policy withdrawal/gate, native inconsistency needing ruling,
candidate defect or receipt alignment after divergence. Candidate defects get
fixed; policy differences may remain because scheduling is not being cut.

## Proposed separate commit scope

After review: Conformance candidate/DTO/codec sources, meaningful candidate tests,
test-support documentation and no production scheduler/host/SP/fixture/CI change.
Production target count/edges stay exactly as766a; Conformance remains forbidden
as production dependency. Push/CI must precede either host using the new exact
managed revision. J5 unfinished packages/designs stay out of this support commit.
