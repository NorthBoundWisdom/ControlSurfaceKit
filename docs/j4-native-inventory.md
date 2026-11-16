# J4 native plan/dispatch/receipt inventory — read-only preparation

No J4 product types, implementation, lock or CI changes are authorized by this
inventory. C's final J3 cut/CI is still pending when this is written. B source is
the pushed `ffd2d40c684d7375bff5b44043322b792ad4b063`; C behavior/line references
are the pushed `a5324f73f908146bb7b1a4310d4d8385e22488c7`. C's pending J3 cut
is consulted only for equivalent index substitutions, not as a shipped identity.
Immutable Git-object snapshots/hashes are in workspace
`build/j-main-cont/k/j4-readonly/source-manifest.json`.

## Existing immutable plan facts and source/actor distinctions

| Aspect | B native | C native | Boundary for J4 |
|---|---|---|---|
| Per-message plan | FeedbackScheduler.swift:38–43: message, SurfaceWriteOrigin, coalesced/synchronous timing | CompactPlannedProvenance in NeutralDeviceProjection.swift:154–167: caller ID, source, captured endpoint/context, ParameterWriter, at; payload stays the returned MIDIMessage | Common immutable effect facts can be shared; native encoded payload and codec remain adapter-owned. Do not require a new clock/UUID merely to create a plan. |
| Batch plan | FeedbackScheduler.swift:47–51: ordered effects/origin/timing | ConsoleModel.swift:1417–1436 captures one ordered message batch and its auth/route/mode/map facts | Preserve array order and existing batch transaction boundaries; a shared whole-batch permission rejection must not replace an old per-message partial-delivery path. |
| Connection source | DeviceSource.mock/hardware | DeviceSource simulation/hardware in provenance; MonitorEvent.Source mock/hardware/agent is a different attribution dimension | Hardware connection source does not prove human actor or local presence. |
| Actor/cause | SurfaceSession.swift:9–11: software, agent, external | ParameterWriter interface, remote, hardware, history; Model source also uses agentOutput | Do not equate B external with a trusted local operator or map a hardware connection into operator authority. Preserve native cause as a distinct captured fact. |
| Display classification | NeutralSurfaceProjection.swift:102–119 classifies B voice output as display, no mechanism side effects | NeutralDeviceProjection.swift:95–114: ring/style/button display; fader feedback mechanism | Classification is supplied by trusted device encoding knowledge, not inferred in Kit from device bytes. |
| Context command side effect | B preset/learning/device transactions remain outside this voice-feedback extraction | NeutralDeviceProjection.swift:85–87: context command management plus mechanism, affecting all native fader roles | Required directions are the explicit union. Kit must not insert a management grant just because mechanism permission exists. |
| Remote hardware vocabulary | setHardwareDisplayFeedback rejects visualization-only/unmapped/NRPN routes and requires explicit write policy | CompactHardwareProfile.swift:37–56 HardwareDisplayMessage contains only button/ring/style, no raw message/motor/context selector | These structural remote boundaries remain; shared plans must not add a remote mechanism/management constructor. |

The existing J2 EffectDescriptor already contains classification, sideEffects,
affected IDs, target/value, source/provenance/context, timing and injected time.
Its requiredDirections computes the union. Its context may include interpretation
facets/evidence for recording; it is **not automatically the semantic lifecycle
scope** that should authorize dispatch.

## B: actual ordering and accounting

