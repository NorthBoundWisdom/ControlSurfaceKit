# J5 independent authority bridge — design only

Historical reviewed design. Current implementation, identities, limits and full
scenario evidence are documented in [j5-integration.md](j5-integration.md).
The prospective statements below record the original design stage.

The supervisor selected an independent test-only process after reviewing
[the full 30-scenario proposal](j5-integration-proposal.md). This document
refines that decision; no package, dependency, CI or implementation is added yet.
J4 shape and implementation remain the next production work after J3 adoption.

## Two independently resolved package graphs

```text
IntegrationTests package (under test)
  ├── current checked-out ControlSurfaceKit package (the code under test)
  └── managed full-SHA SurfacePlugins
        SurfaceControlSession / AgentPlugin / RemoteRegistry / SDK
  │
  └── bounded stdin/stdout data port
        AuthorityBridge package (test-only external platform service)
          └── managed full-SHA BCR2000Dev:BCRSurfaceDomain product
                ├── its existing locked SurfacePlugins
                └── its existing locked ControlSurfaceKit
```

The graphs are separate processes and separate SwiftPM build paths. The bridge
never links the under-test Integration executable and exports no Swift types
across the process boundary. Its older Kit is not claimed as the device runtime
being tested. New Kit commits therefore do not need a host lock update before
their own CI can exercise the current device pipeline.

The main test package references its own parent checkout as the code under test,
not as an externally acquired library. Its external SP source is independently
locked/managed. The production five-target manifest, DAG, source boundary checker
and absence of production SP/host dependencies remain unchanged.

Static public-API review used reachable BCR commit
`36692f1422b0c3952f9048847a0bafd65421bc72`. Its original locks are SP
`12ba0edbc1f2c46eea5311f9b8f982d563c55b75` and Kit
`655f443abb2a3977e6c30deb1fe6d20a97d47191`. The active BCR working tree is
owned by another developer and was not compiled or changed for this design.
The final bridge lock may use a later reviewed, reachable commit, with its actual
transitive locks recorded. The main under-test Kit identity is always separate.

## Existing public authority API is sufficient

The BCR package already exports the `BCRSurfaceDomain` library. A bridge target
needs no new host product, exported internal type or host source edit. With
`import Foundation` and `import BCRSurfaceDomain`, contextually inferred argument
types construct definitions, IDs, policy and injected HostTime through their
public initializers. The uncommitted prototype has now compiled successfully
against these public APIs; no host product/API/source change was needed. This
does not establish the complete J5 scenario result or Linux validation.

| Bridge operation | Existing public API used |
|---|---|
| Create sole parameter owner | SurfaceConfiguration(name:parameters:assignments:), ParameterDefinition, SurfaceSession initializer |
| Authorize both GUI/remote/history identities | configureParameterWrites(allowsWrite:allowsDisplay:identities:parameters:), authorizeParameterWrite |
| Apply canonical proposal | setAuthorizedParameter(to:identity:) or setAuthorizedParameters(identity:) |
| External authority rejection/correction | parameterAuthority callback returning .accept or .reject(actual:reason:) |
| Render canonical value and public history facts | parameterSnapshot().values, engine.value(of:), canUndo, canRedo |
| Real undo/redo and group boundaries | endParameterHistoryGroup(), undo(), redo() |
| Preserve real write-origin attribution | withWriteOrigin(.software/.agent) |
| Prove no output | Source .mock, empty assignment sets, actual monitor output inventory, rejecting SurfaceDevice send method |

Session construction supplies:

- Empty assignments and pages, no plugin action bindings and no output-enable
  parameter. Definitions contain only fixture parameter metadata.
- A SurfaceDevice fixture with a disconnected snapshot and a `send` implementation
  that records an attempted call and throws. It never enumerates or connects.
- `.observe` hardware output and `hardwareLifecycleFeedback: false`, even though
  the session is additionally fixed at `.mock`. There is no protocol operation
  which selects hardware or invokes control/device configuration.
- A manual numeric clock through `now: { Date(timeIntervalSinceReferenceDate: clock) }`
  and `historyTime: .init(now: { clock }, sleep: { _ in ...fail... })`.
  The finite sleep closure is an assertion failure if called, not a new timer.
