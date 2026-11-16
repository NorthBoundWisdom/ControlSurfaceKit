# J4 feedback plan/proof/receipt API — proposal, not implementation

The supervisor approved the shape and C J3 budget gate. These values are now
implemented in the feedback target; host shadow/adoption remains separate.
Native evidence and exact
line references are in [j4-native-inventory.md](j4-native-inventory.md).

The supervisor approved the *dependency direction*: FeedbackPlanning may import
the earlier Contracts, BindingContext and ConnectionState targets directly.
The five production targets and absence of SP/host dependencies remain intact.
The checker must explicitly enforce these edges and reject reverse edges,
Conformance as production dependency, cycles, native imports and external
business packages. It is not a transitive-import workaround.

## 1. Immutable plan without a new ID or clock read

The plan must carry all facts used for dispatch/proof matching, including the
actual native wire payload as an opaque generic value. J2 EffectDescriptor is
not an ideal mandatory constructor argument: it requires an ID and time, whereas
B's current pre-send plan has neither. Forcing one would consume a new clock or
ID factory and change observable sequences. Keep trace-descriptor construction
at the existing native record point.

Suggested shape (all generic bounds Equatable & Sendable):

```swift
enum FeedbackDeliveryMode: Equatable, Sendable { case direct, coalescible }

struct FeedbackPlan<Payload, Origin, Scope, Reference, CapturedEvidence>: Equatable, Sendable {
    let reference: Reference
    let payload: Payload
    let origin: Origin
    let scope: Scope
    let source: DeviceSource
    let endpointEvidence: EndpointProvenance
    let capturedEvidence: CapturedEvidence
    let targetID: String
    let affectedElements: Set<String>
    let classification: EffectClassification
    let sideEffects: Set<EffectDirection>
    let deliveryMode: FeedbackDeliveryMode
    // requiredDirections = classification.direction union sideEffects
}
```

Reference is a caller-supplied existing cause/reference or a value derived from
already captured facts/position. It is **not assumed globally unique**, is not a
bearer capability and is never the sole proof or dedup key. Full plan equality
includes payload, source, captured evidence, actor/cause, semantic scope, target,
affected elements, category/side effects and delivery mode. Reusing the reference
with changed facts invalidates the proof. No UUID, incremented token, Date.now,
timer or time read is added merely for plan construction.

Native message bytes, layouts and protocol facts remain outside Core. Keeping
the opaque payload in the value prevents a proof for one encoded operation
being accidentally applied to another operation with a similar neutral label.
Origin remains a generic captured native value; it does not invent a universal
local/remote actor classification from B external or from connection source.

EndpointEvidence records the common IDs/generation/origin vocabulary; it does
**not** represent every native captured field. CapturedEvidence is a mandatory
opaque immutable native value retaining the complete captured endpoint object,
its name/qualification and object presence, native dispatch facts and genuinely
optional legacy attribution. No default empty evidence value is supplied by the
API. An adapter with no extra native facts can explicitly use its empty value;
the existing hosts cannot use that to erase their facts.

CapturedEvidence equality must compare **all** its fields. It must not reuse a
custom semantic-scope equality that intentionally ignores cosmetic data. If a
native endpoint type's equality omits fields, the host supplies a complete value
DTO with explicit field equality. Nil native endpoint/attribution stays nil;
an explicitly unknown provenance object remains a different captured fact.
Do not fill an absent legacy source/endpoint/time with current known values.

Scope is the existing semantic identity, independent of the two evidence values.
C cosmetic endpoint name/qualification/origin updates therefore do not become
new current-scope denials. A proof still binds the complete *captured plan*:
changing any recorded evidence field while reusing that proof is planMismatch,
even when current semantic scope remains valid. The current-scope gate does not
compare plan evidence to newly sampled cosmetic data. Adapters retain complete
raw evidence in J4 shadow records alongside common EndpointProvenance; the
existing J2 projection alone is not the full-evidence comparator.

