# Minimal-device integration

The independent `IntegrationTests` package executes the unchanged 30-row fixture
through current Kit, actual SurfacePlugins APIs and the independently built
production authority bridge. The local complete run has 17 passing scenarios,
35 passing applicable operations and 50 original assertions. Thirteen complete
scenarios lack physical features; only T25's second, motor-continuity operation
is step-level NA. These are offline fake-device results, not physical qualification.

The canonical report uses the original schema: whole-scenario NA has no step
records; the one step-level NA has empty observations/effects. The supplemental
summary separately counts 43 original fixture steps excluded for physical
features. None of those 43 operations is claimed executed. Fixture SHA256 stays
`546fbc2a6f1d20f9e116a91558f4dd67891bfaba797b9778e85d975fe4cd3384`.

## Executed providers and identities

| Graph | Exact source | Responsibility |
|---|---|---|
| Main integration | Current parent Kit source/commit; separately managed SP `5ffbac79699505a76298172e8e6f28f7de3df88b` | Actual binding/connection/resource reducers, immutable plans/proof/preflight/receipt eligibility, SP canonicalization/control journal/parser/registry/Agent |
| Independent AuthorityBridge | Managed BCR `36692f1422b0c3952f9048847a0bafd65421bc72`; its original SP `12ba0edbc1f2c46eea5311f9b8f982d563c55b75` and Kit `655f443abb2a3977e6c30deb1fe6d20a97d47191` | Existing production SurfaceSession parameter value, write permission, external-authority refusal/correction and history owner |

The bridge uses empty assignments, permanent Mock source, output-observe and
lifecycle-disabled construction, an actual throwing no-I/O device, injected
operation times/UUID factory and counters retained through destruction. Its old
Kit is never the tested device pipeline. No host source, lock or public API was
changed. There is no production Kit→SP/host dependency or sixth production target.

The sole business-value dictionary is production SurfaceSession's engine in the
bridge. The main runtime only reads canonical snapshots and submits canonical
proposals; SP ParameterDefinition performs real clamp rules. Read-only IPC logs,
immutable parameter metadata and the configured external callback reply are not
another current parameter store. Actual dynamic authority context is returned by
production `parameterWriteContext`, captured in scope, and reread before dispatch.
There is one `ControlJournalOwner` containing the actual main SP control session:
raw input and successful feedback both record into that owner, not parallel
journals. The external bridge's own production history is intentionally separate.

## Device and caller responsibilities

| Source | Physical lines | What changes for another device |
|---|---:|---|
| `MinimalDeviceAdapter.swift` | 77 | Packet variants/addresses, two declared protocol modes, physical knob/button/lamp capabilities, stateless decode/encode and real context reports |
| `MinimalPhysicalModel.swift` | 32 | Reported absolute position/context evidence and physical-turn saturation; no business values |
| `MinimalDisplayBackend.swift` | 15 | Offline native receiver for the hypothetical brightness protocol; accepted lamp state is not input/observation |
| `MinimalFixtureWiring.swift` | 67 | Explicit device/fixture assembly: logical axis→physical knob, logical display→physical lamp, mode-specific roles/packets and SP logical profile/opaque binding projection |

Thus device protocol/physical/receiver code is **124 lines**, with **67 additional
assembly lines**, or **191 counted lines together**. This is not the earlier
109-line checkpoint claim. The entire integration runtime, driver, authority,
ports and historical checkpoint runners are also reported separately by source
inventory; they are not hidden in that 191-line figure.

Logical `axis`, `button`, `meter`, pages, p1/p2 and fire1/fire2 belong to the frozen
consumer fixture. Their target references are read from fixture setup; they are
not device business defaults. The complete caller runtime still statically
selects this test adapter/model/receiver type and its explicit wiring. A new
device supplies/replaces those device types and wiring declarations; it does not
replace Kit's lookup, scope, preflight or receipt algorithms, nor the external
parameter/authorization/history or SP journal/action providers. This exercise
does not assert that those platform services have already moved to a neutral
production repository: production parameter authority remains in the host.

