# Strict raw JSON and parsed scheduler input

This is test support in SurfaceDeviceConformance. Production adapters still
cannot depend on this target. Candidate scheduling, encoding, comparison and the
four production runtime targets are unchanged.

## Three separate operations

```swift
let payload = try SchedulerTraceCodec.decodePayload(originalData)
let envelope = try SchedulerTraceCodec.decodeInput(payload: payload)
```

`decodePayload(Data)` performs complete strict raw JSON validation and returns
the value from that same parse. It checks UTF8, JSON syntax/string escapes,
decoded duplicate keys (including canonically equivalent Swift String keys),
1MiB size, depth128, complete scalar grammar, finite representable numbers and
trailing bytes. Array order, nulls, boolean/number distinction and string UTF8
are retained. Number and string tokens use Foundation JSONDecoder directly;
there is no NSNumber conversion, second fallback scan, ignored native field or
separately constructed answer. One private decoder belongs to each parse call;
none is shared between calls/tasks.

`validateRawJSON(Data)` runs that same parser and discards the returned value.
It is useful for validation-only callers. Calling it before decodePayload is
unnecessary: decodePayload already contains the full raw gate.

`decodeInput(payload:)` performs the existing closed scheduler envelope,
operation/item/plan/proof parsing and rejects nonfinite values in any opaque
subtree. It does not execute a candidate or permit output. An already-created
AST cannot prove original bytes lacked duplicate keys or invalid encoding; use
decodePayload on the original bytes when that evidence matters. No skip flag or
caller assertion of previous validation exists.

The original `decodeInput(Data)` retains the original SchedulerJSONGuard →
JSONDecoder<ScenarioPayload> order and original errors, then delegates to the
same closed semantic body. Existing clients keep their semantics. New strict
raw failures may have different details from the legacy Data decoder because
those are distinct layers; no catch-success fallback washes a rejected token
into an accepted value.

## Numeric and Unicode fidelity

Swift Double(String) and NSNumber.doubleValue are not interchangeable with the
legacy decoder. Nonzero underflow may become zero; extreme zero exponents may
be rejected; ordinary decimals can move one ULP. For example the original token
`-0.004144001900805731` must retain Double bits `0xbf70f94d0a376351`.
`-0` retains its sign, `0e-4000`/`-0e-4000` remain accepted, and `1e-400` and
`2.4703282292062327e-324` remain rejected. Normal subnormals and canonical UInt64
decimal strings retain their bytes. These rules come from the same exact token
String/Double decoders as legacy input, not an independently inferred number
policy.

Typed equality alone does not prove fidelity: Swift equality can equate signed
zero and canonically equivalent strings. Migration must compare complete
encodeInput bytes, numeric bitPattern and string UTF8. Canonically equivalent
*object keys* are rejected before a dictionary could erase their multiplicity;
a standalone ScenarioPayload Codable probe that lacks the raw guard is not the
legacy guarded Data entry.

## Required host migration proof

A host can replace raw→Foundation→NSNumber→AST conversion with
`decodePayload(raw)`, then call the shared semantic parser. Preserve original raw
bytes, all strict persisted-read checks, every native output comparison and the
independent current/cold reducer state. Do not seed the candidate from native
results or substitute a checksum for full comparison.

Before adopting, compare every preserved original CI raw input to the actual old
49ad Data implementation: full acceptance/rejection and canonical encodeInput
bytes, with finite numeric bits and UTF8 intact. Keep invalid/raw error details
separate from semantic schema errors. Current Kit tests include all13operation
kinds, scalar/Unicode/size/depth/grammar/duplicate boundaries, the ordinary ULP
regression and1024seeded finite doubles. Isolated actual parser mutations that
conflate booleans/numbers, erase negative zero, normalize Unicode or bypass the
raw gate must fail the same assertions.

The local synthetic codec benchmark and unit oracle establish API correctness
and codec-phase measurements only. They do not establish host full-archive
performance, host equivalence, actual scheduling policy adoption or a CI budget.
Each owner must retain its complete same-input archive proof and verify exact
remote-SHA CI before advancing a managed lock.
