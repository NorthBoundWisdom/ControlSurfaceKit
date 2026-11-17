# J5 integration composition proposal — review draft

Historical reviewed design. Current implementation, identities, limits and full
scenario evidence are documented in [j5-integration.md](j5-integration.md).
The prospective statements below record the original design stage.

This is a design, not an implementation or acceptance report. The supervisor
approved the composition principles and selected the independent authority
bridge process; details are in
[j5-authority-bridge-design.md](j5-authority-bridge-design.md). J3 runtime is
`c6c76c8`; its CI 43903430796 passed on both platforms in 61 seconds according
to the supervisor. J4 must complete before the final J5 implementation. No
dependency, production target, lock or CI rule changes are authorized here.

## Finding: what is actually reusable

SurfacePlugins HEAD/origin `12ba0ed` is the API baseline. Its working tree has an
active owner's uncommitted input-retention work; this proposal does not depend
on that work or treat it as a reachable release.

| Existing production API | What it really provides | What it does not provide |
|---|---|---|
| SurfacePluginContracts.ParameterDefinition.clamp/normalized | Canonical finite parameter values, range/toggle/step rules | Mutable parameter authority, GUI state or authorization |
| SurfaceControlSession.validateHardwareInput/recordHardwareInput | Trusted input validation, accepted raw input journal, independent sequence, source | Physical decoding, parameter application or action execution |
| SurfaceControlSession.validateFeedback/recordFeedback | Declared display-kind/range validation, independent feedback storage/journal | Device output permission or a transport receipt |
| SurfaceControlSession.transitionHardware/reset | Source-separated link/epoch transitions, no state replay | Native context policy or parameter history |
| SurfaceControlSession.events/validateExpected | Real CAS/identity gates and event-gap detection | Caller credential authentication |
| SurfaceControlTools.parse | Closed remote request grammar; a claimed hardware-origin field is not a privilege | Parameter business mapping |
| AgentPlugin.handle and AgentRemoteBinding | Real action transitions and origin-sensitive approval | Generic parameter write authorization |
| RemoteRegistry.handle/call and RemoteEventJournal | Real plugin ownership, committed action journal, monotonic write clock | Parameter values or undo |
| Python surface_control.Client.rpc | Real HTTP/MCP transport failure becomes transport_unknown, no automatic retry | Server-side platform owner |
| Kit J3 BindingContext, ConnectionState, ContextScope, ContextResourceIndex | Actual binding lookup, lifecycle decisions and scoped resource ownership | Parameter values or device safety policy |
| Kit J4 (pending) | Intended immutable plan/permissions/pre-dispatch validity and successful-receipt accounting | Must not be replaced by a test harness's invented answers |

There is **no exported SP mutable generic parameter owner, dynamic parameter-write
authorization or undo implementation**. Creating an ideal test-only copy of
these functions and using it to make expected metrics true would not establish
the requested boundary.

## Bounded composition (process separation selected)

Create an independent, explicitly test-only `IntegrationTests/` Swift package.
Keep the existing five-target package and its no-external-dependency DAG exactly
unchanged. The integration package combines:

1. The minimal adapter, containing only packets, physical roles, capabilities and
   codec. One knob, one momentary button, one brightness lamp; no mechanism,
   touch sensor, hardware context selector, preset or style protocol. The knob
   may expose two explicit test protocol modes (absolute and relative). This is
   a declared hypothetical protocol fact, not a real-device claim.
   Business display projection may target the separate lamp, but that does not
   give the knob a native feedback role. It cannot be advertised as the same
   physical control's independent input/output-address feature. Input packets
   must genuinely carry their hardware-context tag for applicable T02; the
   current simple codec's missing tag is an implementation gap, not physical NA.
2. Actual Kit J3 and J4 runtime, owning binding lookup, route transitions,
   pending/cache identities and plan/admission/receipt decisions. The generic
   driver must call these implementations to obtain decisions, rather than seed
   their state from the expected result or native shadow answer.