The input-only physical knob has `displays=[]`; the separate lamp is the sole
physical output. A fixture display targeting logical axis is projected to lamp;
full plan/receipt traces retain `affected_elements=[lamp]` and `lamp.output`.
This does not make same-physical-control `independent_io_addresses` available.
No motor, touch, context-moving management output, style, preset or persistence
protocol is present. A genuine context tag/report is supported; a software page
change never manufactures one.

SP's published logical ControlProfile requires every control to have input_kind
and its corresponding input capability, even accepts_input=false. The final
profile therefore contains only the actual axis mode and button. It omits a
fake absolute meter input; unknown/read-only meter packets still run through the
actual codec and produce no input/binding. Relative mode declares input.relative
and input.button, without input.absolute. Pure display is associated with a
logical input's feedback declaration and the physical lamp; this contract shape
is a recorded boundary, not a new SP API or a changed published contract.

## Execution and evidence

Each operation decodes its actual packet, captures direction-specific input
provenance, uses actual binding lookup, commits through the sole production
owner, and records raw input in SP. Independent output construction creates a
complete immutable Kit plan with captured endpoint/name/qualification/nullable
attribution. The explicit fresh proof uses real current authority rights and
native route/codec/owner facts. Only permitted plans reach the actual offline
receiver. Accepted receipts can update sent-cache identity and SP feedback;
rejection cannot. Output acceptance never fabricates operator input, observed
position, hardware context or a new parameter value.

Raw evidence includes each packet address/value/context, decoded event source,
endpoint/generation/context/time, device observations, actual connection snapshot
and separate native descriptor, full plan/proof/current snapshots, every attempt
and receipt, canonical owner snapshots, actual action journals and no-I/O totals.
Endpoint attachment itself performs no input/send. An explicitly separate
auxiliary operation then decodes a packet and sends display, verifying raw
attachment provenance through connection→event→plan→receipt. Qualification is
read from actual native state; unknown remains nil. No display name derives it.

T24 uses actual production SP Registry/Agent and unchanged Python Client.rpc. The
loopback helper drops one response after the production mutation commits; the
actual SDK reports transport_unknown and does not retry. T23 rejects forged
origin through the closed parser; removing only that field parses successfully
then real hardware input validation denies it. Separate real localOrigins Agent
controls distinguish ordinary remote denial from true local hardware approval.
T26 supplies injected monotonic times to actual SP policy and retains wall jumps
as data. The nonmotor history auxiliary captures a real undo group, revokes real
history permission, observes denial/value100/retained stack, then regrants and
actually undoes to0. T21 remains physically motor-only NA.

The complete wrapper runs 13 real regression controls: wrong route; wrong input
endpoint; changed origin; invented qualification; rejection misclassified as
accepted; automatic enable binding; SDK retry; dropped actual error; wrong render
projection; journal truncation; remote write bypass; forged hardware actor; and
wall time used for policy. Each executes real altered operations and exits1 with
an unchanged original assertion/error path failing. Original fixture and schema
remain byte-identical. Both the original stdlib report validator and JSONSchema
validate every result, including negative result structure. Old checkpoints and
their original logs remain separate historical evidence, not additional full
scenario counts.

The early `j5-complete/third` run had 17/35 green but lacked honest directional
input and provenance witnesses. It is retained as an intermediate result with
that limitation. Final evidence follows the supervisor's concentrated review
fixes and includes their three dedicated negative controls. The real SP
invalid_profile red exposed the fake meter capability and is preserved before
the corrected current-mode profile's green run.

## Physical applicability

| Rows | Missing physical/protocol feature |
|---|---|
| T03 | Same physical control with independent input/output addresses; knob and lamp are different controls |
| T07, T08, T09, T10, T11, T16, T17, T21 | Motor-dependent cases; touch/echo/layer safety is not invented for a device without the mechanism |
| T13 | Global hardware context movement/management output |
| T14 | Display-style protocol; lamp supports brightness only |
| T19, T20 | Preset transaction/hardware restore persistence |
| T25 step1 only | Motor/contact continuity; step0 journal overflow is executed |

All other rows T01,T02,T04,T05,T06,T12,T15,T18,T22,T23,T24,T25,T26,T27,T28,T29,T30
execute their original applicable operations and assertions. A missing platform
implementation is never classified as a physical feature absence.