| Phase | Exact native point | Meaning that must be preserved |
|---|---|---|
| Project desired display | SurfaceEngine.swift:827–843 records control last-output/presentation before returning .send | A planned projection, not transport success or physical observation. Do not move it merely to rename all output state as sent. |
| Mock echo compatibility | Engine.swift:840 may populate recentFeedback when recordFeedbackWhenGenerated; Session.swift:574 enables that only for unthrottled mock | Legacy simulation behavior remains. Hardware sets this false (Session.swift:554/574). |
| Select dispatch policy | Session.swift:1246–1267; Scheduler.swift:130–132 | Hardware observe suppresses before enqueue/send; coalescing is only hardware+enabled+destination and timing coalesced. Synchronous bypass leaves existing queued state/tokens untouched. |
| Capture queued identity | Session.swift:1257–1263 | Capture current endpoint, mapping, source and input epoch at enqueue, retaining genuinely optional legacy attribution fields. |
| Actual pre-send checks | Session.swift:1276–1315 | Capture source/control/cause/queue generation/endpoint/context; deny unpublished route handover, stale expected endpoint, stale or forbidden display auth, stale mapping; disconnected destination yields no send. The order and error/monitor semantics matter. |
| Final native transport | Session.swift:1318 device.send; CoreMIDIService.swift:215–218/649–657 forwards and checks expected generation on the management queue | Transport/device owner remains outside Kit. A generic preflight never replaces this native generation pin or reuses a pre-I/O whole-state candidate. |
| Accepted current-scope echo | Session.swift:1321–1324, Engine.swift:107–123 | Only actual send return plus still-current source/epoch/mapping/endpoint updates recentFeedback/absolute-input reference. This does not manufacture a physical observation. |
| Failed current-scope accounting | Session.swift:1328–1335 | Drop/error bookkeeping applies only to matching current scope; scheduler cooldown additionally requires original queue generation. The failure callback itself remains visible even after a late old-scope failure. |
| Request acknowledgment linearization | Session.swift:1339–1342; Scheduler.swift:76–86 | Invocation-local receipt is recorded before monitor/journal/UI callbacks. Its accepted callback may itself reenter; no child request shares the collector. |
| Synchronous display transaction | Session.swift:867–912 | Nonempty/all-sent, no accepted-callback error and still-current scope are required. Failure narrowly undoes only this request's overlay ownership; partial output means delivery_failed/output may have occurred, never certainly unexecuted/retry. |
| Batch origin scope | Scheduler.swift:57–71 | withBatch clears activeBatch to nil on completion; it deliberately does **not** restore the enclosing cause after a nested synchronous request. This unusual legacy boundary is tested behavior. |
| Canonical owner after I/O | Session.swift:1321–1342 and per-request display methods | Modify the current canonical engine/session only; do not commit a pre-I/O whole-state candidate over newly received input, feedback or a new context. |
| Lifecycle scope | Session.swift:1201–1242 | Lifecycle feedback captures connectionScopeRevision; callbacks changing it stop the rest of the batch. Cosmetic notifications do not revoke a semantically identical route. |

The monitor at Session.swift:1418–1454 increments the existing event ID, reads
its existing wall/monotonic clocks, invokes observers, bounds the monitor to300
and appends the provider journal event. It is not a reliable request-local
acknowledgment collector. Do not reintroduce bounded-monitor inference as a
replacement for the private receipt.

## C: planned dedup versus actual receipt