3. Actual SP control sessions and action registry/plugins. They own their real
   contract journals, accepted raw inputs, source/identity checks, clocks and
   actions. Two AgentRemoteBinding instances represent the fixture's two opaque
   action references; counts are read from actual committed registry events.
4. A **test-only external authority port backed by existing production
   BCRSurfaceDomain.SurfaceSession**, with empty native control assignments.
   This is the existing caller-owned platform service, not another device
   adapter. Use its actual `configureParameterWrites`,
   `setAuthorizedParameter(s)`, `parameterAuthority`, `undo`/`redo` and
   `engine.value` APIs. Its engine is the only business parameter value store.
   No BCR input or display mapping participates. A no-I/O SurfaceDevice fixture
   rejects unexpected sends; the authority session remains in mock source and
   is never reported as hardware evidence. The minimal adapter does not import
   any host module or know that this provider is being used.

The generic bridge first uses SP ParameterDefinition.clamp, then submits that
canonical proposal to the real authority. It stores **no second parameter
dictionary**. A configured external rejection is a real callback result through
SurfaceSession's existing rejection path, and the renderer reads the canonical
authority value plus the thrown error. It does not assign the fixture's expected
rendered value. An auxiliary nonmotor undo/revocation test invokes actual history
and dynamic authorization even though the motor-specific T21 is physically NA.

This reuses production code without moving or duplicating a business engine into
Kit or Conformance. It demonstrates a new adapter using an existing caller
runtime. It does not claim that the platform runtime's final neutral repository
placement has already been solved: that implementation remains in its host
repository, outside Kit's production dependency graph.

## Dependency/materialization and CI execution still pending

The selected authority-bridge executable links against the managed host package
and communicates over bounded stdin/stdout frames. The main integration package
depends only on the current under-test Kit and separately managed SP. The bridge
retains its own original host SP/Kit locks; those identities are registered
separately and its Kit does not stand in for the current device pipeline. Thus
new Kit CI need not wait for a host to pin the new Kit. Neither production
repository gains a dependency on the other. Acquisition happens before SwiftPM;
manifest evaluation only verifies. See the bridge design for the exact graph,
public APIs, source management and protocol proposed for execution authorization.

Recommended CI: run this integration package as a separately named test-only
job on macOS and Linux, sharing keyed SwiftPM caches and restoring source mtimes
once. Report one complete check budget from workflow created to final update;
no cold/queue exemption. Existing checks remain unchanged. No repeated host
full build, GUI, HTTP provider build or per-scenario process is needed: the
Foundation/domain authority and all Swift scenarios run once in one process.
The single response-loss experiment uses a shared loopback fixture and actual
Python SDK transport; no fixed sleep, reverse DNS or retry.

Estimated implementation size, **not measured evidence**: adapter about 40–75
physical lines, reusable composition/metrics/fixture-driver about 500–800 lines,
authority wrapper about 80–130 lines, dependency/CI checks about 100–180 lines,
and a small framing/drop-response helper if needed. Source and test counts must
be measured separately after implementation. These are test plumbing and
composition; no independent clamp, journal, authorization, undo, action or
route/plan algorithm is permitted in them.

## Full 30-scenario applicability matrix

`Applicable` means execute the unmodified fixture operations and every applicable
assertion. A missing runtime is not NA. `Physical NA` identifies a real absent
device/protocol feature. Original fixture SHA remains
`546fbc2a6f1d20f9e116a91558f4dd67891bfaba797b9778e85d975fe4cd3384`.

