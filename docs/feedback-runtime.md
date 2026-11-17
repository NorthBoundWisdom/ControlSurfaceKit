# Feedback plans, native proof and transport receipts

This block supplies synchronous Sendable dispatch facts/decisions. It never
sends, reads a clock, creates an identity, owns a parameter value, implements a
device gate or schedules a timer. Dependencies point only to earlier Contracts,
BindingContext and ConnectionState. Unit tests establish the common rules;
independent host shadows establish adoption.

## What a new adapter provides

- Immutable Equatable/Sendable native Payload and Origin values. Classification,
  side effects, affected physical roles and encoding come from trusted adapter
  knowledge, never a remote caller's claim.
- Semantic Scope with the actual lifecycle/binding/permission identity and pure
  equality. Preserve native route predicates and the final actual transport pin.
- Mandatory full CapturedEvidence: raw endpoint objects, names, qualification,
  presence, optional legacy attribution and already captured metadata. Its
  equality compares every field; it must not reuse a cosmetic-ignoring Scope
  equality. Common EndpointProvenance does not replace richer raw evidence.
  Missing/unknown facts stay missing/unknown; the current UI cannot fill them.
- An existing or derived Reference. It is not globally unique or a bearer token.
  No new UUID, counter or clock read is required. Complete plan equality binds
  the proof, including payload, origin, source, scope, evidence and all effect
  facts; reference equality alone grants nothing.
- Actual per-plan authorization and final native safety results, plus the native
  facts checked and their fresh current values. Snapshot equality must be pure.
  There is no optional safety/default-passed API argument or disable flag.

The host also supplies the single serial owner, its existing parameter authority,
trusted time, actual sender and receipt callbacks. Core stores none of those.
The adapter must bind route/mode/generation changes into scope and the fresh
native snapshot, preserve its original final transport pin and callback order,
and invalidate pending work on generation changes without replay. Unknown
hardware context and position stay unknown; encoding or accepting a display
command never supplies an observation.

`FeedbackPlan` adds target/affected IDs, classification, sideEffects, source and
deliveryMode to these facts. `requiredDirections` is the full classification plus
side-effect union. `dispatchChoice(canCoalesce:)` chooses enqueue/send only; it
does not authorize a send. Rate/refill/cooldown/retry and generated-plan dedup
remain native pending their independent executable shadow report.

## Preserve the original phases

1. Capture existing immutable facts at their old call point. Keep desired/
   planned dedup writes and encoded order unchanged. J2 event IDs/timestamps stay
   at the original record point; the plan does not require a new event or time.
2. At a native early authorization return, call
   `FeedbackAuthorizationCheck.evaluate(requirements:authorization:)`. Both sets
   are explicit. Its `.sufficient` is stage sufficiency, **not a send permit**.
   A denial must still return before a state-mutating final device filter.
3. Execute original native gates in their original order, then make the explicit
   `FeedbackProof(plan:nativeSnapshot:authorization:safety:)`. Never fill an
   unexecuted filter with `.passed`, queue a proof or reuse it across callbacks.
4. Immediately before actual dispatch, call
   `FeedbackPreflight.evaluate(plan:proof:currentScope:currentNativeSnapshot:)`.
   It checks complete plan equality, current scope, snapshot freshness, explicit
   authorization, **exact** full direction union and native safety. Missing and
   surplus directions both reject. A stage subset never shrinks the full union.
5. The actual native final gate/transport pin remains mandatory outside Core.
   Admission/defer/disconnect before calling it is not an attempted transmission.
   Invoking it and receiving a rejected pin can be an attempted transport call
   with zero physical bytes written.

For the native context operation with management+mechanism effects, an original
early mechanism-only stage may check requirements `[.mechanism]`. That grants no
management. Only that particular existing local explicit operation, after its
actual actor/mode/layer/global-touch/mechanism gates, may issue exactly
`[.management, .mechanism]` in the final proof. Generic mechanism rights, remote
claims and hardware connection source do not create a management grant. Ordinary
display's stage/final set is display. No device branch or touch switch enters Core.

Keep three domains separate:

| Domain | Existing context-command policy |
|---|---|
| Permanent simulation/GUI Mock route | Preserve old1.3 lifecycle/reset virtual commands byte-for-byte, without a new local confirmation gate. Its specific plan can narrow existing simulation rights and prove actual routing stays Mock. |
| Hardware-mode console, including fake hardware in tests | Only the existing particular local explicit command with all actor/mode/layer/global-touch/mechanism gates may obtain the full union. |
| Owned-virtual rehearsal hardware service | Source is hardware and its output vocabulary remains display-only; a virtual endpoint does not make it the simulation domain or create a context/motor command. |

Core never grants from DeviceSource or endpoint origin. Scope/native snapshot
must bind actual hardware mode and route, so a Mock proof becomes stale during a
switch to hardware even at identical virtual endpoints; the original final pin
still runs. Permanent-Mock proof is not a reusable hardware-service permit.

## Receipt and current canonical owner are separate

Create `FeedbackReceiptFact(plan:result:)` from actual native outcomes:

| Result | hasTransportAttempt | successfulSend | transmissionOutcome |
|---|---|---|---|
| notAttempted(reason) | false | false | nil |
| accepted | true | true | accepted |
| rejected(reason) | true | false | rejected(reason) |

This creates no observation or current-state candidate. An accepted old-scope
attempt stays successful even if a callback changed the canonical owner.
Recompute `FeedbackReceiptEligibility.matchesCurrentScope` at the original
bookkeeping point; `acceptedInCurrentScope` additionally requires success.
An old accepted receipt can therefore be successfulSend=true but current
eligibility=false. Current failure bookkeeping can use matchesCurrentScope
while its successfulSend remains false.

Do not retroactively recheck every physical proof fact after completion: newer
real input survives through the native revision cutoff. Do not assign an old
whole owner over new state. B keeps current echo/reference update and request
accepted hook before monitor/journal callbacks. C keeps the sent record before
its post-record scope check and original observation/receipt cutoff. Its
generation-time lastSent/command caches remain planned dedup, not success or
observation. Existing timestamps/IDs are reused at their native record point.

`FeedbackReceiptSummary` is pure nonempty/all-accepted/any-accepted aggregation.
It owns no callback, mutable collector, monitor inference, undo or retry. A
native convenience `.sent` return for an empty batch is not transport evidence.

## Required adoption evidence

Full native/candidate shadows compare complete plans/raw evidence and semantic
scope separately, stage/final authorization, native proof/freshness, actual
attempt/outcome, current eligibility and exact ordered output. Cosmetic
name/qualification/nil-versus-unknown changes must cause a full-plan mismatch
against an old proof, while preserving the native semantic current-scope rule.
Fresh matching plan/proof can still pass. Same reference cannot transfer a proof
to another payload/actor/target.

Old full suites/scenarios/golden bytes and callback safety remain mandatory.
Scheduling uses a separate test-only candidate with actual independent inputs,
no native-state/output reseeding and explicit differences; API unit tests do not
stand in for that execution or a host cutover/third-device acceptance result.

For a new device, provide independent plan/proof/receipt comparisons, all
applicable shared scenarios with explicit non-applicability reasons, original
golden bytes, lifecycle zero-send and reentry/failure cases. Under the J-close
CI layers, regression/representative comparisons and full proof must both pass
on the exact adopted commit before a switch or delivery. See
[the retained scheduler differences](scheduler-differences.md); rate/order/dedup
policy is not obtained merely by adopting this feedback block.