The freshness snapshot includes facts actually used by the existing native
safety/authorization predicates; it does not smuggle cosmetic fields into a new
dispatch predicate. A new plan/proof pair can retain newly captured cosmetic
facts while the semantic scope stays the same. Adapters preserve their existing
full scope predicates, never replacing them with a loose token. Native transport
pins still run at final I/O.

Delivery mode answers only whether existing coalescing may be used. B synchronous
maps to direct; its request acknowledgment/transaction rules remain separate.
C uses direct; native touch withholding is not a token-bucket scheduling mode.
The shared pure dispatch choice can replace B's `canCoalesce && coalescible`
decision. Rate refill, cooldown, retry and dedup algorithms are not adopted in
this J4 block; they receive a truthful shadow/difference report.

## 2. Explicit plan-bound authorization and fresh native safety result

No optional safety closure, `touchPolicyEnabled`, default-true gate or global
management grant is accepted. The trusted adapter produces a value only after
running the original final native gates for this particular effect.

```swift
enum PlanAuthorization: Equatable, Sendable {
    case granted(directions: Set<EffectDirection>)
    case denied(reason: String)
}
enum NativeSafetyResult: Equatable, Sendable {
    case passed
    case rejected(reason: String)
}
struct FeedbackProof<Plan, NativeSnapshot>: Equatable, Sendable {
    let plan: Plan
    let nativeSnapshot: NativeSnapshot
    let authorization: PlanAuthorization
    let safety: NativeSafetyResult
}
```

NativeSnapshot is an immutable native value of the safety/freshness facts
actually checked at this point. It can contain existing observation revisions,
actor/action ownership and mode/gate data; Core does not interpret device fields.
It uses existing state, not a new UUID/time source. At preflight the caller also
provides the **current** semantic scope and native snapshot. Core verifies:

1. proof.plan equals the entire proposed plan, not just its reference;
2. plan.scope equals the current native semantic scope;
3. proof.nativeSnapshot equals the current snapshot;
4. authorization is explicitly granted for all required directions;
5. safety explicitly passed.

Supervisor-approved narrowing rule: granted directions must equal the plan's
required union (no missing or unrelated surplus grant). The adapter can narrow
genuine existing rights to the particular plan, but cannot invent a missing
direction. Missing management never defaults to allowed.

The snapshot comparison is a freshness check of the proof, not a new global
business revision gate. Adapters remint the proof after the actual final native
checks before each attempt. They do not queue/cache a proof with an earlier plan
or carry it across callbacks. A physical fact change that leaves native dispatch
semantically valid can receive a fresh proof; it is not forced into lifecycle
scope or turned into a fabricated observation.

For C's context selector, only its **existing explicit local command path**,
after current actor/mode/layer/global-touch/mechanism gates, may issue exactly
management+mechanism for that encoded operation. Generic allowsMechanisms does
not grant arbitrary management. Diagnostic command paths need their existing
specific local approval as well. Remote hardware vocabulary still cannot encode
the command. No root/UI/service permission surface is added by this proof type.

The safety result is evidence from trusted native code, not remote request data.
The native final gate/transport pin remains physically mandatory. Core neither
executes a callback nor asks a caller to switch device safety off. Host integration
must demonstrate the proof is minted by the actual native path, not an unconditional
`.passed` wrapper that leaves all shared decisions untested.

## 3. Preflight outcome is distinct from an actual attempt

Proposed pure preflight result vocabulary:

```swift
enum FeedbackPreflight: Equatable, Sendable {
    case permitted
    case rejected(FeedbackRejection)
}
// Rejection categories: planMismatch, staleScope, staleNativeProof,
// authorizationDenied, missingDirection, surplusDirection, nativeRejected.
```

Rejection must preserve a native reason where relevant. Hosts retain their
existing outward error/monitor mapping; this does not create a new public
consumer error code. Preflight creates no transmission evidence, input event,
observation, sent cache, budget refund or automatic retry.