- Injected deterministic generation strings and persistence closures that fail
  if called. No real time, randomness, filesystem persistence or device output
  is needed for parameter authority operations.

Before and after every command, assert source remains `.mock`, all assignment
sets remain empty, hardware send attempts are zero, and actual monitor output
events are zero. A dedicated observer counts actual output callbacks from the
moment of session creation; do not infer zero from a bounded monitor's current
contents after older events might have been evicted. A mock projection or accidental assignment must not quietly
produce hidden internal device sends. An invariant failure is fatal to the
bridge and integration run, not an ignored diagnostic.

The only business-value dictionary is inside the real SurfaceSession engine.
The bridge may hold sessions keyed by instance ID, immutable definitions and
one configured external callback result per parameter. It does not hold a
second current/desired/rendered parameter dictionary or an undo stack.
External rejection data is an injected response, not cached parameter authority.
The parent renderer reads returned canonical snapshots and actual thrown errors.

## Bounded private JSON-lines protocol

This is a subprocess test port, not a network service or consumer contract.
It uses inherited stdin/stdout, requires no token and accepts no credentials.
Stdout contains protocol frames only; diagnostics go to stderr.

Every request has exact common fields:

```json
{"version":1,"id":1,"op":"snapshot","instance":"primary","at":0.1,"arguments":{}}
```

The monotonically increasing request ID identifies one request/one response; it
is not a business authorization token. The parent issues no retry after a lost
or invalid response. The `at` value is finite injected time. Actual SP/registry
policy in the main process owns monotonic-time decisions; the bridge must not
add a competing test-only time-policy engine.

| op | Exact operation arguments | Execution |
|---|---|---|
| create | definitions:[{id,minimum,maximum,initial,step?}] | Construct a new real authority session; duplicate live instance rejected |
| permissions | allows_write,allows_display,identities,parameters? | Configure the real current permission context; no copied authorization predicate |
| authority_reply | parameter,accepted,actual_value?,reason? | Install/replace one fixture callback result; false must use actual value+reason; true means .accept |
| write | parameter,canonical_value,identity | Call real authorized write; no local value assignment |
| snapshot | empty | Read actual canonical snapshot/history/source/invariant facts |
| end_history_group | empty | Call real production group boundary |
| undo / redo | empty | Call actual history operation with current authorization |
| destroy | empty | Drop this isolated authority instance, with no device shutdown command |
| finish | empty | Return final invariant totals, then exit successfully |

Responses contain matching version/id/instance, `ok`, either a bounded typed
error or operation result, and a snapshot of actual values plus `can_undo`,
`can_redo`, current source/context and invariant counters. Returned errors preserve
the production ParameterWriteFailure category and bounded reason where present.
A rejected `write` response still includes the actual corrected snapshot from
the production rejection path. The parent cannot infer acceptance from merely
receiving a canonical value.

Framing limits proposed for implementation: 64KiB per input/output line, 128-byte
IDs, 32 parameter definitions per instance, 8 simultaneous instances and 2048
request frames per process. Bound cumulative retained diagnostics as well.
Overlong/incomplete UTF-8/JSON, unknown fields/op, duplicate request ID, nonfinite
number, wrong scalar type, excessive count or unexpected EOF fails visibly
without applying the operation. The framing reader caps bytes before decoding;
`readLine()` followed by a size check would not bound allocation. No unbounded
whole-stdin read or generic dynamic method invocation.

The request decoder is transport validation only. It must not duplicate clamp,
permission, history, action, source or journal policy. The test driver never
reads a scenario expectation while executing its operation.

## Managed source acquisition

Two externally locked roots are needed: main SP and bridge BCR. Each uses HTTPS
remote plus full40-character revision, a manager-owned marker, an owned seed
directory, ownership/revision/dirty verification and atomic materialization.

1. Validate each lock and refuse symlink/unowned/dirty cache paths. Do not reset,
   clean, overwrite or stash an unexpected source.
2. Fetch/clone the precise object into an owned temporary directory. A local
   developer checkout may be an acquisition source only; no dirty working-tree
   content is copied or compiled. The managed checkout must be clean at the
   locked revision and retain the intended remote identity.
3. Atomically install only after all checks. Reuse an existing clean exact seed;
   fail visibly on wrong revision/origin/ownership instead of silently repairing
   someone else's checkout.