| ID | Minimal device applicability | Actual common provider and implementation requirement |
|---|---|---|
| T01 | Applicable | Two independent device scopes; Kit lookup, SP hardware input journal, sole production authority per fixture instance; J4 display output. Inspect real canonical values and output records. |
| T02 | Applicable | Decode the real hypothetical packet's explicit hardware-context tag, retain physical role identity, and keep actual reported context2 distinct from software page2. Codec/tag support is pending, not NA; UI page selection must not fabricate the hardware tag. |
| T03 | Physical NA: no same-control independent I/O addresses | The knob is input-only and a different physical lamp is output-only. Distinct addresses on those two roles do not satisfy independent_io_addresses for one physical control; do not advertise that feature. |
| T04 | Applicable in absolute mode | Codec saturates the hypothetical physical position; SP canonicalization and real authority apply the result. No relative event is fabricated. |
| T05 | Applicable in relative mode | Twenty real decoded deltas, Kit binding lookup and twenty actual authority commits/journal records. No coalescing of input; sum is derived from the recorded deltas. |
| T06 | Applicable | SP/Kit bound press invokes actual AgentPlugin once. Page replacement changes lookup; release remains a release and causes no invocation of either action. Count committed registry events. |
| T07 | Physical NA: no motor | No motor plan vocabulary is declared. |
| T08 | Physical NA: no motor or contact sensor | No invented contact batch. |
| T09 | Physical NA: no motor | Generic remote/display authorization is still tested in T18; do not claim this proves motor gates. |
| T10 | Physical NA: no motor or native hardware context | No fabricated layer-mismatch model. |
| T11 | Physical NA: no motor or contact sensor | Connection loss is still exercised in T12. |
| T12 | Applicable | Actual Kit ConnectionState transition, captured ContextScope rejection and resource invalidation; J4 queued display cannot dispatch under the new generation. Real recorded output count remains zero. |
| T13 | Physical NA: no global context movement | No management effect can be expressed by this adapter. |
| T14 | Physical NA: lamp has brightness only, no display-style protocol | Do not add a style feature merely to match this fixture. Brightness projection is tested elsewhere. |
| T15 | Applicable | Actual J4 dispatch attempt/receipt reducer with a rejecting in-memory transport; no successful-send record or sent cache update on rejection. |
| T16 | Physical NA: no motor | No physical position observation is available; neutral observation tests remain independent. |
| T17 | Physical NA: no motor/physical motor echo | Input/display independence is nevertheless tested by T03. |
| T18 | Applicable | GUI and remote submit to the same real production authority gate; display permission is enforced by actual J4 direction admission at both paths. Derive equality from the two real decisions; zero output from actual transport records. |
| T19 | Physical NA: no preset transaction protocol | Do not introduce test-only preset transactions. |
| T20 | Physical NA: no hardware restore transaction/profile persistence | Software-page and session epoch replacement do not manufacture this hardware feature. |
| T21 | Physical NA for the fixture: it explicitly requires motor | Its generic history/authorization question remains real. Add an auxiliary no-motor undo/revoked-permission test using production SurfaceSession.undo, not a fake undo stack. No generic undo exists in SP or Kit. |
| T22 | Applicable | Separate real SP simulation session feedback/reset, shared real authority port identities and Kit hardware scope. Hardware canonical value and output records must remain unchanged; no reset fanout. |
| T23 | Applicable | Real closed request parser/RemoteArguments rejects forged origin before actual Agent action; hardware SurfaceControlSession also rejects remote input. No remote request can construct the trusted hardware-input API. |
| T24 | Applicable | Actual RemoteRegistry/AgentRemoteBinding mutation once; loopback framing deliberately drops only its response. Actual Client.rpc raises transport_unknown and does not retry. Reconcile actual plugin/journal state; replay count is actual upstream invocation count. |
| T25 | Applicable journal step; physical NA contact-loss step | Actual SP bounded event journal overflows capacity16 at17 events and reports event_gap. The motor-continuity step is separately NA because no motor/contact exists; never mark the applicable journal step NA. |
| T26 | Applicable | Inject monotonic time into actual SP sessions/registry and J4 timing. Wall time is only a fixture trace field and never supplied as policy time. Compare actual clock/event/dispatch outcomes. |
| T27 | Applicable; blocks a SP+Kit-only ideal harness | Actual production authority callback rejects and supplies actual10; its existing correction/error path executes. Renderer reads authority and error. No fixture assignment directly sets rendered_value to10. |
| T28 | Applicable | Codec exposes no pedal input and the lamp is display-only. Actual Kit binding inventory has no enable reference and decoding emits no trusted input for unknown/read-only addresses; the real action registry remains unchanged. Hardware profile accepts_input=false is the remote request prohibition, not a substitute for trusted physical decoding. |
| T29 | Applicable | Actual Kit binding replacement changes software page/target. Native hardware context stays the adapter's single context; J4 produces a valid display plan and no management/context-select packet. |
| T30 | Applicable | Genuine captured EndpointProvenance flows through the actual Kit route/plan and records; same display name never derives a device ID or qualification. Qualification is an explicit test-provider capability fact, never inferred from transport. |