| Field/phase | Exact native point | What it really means |
|---|---|---|
| lastSentButtons/Rings/Styles | CompactState.swift:315–343 | Updated when a candidate message is generated, before transport. They are planned-output dedup/cache-validity state despite the name. Style changes invalidate ring cache and then return style before same-value ring redraw. |
| lastMotorCommands | State.swift:201–245 | Updated when generating a motor candidate/released reconciliation, with observed-currentness invalidated. This is planned command dedup/currentness, not actual acceptance or observation. |
| Desired values | State.swift:223–245/315–343 | Sole native desired payload stores; not a second business parameter authority and not moved into Kit. |
| Final physical recheck | State.swift:250–272; Model.swift:1525–1537 | A newer physical report/target, touch or mismatch can withhold/cancel a previously generated motor message. This final device policy must remain native and mandatory. |
| Rejected/suppressed route | Model.swift:1453–1485/1502–1537 | Handover, listen/observe, actor permission and device gates retain their exact clear/invalidate/partial-return order. |
| Actual send completion | Model.swift:1554–1565 | sendPinned returns before a .sent record with captured old route/context and actual transport time. This is the receipt point for shared successful-send evidence. |
| After record callback | Model.swift:1566–1574 | Recompute current semantic scope **after** recording; record observers can reenter. A stale old completion cannot invalidate/restore newer canonical physical facts. |
| Context assertion observation expiry | Model.swift:1551–1552/1571–1573; State.swift:123–140 | Cutoff observation/receipt revisions are captured before I/O. Accepted context command expires only facts at/before cutoff, preserving later same-route input even at equal timestamp. No sent record becomes observed context. |
| Failed actual attempt | Model.swift:1575–1593 | Old-scope error is recorded but cannot clear new state; current-scope failure marks UI failure, discards pending motor writes, invalidates transport caches and locks diagnostic tests. No automatic retry. |
| Failure before attempt | ConsoleNeutralProjection.swift:53–65 | A failed event without transportMonotonicTime is not TransmissionEvidence. Do not create a rejected transport receipt merely because an admission/path error is labeled failed. |

Supervisor direction confirmed during this inventory: preserve generation-time
caches as planned dedup/currentness; shared success accounting hooks the actual
transport receipt, without changing old dedup or output order. No blanket rename
or assertion weakening is needed to pretend the two evidence classes were equal.

## C semantic scope and mandatory native gates

ConsoleModel.swift:1437–1451 compares route generation and selected input/output
IDs, complete write authorization, requested host context, hardware/listen/observe
mode, agent motor-permission stability, native map channels and light protocol;
hardware handover invalidates it. It does not compare cosmetic endpoint name or
provenance changes. Full captured provenance is still retained by
ConsoleNeutralProjection.swift:13–22 and record paths. J4 must use the native
semantic scope for validity and the complete captured provenance for evidence,
without equating them or dropping fields from the shadow comparator.

Native gates remain in their original final-send positions:

- Whole-batch context assertion gate at Model.swift:1487–1490;
- Per-message authorization at1502–1510;
- Explicit local motor-action requirement at1512–1523;
- Fresh per-message context/touch assertion gate at1525–1533;
- Fresh desired-target/touch/mismatch filter at1534–1537;
- Actual route pin in CoreMIDIService.swift:177–197 (native queue/selected IDs and
  generation checked immediately before physical send).

The context command requires a particularly narrow permission proof. Current
native authorization has allowsMechanisms but no generic allowsManagement. The
supervisor explicitly rejects mapping that bit into arbitrary management rights.
Only a **particular existing local explicit context command**, after its current
actor/mode/layer/global-touch/mechanism gates, may receive that plan's exact
management+mechanism union. Other management and remote paths gain nothing;
remote hardware output still cannot express the command. Core must require an
explicit per-plan authorization/native-safety result, with no default true or
optional touch-policy disable.

## Hardware display service is a distinct caller, not the console send loop

The C headless hardware service's public typed plan is
CompactHardwareSurface.displayPlan (CompactHardwareSurface.swift:62–83), which
validates real contract feedback, allowed flag, connected link and known matching
hardware context. Its output enum structurally excludes motor/context commands.
HardwareMain.swift:341–352 prepares a contract-event candidate, spends request
budget before I/O, sends each typed message under activeEndpointOrigin, then
commits the event only after every transport acceptance. HardwareMIDI.swift:156–167
refreshes endpoints and checks the exact expected origin before physical output.

J4 must not accidentally narrow this typed vocabulary into raw messages or turn
its candidate journal record into success before all sends finish. This service
has a different serial execution context from the GUI callback owner; changes
need its own original full-suite/scenario evidence. B's hardware service already
uses the shared native SurfaceSession receipt path described above.

## Scheduler/dedup differences — report, not forced unification