4. In the owned BCR seed, invoke that committed repository's original SP/Kit
   `ensure` entry points. Do not alter its locks to match the main process. Its
   manifest's existing verify-only checks must pass before Bridge compilation.
5. Build the AuthorityBridge product against the BCRSurfaceDomain product only,
   with `BCR_PORTABLE_BUILD=1` where the original manifest selects its portable
   slice. Inspect the resolved reachable target graph: no CoreMIDI driver, GUI,
   native HTTP host or network-provider product is linked into the bridge.
6. Separately build the main Integration executable/tests against the under-test
   parent Kit and managed main SP. Never add the BCR seed to this package graph.

The D9 manager implementation should follow the already reviewed stdlib/Git
mechanism. If copied/adapted, record source blob/license and retain its ownership,
dirty-source, exact-revision, atomicity and failure tests; do not import the host
FreeCM strategy. A seed source path override changes acquisition only.

Record one ledger with parent Kit HEAD + dirty state and Source blobs, main SP
remote/revision, bridge source remote/revision, both original bridge dependency
locks, exact build commands/toolchain, executable hashes and process arguments.
The parent development run may be dirty only in its owned under-test files;
final committed CI evidence must identify the exact commit. All external sources
must be clean and pinned in either case. No credential or token enters the ledger.

## T24 uses actual actions and actual SDK transport

The authority bridge does not execute Agent actions or fake response-loss counts.
The main Integration process owns the actual production RemoteRegistry with
AgentRemoteBinding/AgentPlugin. A small generic loopback framing helper forwards
the actual MCP `tools/call` to that process. It waits for a real committed response
before deliberately closing that one response connection. Thus loss happens
after the action really happened.

The unchanged real Python SDK `Client.rpc` makes one call. Its public generic
RPC method can invoke `surface_agent_primary`; `Client.call` is control-contract
name-restricted and must not be patched to accept a plugin tool. The client must
raise actual `transport_unknown`. Reconciliation reads actual registry/plugin
state and its production journal. Capture actual upstream request IDs and count;
no second call/retry is made by the SDK or helper. A deliberate test-only second
invocation is a negative control and must fail the original one-action assertion.

The fixture's transport-loss helper is one bounded process/server per complete
suite, not one process per step. Use literal loopback binding without reverse
DNS. Close the selected connection immediately after committed response receipt;
no sleep or widened readiness deadline. No real MIDI endpoint is created.

## Negative controls and measurements

In addition to all17applicable fixture rows/35operations and explicit physical
NA rows/steps from the parent proposal:

- Protocol tests reject oversized/unknown/duplicate/stale frames without changing
  a canonical snapshot, and prove stderr cannot corrupt stdout framing.
- No-I/O tests intentionally attempt an authority-side assignment or forbidden
  device operation in isolated test values; the invariant checker must make the
  run fail rather than silently count a successful minimal-device send.
- Actual write/reject/history tests show value100 accepted, a later authority
  rejection corrects to10 with a visible error, and permission revoked after
  capture prevents real nonmotor undo without changing the canonical value.
  No expected-value assignment or test-only history stack is permitted.
- A deliberately stale captured Kit scope fails real J3/J4 admission; a wrong
  binding makes original parameter/action assertions fail; successful receipt
  substituted for a rejected receipt makes the sent-evidence assertion fail.
- A transport second invocation fails T24, and a corrupted render projection
  fails T27. These isolated negative controls never edit the shared fixture.

Measure adapter device knowledge, generic pipeline composition, authority bridge,
framing helper, validators and tests as separate physical-line inventories. Also
record actual per-target compile count, whole-suite runtime, fixture assertions
checked, scenario/step pass/fail/physical-NA counts, authority request ledger and
all zero-I/O invariant totals. Estimates are not substituted for those outputs.

CI placement remains for the supervisor's J4/J5 execution authorization. The two
build paths can prepare in parallel where independent, then tests run once with
their known executable paths. Cache keys include toolchain and actual source
identities; do not build a whole host GUI/service distribution. Existing root
checks remain mandatory. The entire workflow, including cold setup, queue and
post steps, stays within300seconds; exceeding it is a structural failure.
