# Main minimal-device integration prototype

This independent test package compiles the current parent Kit as the code under
test and acquires its own clean full-SHA SP5ff. It does not link the independent
authority process's host or older SP/Kit into the device pipeline. Production
root targets, manifest and CI are unchanged.

`CompleteScenarioRunner` is the final J5 offline composition:17 applicable rows,
35 operations and50 original assertions, with13whole physical-NA rows and only
T25's motor-continuity step NA. `tests/complete.py` runs13 real failing regression
controls and validates all reports with the unchanged stdlib/schema validators.
See [the integration boundary and source counts](../docs/j5-integration.md).
Historical checkpoint executables below remain available and preserve their
original narrower stage claims; they are not added to final scene counts.

MinimalDeviceAdapter is a separate target with only SurfaceDeviceContracts as a
dependency. It contains packet/layout/capability/codec knowledge, one knob,
one button and one brightness lamp. It cannot read fixture assertions or import
SP, host, or Conformance code. Generic composition owns the actual Kit binding,
route, scope and pending-resource values, plus actual SP sessions and action
registry. Expectations are accessed after execution through AssertionEvaluator.

The J3-only flush supports a queue that was actually canceled. A remaining plan
throws requiresJ4Dispatch; the harness does not invent a successful permit or
receipt. The wrong-route negative leaves the old generation/queue and fails the
original route/authorization assertions. The wrong-binding negative inserts an
actual enable reference into the shared index and fails both original T28
enable-binding assertions.

Hardware profile accepts_input is false for remote requests, as required by the
actual contract; physical packet decoding is a distinct adapter capability.
Unknown/read-only packet addresses emit no trusted DeviceInputEvent. No default
or sent value is seeded as a hardware observation or parameter authority.

```sh
python3 -B configs/surface_plugins_dependency.py ensure
swift build --product CheckpointRunner --build-path build/swiftpm
python3 -B tests/checkpoint.py --runner build/swiftpm/debug/CheckpointRunner --fixture ../fixtures/controller-regression-v1.json --evidence /path/to/ignored/evidence
```

Qualification evidence is explicitly absent for the hypothetical offline device.
Endpoint attachment preserves actual origin and unknown device identity without
creating qualification evidence. No real MIDI endpoint, physical output, timer
or wall-clock policy is used. Stage evidence and source inventories live in the
workspace K report; the exact current source identities are registered in each evidence ledger.

## Platform checkpoint stage

PlatformRuntime is separate caller-service composition. Immutable parameter
definitions use real SP canonicalization; actual current values/authorization/
external refusal/undo live exclusively in the independent AuthorityBridge's
production SurfaceSession. Runtime rendering reads its canonical snapshot and
actual error, without a second current-value dictionary. The active instance and
simulation/hardware source come from fixture setup and step routing, not SceneID.

PlatformCheckpointRunner executes complete original T24/T27 plus only T25's
overflow_journal operation, explicitly labeled partial with step1 unexecuted.
It does not emit an NA/skip result for that unexecuted operation. A separate
nonmotor undo auxiliary case proves real history capture then permission revoke
denial, unchanged value100, regrant and actual undo0.

T24 uses unchanged real Python Client.rpc and actual SP RemoteRegistry/
AgentRemoteBinding/AgentPlugin. The loopback helper forwards the real request to
the parent and drops its first response only after receiving the committed real
result. Raw request IDs, production journal events and transport_unknown prove
one action/no retry; a retry negative control really executes two actions.
Other negative controls discard a real rejection error, corrupt only render
projection, or record16instead of17raw events; original assertions then fail.

```sh
swift build --product PlatformCheckpointRunner --build-path build/swiftpm
python3 -B tests/platform_checkpoint.py --runner build/swiftpm/debug/PlatformCheckpointRunner --fixture ../fixtures/controller-regression-v1.json --bridge ../IntegrationAuthority/build/swiftpm/debug/AuthorityBridge --helper tests/action_transport.py --sdk-root build/seed/SurfacePlugins/clients/python --evidence /path/to/new/ignored/evidence
```

The wrapper resolves all executable/script paths before launching. Interactive
private pipes use bounded POSIX reads: a short request must receive its reply
without EOF/padding. Old fill-size FileHandle behavior was exposed by this stage,
retained as a real failing interactive regression, then fixed in both private
process ports. Darwin/Glibc imports occur only in this test I/O infrastructure;
the five production Kit targets remain unchanged and Foundation-only.

## Authority/parser/clock stage

ControlCheckpointRunner runs complete original T18/T23/T26 through the same real
providers, with6operations/6assertions. T18 withdraws the production authority's
value-write/display rights as the original fixture executors do. Both local and
remote writes are genuinely denied and keep canonical0. Any accepted software
write or requested positive feedback still raises requiresJ4Dispatch here;
there is no transport-success placeholder.

T23 records two isolated layers: removing only origin leaves all other canonical
field bytes unchanged, parses as a real ControlInput, then real hardware
validateInput rejects permission_denied; with origin the actual closed parser
rejects invalid_argument. A real localOrigins Agent is advanced to waitingApproval
on an explicitly labeled diagnostic clock. Ordinary RemoteBinding remains
waiting with permissionDenied/no journal change; a copied genuine hardware
control approves. The original untrusted witness stays unchanged when parsing
rejects. Its actual approved events, not the call's origin label, drive the
manual_authority_granted metric. Origin labels remain separate attribution.

T26 feeds actual Agent time policy and session reads with injected monotonic time;
wall jumps remain data. Negatives really bypass a remote write grant, promote a
forged actor into the real approval gate, or feed wall time and trigger real
invalid-time behavior. They fail the unchanged original assertions. This is
still checkpoint evidence, not the full17row/35step result.

## Complete execution

```sh
swift build --product CompleteScenarioRunner --build-path build/swiftpm
../build/schema-validation/bin/python -B tests/complete.py --runner build/swiftpm/debug/CompleteScenarioRunner --fixture ../fixtures/controller-regression-v1.json --bridge ../IntegrationAuthority/build/swiftpm/debug/AuthorityBridge --helper tests/action_transport.py --sdk-root build/seed/SurfacePlugins/clients/python --revision CURRENT_KIT_FULL_SHA --evidence /path/to/new/ignored/evidence
```

The wrapper requires jsonschema, as the main Kit check already does. Whole-NA
rows have empty steps per the original result contract; excluded fixture-step
counts appear only in the supplemental summary. Caller clocks, plan references
and diagnostic approval witnesses are explicitly scoped and injected. No real
hardware, default-enabled simulator or physical qualification is involved.