Expected applicability is 16 complete applicable scenarios plus the applicable
journal portion of T25, 13 whole physical-NA scenarios, and one motor-only step
NA in T25. These are planning classifications, not passing results. The scenario
file itself is not edited; the result format must preserve each step's status and
specific physical reason. Any validator disagreement must be resolved from the
original schema, never by omitting the scenario or weakening a result assertion.
Counting the unchanged fixture gives 35 applicable operations across those17
rows, not7operations in a selectively chosen three-scenario subset.
Supervisor's explicit whole-scenario physical-NA list is T03,T07,T08,T09,T10,
T11,T13,T14,T16,T17,T19,T20,T21. T25 loses only its motor-continuity step. This
corrects an earlier draft that swapped T02 and T03 while coincidentally retaining
the same counts; counts alone did not establish the feature reasoning.

## Proof that this is reuse rather than a fixture oracle

- For every applicable step emit actual before/after snapshots, Kit transition
  facts, exact resource inventories, effect plans/admission and transport result,
  plus SP and authority journal cursors. Assertions come only from the existing
  ScenarioAssertions engine and original fixture data.
- Run meaningful negative controls in isolated test values: old route generation
  must reject T12; wrong binding must fail T01/T06; an accepted receipt substituted
  for rejection must fail T15; forged origin must fail T23; a deliberate test
  transport second invocation must fail T24; corrupt canonical render projection
  must fail T27. Do not mutate a production fixture or relax comparison.
- Adapter code cannot import SP, authority or Conformance modules. The generic
  fixture driver cannot read expected values while executing operations; it only
  reads expectations afterward through the shared assertion evaluator.
- Prove one sole business-value owner: all rendered/feedback values read the
  production authority; SP accepted raw input observations remain explicitly raw
  evidence and are never treated as that business authority.
- Track exact adapter device-knowledge lines separately from generic composition,
  verify the same runtime with both protocol modes, and preserve all 30 scenario
  rows including their explicit physical applicability decisions.

## X-Touch One update after J3/J4

The existing paper exercise remains valid and unqualified. Add stable physical
roles plus opaque logical facets to BindingContext, with references into the
caller's existing configuration; explicit input/output IDs and transport
generation to ConnectionSnapshot; actual pending/cache IDs to the shared index;
and J4 effect direction/side-effect/permission/receipt plumbing. Physical contact,
mode transitions, possible mechanism side effects and final send safety remain
its own adapter work. No addresses, acknowledgments or motor behavior can be
inferred from the minimal hypothetical protocol or from another device.

## Supervisor decisions and remaining authorization

1. Composition principles accepted; independent test-only authority process
   selected. Both production package DAGs remain unchanged. There is no direct
   main Integration→host SwiftPM link.
2. Minimal hypothetical protocol modes/physical applicability accepted in
   principle; original expectations and all runtime-dependent applicable
   scenarios remain mandatory. Missing implementation is never physical NA.
3. Formal implementation scope, managed locks and CI placement/cache/budget await
   supervisor authorization after J4 API approval. No new CI exception, hidden
   old Kit runtime or silent cross-repository source path is permitted.
4. No new public host API/product appears necessary from static review. If
   compilation reveals a real public-API gap, report it before any host change;
   a copied test engine is not an acceptable workaround.
