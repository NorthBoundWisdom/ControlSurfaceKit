# J3 shape decisions

Status: supervisor approved implementation on 2026-11-16. The implemented API
and new-device integration rules are in [context-runtime.md](context-runtime.md).
Host shadow execution and sequential cutover are separate acceptance gates;
shape approval does not establish adoption or behavioral equivalence.

Baseline is 655f443: 77 Python and 30 Swift tests, zero failures or skips;
original evidence is in workspace `build/j-main-cont/k/`.

## Approved decisions

- ConnectionSnapshot fixes inputID, outputID, transportGeneration and isConnected
  as mandatory constructor arguments. Kit compares all of them. Generic Extra
  adds native semantic identity components, never replaces the mandatory IDs.
  One transport includes selected names and optional provenance; another does
  not. Preserve both original predicates and retain full captured provenance
  separately in strict traces and final native transport validation.
- Input epoch, mapping revision and transport generation remain separate. Kit
  does not invent an epoch or derive lifecycle identity from an observation,
  requested physical context or per-input interpretation facet.
- Bindings index physical role, opaque logical facet and InputKind to an opaque
  target reference. First match wins in original entry order. Native validators
  still reject their previously illegal configurations. Complex action payloads
  and SurfacePlugins references resolve the sole native configuration; there is
  no second parameter or action-definition store.
- ContextResourceIndex owns actual ordered IDs and captured scope. One host
  removes its native scheduler order array; the other removes its corresponding
  pending and cache-validity ID owners. Native payload dictionaries remain sole
  value owners. Do not maintain a sidecar seeded from expected native results.
- Logical invalidity immediately rejects a stale scope, while physical queue
  removal retains the old explicit clear/drain timing. Binding changes must not
  eagerly change visible queue counts when the old implementation deferred
  rejection until dispatch.
- An unordered pending inventory keeps its original sorted public facts and
  actual input-event dispatch order. Generic registration order is not imposed
  as a new mechanism-dispatch order.
- Repeated explicit context selection or attachment still performs its original
  invalidation even if the context snapshot is equal. Snapshot replacement and
  explicit resource removal are independent operations.
- Contact ownership, physical observations, context mismatch, mechanisms,
  management transactions and final send gates remain native. No optional
  device-policy disable is added to Kit. Neither a callback nor synchronous I/O
  may cause an old whole-state candidate to overwrite newer canonical state.

## Proof required after implementation

The host owners independently run old and candidate owners with the same trusted
inputs and injected identities. Every binding result, transition, captured scope,
pending/canceled ID, cache validity, observation, feedback and ordered transport
record is compared exactly. Do not ignore provenance or remap IDs after execution.
All applicable shared scenarios, full old suites and golden transport sequences
remain unchanged. The supervisor reviews each host before sequential cutover.

A new device provides only stable physical roles, logical facets, references into
its native configuration, genuine route identity/provenance, explicit lifecycle
context and protocol/safety policy. The common lookup, route transition and
resource ownership algorithms are reused without reimplementation. Kit unit
tests alone do not establish this complete new-device acceptance criterion.