| Concern | B native | C native | J4 implication |
|---|---|---|---|
| Timing | Explicit synchronous versus coalesced | Immediate message-array dispatch plus native safety withholding | Do not impose a generic defer deadline or token bucket on C. |
| Queue key/order | Actual J3 index keyed native control identity; replacement retains insertion position; FIFO drain | Pending motor IDs, sorted public facts and actual release-event consumption; planned display dedup caches | Do not impose FIFO registration order on motor safety behavior. |
| Rate | Scheduler.swift:162–179 token bucket; regressing supplied Date yields zero refill; drain spends tokens | No corresponding global feedback token bucket | Scheduler is shadow/difference report only unless separately proved. |
| Failure | Session.swift:515–530 requeues failed+remaining batch only under same source/epoch/mapping/endpoint/queue generation; cooldown | Current-scope failure drops pending intents/cache validity and requires explicit resync/recall | No shared automatic retry policy is inferred. |
| Repeat display | Native projection/queue merge and echo ownership | Candidate generation suppresses same payload; local style/physical redraw can explicitly invalidate dedup | Sharing actual receipt must not delay generation-time cache writes. |
| Ordered restoration | Existing hardware fullFeedback/synchronous output order and goldens | State.swift:357–374 restores styles sorted, rings sorted, then buttons sorted | Retain the existing exact byte order. |
| Source of time | B supplied Date for rate/echo and existing monotonic event time for evidence | C injected eventMonotonicClock at existing plan/dispatch/record points | Convert already captured values as needed; do not unify domains by an extra clock read. |

## Shape questions for the formal J4 decision

These are design questions, not newly declared public product types:

1. Separate immutable planned effect facts, semantic dispatch identity, and full
   captured evidence. Can one per-message shared plan carry these separately,
   retaining native encoded payload externally and preserving the original
   per-message versus batch gate boundaries?
2. Require a nonoptional result bound to this specific plan and semantic scope
   from the trusted native authorization/safety boundary. Core validates exact
   required-direction union and scope; no default grant or global policy switch.
   What minimal proof data prevents reuse for a different target/effect/actor
   while keeping all device safety predicates native at final send?
3. Preserve source independently from opaque cause/origin. B external does not
   distinguish every remote/local actor, so a new universal actor enum must not
   invent identity or grant presence. The native proof, not source, supplies the
   particular plan's authority.
4. Define actual attempt versus preflight rejection separately. A pure receipt
   helper can produce accepted/rejected transmission evidence only for a real
   attempted completion; suppression/deferred/disconnected remain decisions.
   Current-canonical bookkeeping eligibility is recomputed at each existing
   native linearization point, never cached before a reentrant observer.
5. Preserve B request-local receipt/accepted callback and overlay ownership;
   preserve C post-record scope check and observation cutoff. A shared value
   receipt helper must not move the callbacks or return a whole-state candidate
   for later assignment across I/O.
6. B has no pre-send globally unique plan ID; its neutral event ID is allocated
   at log time. C already allocates plannedIntentIDFactory/event clock at certain
   operations, then makeRecordID at record time. How can the shared plan use
   caller-supplied/derived identity without any new UUID/clock/counter call or
   changing existing golden sequences? Global uniqueness must not be presumed
   from the current J2 descriptor's merely nonempty id requirement.
7. Existing feedback target imports only ConnectionState under the strict DAG;
   actual EffectDescriptor/direction types belong to Contracts and ContextScope
   to BindingContext. Formal API review must explicitly decide whether to add
   direct dependencies on these earlier targets (still a five-target acyclic
   graph) and update checker/negative fixtures, or choose a sound existing-edge
   type arrangement. Do not silently use transitive imports or add new business
   definitions to avoid the boundary checker.

Formal implementation waits for C's J3 cut/CI and supervisor shape approval.
Subsequent B/C shadows must compare actual plan facts, required/authorized
directions, preflight decisions, attempt/outcome/evidence and exact side-effect
order, plus existing complete suites/scenario/goldens. The J5 prototypes and
original checkpoint evidence are preserved without being committed as part of
J4 product work.
