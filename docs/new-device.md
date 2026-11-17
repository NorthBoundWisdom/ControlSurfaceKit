# Adapter integration checklist

1. Give each physical actuation role a stable element ID across group/layer/bank
   facets; turning and pressing may be separate roles. Preserve actual physical
   positions, not logical rows that merely encode groups. Keep endpoint,
   connection generation and context identities explicit. Legacy logical
   control IDs remain binding/display targets, mapped by the adapter.
2. Declare inputs, displays, effect directions and the side-effect union. Under
   one actual protocol mode, aggregate each physical role's supported kinds
   across facets; groups, layers and software banks are not protocol modes.
   Effect targets may be facet-qualified; affected elements are physical roles.
   Do not infer hardware identity from there being only one connection.
3. Decode only device facts to neutral input and observation values; encode only
   approved effects. Context preserves evidenced interpretation and hardware
   context separately; UI selection cannot fill an unknown hardware group/layer.
   Observation attributes distinguish absolute input position from relative
   delta; a delta, estimate, default or sent value is not position evidence.
   The host owns business values, permissions and transactions.
4. Supply device-specific touch, layer, motion, echo, preset and endpoint policies.
   Successful transport acceptance is only sent evidence, never observation.
5. Drive context/connection reducers with caller-supplied events and time. On a
   new generation discard old pending work, caches and evidence; never replay.
6. Run all applicable shared scenarios through the adapter and record explicit
   physical reasons for non-applicability. Compare every step before adoption.
7. Add byte-level protocol tests, failure/reentry tests and safety evidence. A
   new adapter may use existing host infrastructure without adding kernel device
   branches. Hardware qualification is a separate, user-arranged activity.

J-2 supplies neutral contracts, the unchanged scenario format and a minimal
stateless test adapter. See new-device-example.md for the evidence limits.
J-3 implements binding lookup, semantic scope, connection transitions and scoped
resource ownership; see [context integration](context-runtime.md). J-4 adds
complete immutable plans, explicit stage/full native proof and actual receipt
facts; see [feedback integration](feedback-runtime.md). Their implementation in
the library does not by itself prove a host's shadow/cutover or final J5 matrix.
The feedback checklist there specifies the adapter's payload, scope, raw evidence,
fresh safety results, sender and exact-commit adoption proof. Scheduling stays
native; see [accepted differences and the next extraction boundary](scheduler-differences.md).

These identity/facet rules apply to J-2 neutral integration. Host adoption and
exact pins are tracked in the supervisor's workspace review. They do not rename
published control IDs or change legacy bindings.