Permission checking stays at the old per-message versus whole-batch boundary.
In C, an existing global touch/context assertion can reject the whole batch;
an individual withheld motor can coexist with allowed display messages. Core
must not replace that with a blanket all-effects union denial. B's partial
synchronous transaction remains output-may-have-occurred, with narrow overlay
undo and its invocation-local accepted callback.

## 4. Receipt facts and current-canonical eligibility are separate

Suggested value receipt layer:

```swift
enum FeedbackAttemptResult: Equatable, Sendable {
    case notAttempted(reason: String)
    case accepted
    case rejected(reason: String)
}
struct FeedbackReceiptFact<Plan>: Equatable, Sendable {
    let plan: Plan
    let result: FeedbackAttemptResult
    // successfulSend is true only for accepted.
    // hasTransportAttempt is false only for notAttempted.
}
```

Here an attempt means invocation of the real native transport boundary. A
rejection inside its pin can be a rejected transport attempt while physical
write count is still zero. An admission failure before calling that boundary is
notAttempted. Do not claim bytes were physically emitted from merely attempting
or receiving a failed delivery label.

The receipt retains old captured plan facts even if a callback has changed the
current canonical owner. A separate pure query compares the captured semantic
scope to the **current** native scope at the existing bookkeeping point. It
does not recompute successfulSend from current permission and does not compare
all physical proof facts after completion: newer actual input must survive via
the existing native revision cutoff, not be rejected or overwritten.

No additional timestamp is required for this receipt value. When the native
record point already supplies an actual completion/record time and ID, the old
J2 TransmissionEvidence projection can use those same values. B must not add a
new historyTime/now call where its old code did not read one; C reuses its existing
transportMonotonicTime. Unknown timing is not filled with dispatch or wall time.
There is no conversion from a receipt into DeviceObservation.

Optional pure batch aggregation can replace B's nonempty/all-sent/any-sent value
tests, but cannot own its accepted callback or mutable collector. Deferred or
suppressed entries are not successful attempts. C's native empty-batch `.sent`
return is a legacy method disposition, not a transmission receipt; keep that
return mapping without manufacturing a send. No automatic replay is provided.

## 5. Required placement in each caller

| Caller | Plan/proof/preflight placement | Receipt/current-owner placement |
|---|---|---|
| B transmit/enqueue | Retain origin/timing selection and observe policy. Build from already captured native/queued scope; shared dispatch choice preserves synchronous bypass. Fresh native proof at actual transmitNow after its existing checks. | Accepted receipt follows actual device.send. Current eligibility gates existing noteFeedbackSent before receipt callback; invocation-local collector/accepted hook still precedes monitor/journal callbacks. Late failure cannot mutate new owner/cooldown. |
| B explicit display | Preserve original begin-overlay ownership, nonempty ordered plan and synchronous collector. Native authority/display/write/source gates remain. | Keep partial-output delivery_failed, current canonical mutation, narrow undo and repeated scope rechecks at old points. No whole candidate crosses I/O. |
| C GUI console | Preserve generation-time planned dedup and ordered message construction. Per-plan proof follows existing native whole-batch/per-message device gates; native transport pin still checks actual IDs/generation. | Actual accepted record remains before post-record scope recheck. Recompute eligibility there, then use original observation/receipt cutoff. Current failure clears native histories; stale failure does not clear a newer owner. |
| C hardware display service | Keep typed display-only encoding. Native source/link/context permission plus actual pin forms specific plan proof; budget still spent before any I/O. | Real contract event commits only after every typed message returns accepted. No motor/context operation becomes expressible, no input/lifecycle output is added. |

Existing native origin-scoping and callback rules remain. In particular, B's
withBatch clears to nil after a child request rather than restoring its enclosing
cause; C's withPlannedProvenance does restore previous metadata. These are
different native orchestration contracts, not a reason for a shared callback API.

