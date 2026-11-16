# Adapter integration checklist

1. Give every physical element, endpoint, connection generation and context an
   explicit stable identity. Unknown device observations remain unknown.
2. Declare inputs, displays, effect directions and the union of side effects.
   Do not infer hardware identity from there being only one connection.
3. Decode only device facts to neutral input and observation values; encode only
   approved effects. The host owns business values, permissions and transactions.
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
Binding/connection reducer adoption follows in J-3, and is not yet implemented.