## 6. Executable scheduler shadow, without scheduler adoption

The difference table alone is insufficient. Both hosts must record actual native
scheduler inputs and run a separate test-only neutral candidate with its own
empty initial queue/bucket/cache. Product output remains entirely native.

### Recording and independence

Native hooks record inputs at existing call boundaries: enqueue/replace/cancel/
clear, dispatch mode, drain with the actual supplied time, actual transport
outcome, and actual release/readiness events. Capture the full opaque payload,
origin, semantic scope, current rate policy and ordered batch facts. A dedicated
test-only ordinal may order records; it must not query a clock or consume an
existing host ID factory. An existing native `now` argument is copied, not read
again by the hook. Nested callbacks retain their real event order.

Save `scheduler-inputs.jsonl` independently from `scheduler-native-output.jsonl`.
The candidate executable can read **only** the input file and declared policy,
never the native output file. It writes `scheduler-candidate-output.jsonl` from
its own value state. The comparison program opens both output files afterward.
Thus neither native canceled IDs nor its drain/output list can reseed a candidate.

The test-only candidate must implement genuine queue replacement/order, rate
refill/drain, dedup and attempt accounting; simply reusing the J3 resource index
and comparing IDs is not a scheduler proof. A proposed starting policy uses
last-value-per-key replacement with retained insertion order, a supplied finite
bucket or unlimited rate, direct versus coalescible dispatch, successful-receipt
dedup and explicit failure/cooldown handling. It can intentionally differ from
C's generation-time dedup; those real differences are reported, not concealed
with device branches or silently changed production cache timing.

For B, instrument actual queue ingress/drain/failure boundaries and record the
delivery-mode decision's input before selecting enqueue versus direct. For C,
instrument **intent entries before generation-time dedup**: setFader/setButton/
setRing/setRingStyle, decoded input/lifecycle/authorization changes, and release
reconciliation. Starting only at `ConsoleModel.send(messages)` would hide every
request already removed by planned dedup and is not sufficient. Feeding the J3
index's upsert/remove output as the candidate's input would be reseeding by the
answer and is prohibited.

Tag nested native calls with the real parent/root operation. A style change's
internally generated ring-redraw call is a derived native output, not an extra
external ring intent for the candidate. The candidate must derive its redraw
from its own earlier desired-ring state. Likewise, it reconciles its own pending
release target, not the message/target returned by native reconciliation. Compare
proposed operations before the final native gate as well as permitted outputs,
so a bad candidate is not declared equal merely because safety rejected both
streams' actual sends.

### Device gates remain mandatory native inputs

The candidate owns queue policy, not touch/layer/motor/preset policy. Raw release
events and the actual immutable native safety state are recorded. The adapter
evaluates its unchanged safety gate **for the candidate's own proposed plan**
and supplies the nonoptional plan-bound native proof/current snapshot. It does
not supply a native permitted-output list, pending set or "whatever native sent"
answer. A candidate proposal rejected by the real native gate is a rejected
proposal in the shadow record, never a send. There is no disable flag or default
ready result. The actual final native gate remains in the product path too.

For example, candidate release handling must consume its own earlier staged
target. It cannot copy the target returned by native release reconciliation.
The unchanged native safety evaluator sees that candidate target plus the same
fresh touch/mismatch/ownership facts and returns its specific plan proof. A
different candidate target, missing target, wrong direction or stale proof is
visible as a difference or rejected proposal.

### Step comparisons and divergence handling

Compare each operation's disposition, full pending order/payload/origin/scopes,
replaced/canceled IDs including multiplicity, token/refill/cooldown state where
present, dedup validity, and ordered proposed/withheld/attempted output plus actual
receipt association. Every value/byte/time is exact; there is no epsilon or
post-hoc identifier remap. Record both the first difference and all subsequent
observable differences with the source operation and original input ordinal.

After a divergence an actual native transport outcome may have no matching
candidate outstanding operation. Record that as an alignment difference rather
than inventing a candidate attempt or resetting it from native state. Continue
from the candidate's own state. Only an explicit reset/clear in the real input
stream may reset both. Compare matching exact payload/scope/origin occurrences
as an ordered multiset; do not assume the current native plan reference globally
uniquely identifies an attempt.

Classify differences as rate/order/merge policy, planned-versus-accepted dedup,
native device-policy rejection, old native inconsistency needing supervisor
ruling, or a candidate defect. Candidate defects are fixed; device safety stays
native; legitimate scheduling differences need not reach zero because scheduling
is not being adopted in this block. Neither a failure label nor a different
schedule is converted into a physical-NA result.

### Actual coverage and negative controls

- B: actual existing scheduler tests plus applicable scenes/goldens must emit
  enqueue/replace/FIFO drain, supplied forward/backward time, token exhaustion,
  failure/cooldown/requeue, direct acknowledged bypass and nested callback
  enqueue/source/mapping/queue invalidation.
- C: actual existing touch/release/old-context release, target supersession,
  same-value redraw/style ordering, blocked batch/context command, failure and
  reconnect cases emit staged/replace/release/gate/receipt operations. No common
  finite rate limit is invented for a native path that has none.
- Negative controls reorder a drain, drop a replacement, incorrectly refund
  failure tokens, update a dedup cache at the wrong phase, or reuse an obsolete
  release target. The comparison must produce a concrete difference. A missing
  input/output step or unmatched actual receipt must also fail alignment.

Reports give exact input/operation counts, source hashes, candidate policy,
first/all differences and classification, with all three raw files preserved.
Full host suites/scenarios/goldens remain required for the formal plan/preflight/
receipt cut independently. Scheduler stays shadow-only unless a later explicit
decision approves a particular proven common policy.

## 7. Acceptance and negative coverage

- Core tests mutate every plan field while retaining the same reference and
  require planMismatch; test duplicate/nonunique references without using them
  as global authorization. Missing classification side-effect direction rejects.
- Full-evidence negative tests change native name, qualification, native optional
  endpoint presence and nil-versus-explicit-unknown attribution while preserving
  IDs/generation and semantic Scope. Old proof with changed plan evidence rejects
  planMismatch. Separately, original plan/proof under the still-equal semantic
  scope remains eligible, and a fresh matching plan/proof with the new captured
  facts can pass. Both dimensions are asserted; cosmetic data is neither dropped
  from proof/trace nor forced into the current-scope comparison.
- Freshness tests change native snapshot or semantic scope separately; cosmetic
  provenance changes stay evidence under C's unchanged semantic key. No identity
  is normalized away in complete host trace comparisons.
- Authorization/safety tests reject explicit denials, missing management for a
  mechanism-only grant, rejected local native safety and proof reuse for another
  payload/target/actor. Exact-grant rule has an explicit surplus-direction case.
- Receipt tests distinguish notAttempted, failed attempt and accepted old-scope
  send; successfulSend remains true for an accepted stale completion while
  current-canonical eligibility becomes false. No observation is returned.
- Host shadows independently compare plans, direction unions, native proof/
  preflight/attempt facts and actual ordered output with all old suites/scenarios
  and golden samples. Keep B accepted-hook and C post-record/cutoff reentry tests.
- Boundary tests explicitly allow only the approved earlier direct imports and
  reject reverse/cyclic/test-support/external/native dependencies. Any updated
  old edge-policy test is mapped and explained by this approved DAG change,
  never silently deleted or treated as permission to weaken I/O checks.

The J5 checkpoint prototypes remain uncommitted test infrastructure. After the
formal J4 shape is approved and both callers adopt it with zero differences,
they will replace the checkpoint's requiresJ4Dispatch fence with this actual
shared implementation and execute every applicable original scenario. No
test-only success/preflight oracle is introduced to make that matrix pass.
