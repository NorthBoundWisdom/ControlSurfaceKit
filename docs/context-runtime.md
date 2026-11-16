# Binding and connection runtime

J3 provides synchronous Sendable values. There are no device effects, clocks,
callbacks, parameter values, senders or observations in these reducers.

## What a new adapter provides

1. Stable physical-role `elementID`, opaque logical `facetID`, `InputKind` and an
   opaque `targetReferenceID` resolving the existing immutable configuration.
   Build `ContextBinding` entries in the native lookup order. `BindingContext`
   builds the lookup index once; the first matching entry wins. Device validation
   runs before this bridge. No action payload or parameter definition is copied.
   For a configuration-level control lookup that does not depend on an input
   role, use `ControlBinding(elementID:facetID:targetReferenceID:)` and
   `BindingContext(context:controlEntries:)`, then `targetForControl`. This
   separate index declares no event capability. Never attach a fabricated
   InputKind to a configuration merely to obtain a lookup key. Role-specific
   entries and control-level entries can coexist through
   `BindingContext(context:entries:controlEntries:)`; each preserves its own
   first-match order, and neither lookup falls back to the other.
2. A stable lifecycle `DeviceContext`, with input epoch and mapping revision
   preserved as separate identities. `BindingContextState.apply` reports context
   and binding changes and keeps the exact supplied identity; it never mints one.
   Per-input facets and newly observed physical context are not lifecycle scope.
3. Current selected input ID, output ID, optional transport generation and
   connectivity for `ConnectionSnapshot<Extra>`. All four common fields are
   mandatory constructor arguments and participate in transition decisions.
   An unknown ID remains nil. `Extra` contains additional native route identity
   components, or `EmptyConnectionIdentity` when there are none. Full captured
   provenance remains recorded separately and validated by the actual transport.
4. Stable resource IDs and captured scope for `ContextResourceIndex<ID, Scope>`.
   It owns the actual pending/cache-validity identity inventory; do not retain a
   second native order array or ID set. Typed payloads remain in their sole native
   dictionary, removed using IDs returned by the index. Contact ownership and
   actual observations are device policy and do not belong in this index.

## Exact behavior

`ConnectionState.apply` compares input/output IDs, transport generation and Extra
for `routeChanged`; connectivity is reported separately as `statusChanged`.
Either invalidates lifecycle scope. `clearPending` is true on a changed route or
disconnected snapshot; `becameAvailable` is true on a connected new route or
transition from disconnected. Adapters retain their existing callback boundary:
one which previously ignored an unchanged callback still ignores it.

On invalidation, a supplied transport generation becomes the connection
generation; otherwise fallback advances with the existing unsigned wrapping
semantics. An unchanged snapshot preserves the current generation. This number
does not replace the input epoch or mapping revision. The transition contains
old and new snapshots and generations so adapters can independently compare it.
It never authorizes an automatic send, restores an old plan or invents evidence.

`ContextScope.matches` is exact across source, every DeviceContext field and
every captured endpoint field, including nil. Use stable lifecycle context here;
do not include a per-input observation as though it were a global binding epoch.
An unknown route matching another unknown route is only a bookkeeping equality;
the actual transport still requires its trustworthy current pin before sending.
Use the current canonical scope after synchronous I/O, never a candidate copied
before callbacks that might rebind, reconnect or mutate the canonical owner.

The resource index preserves original insertion order when replacing an ID.
Removing and reinserting it appends it. `removeFirst` returns the exact removed
IDs, supports counts beyond the inventory size, and rejects negative counts
without mutation. `removeAll` and `invalidate(current:)` return exact IDs in
registration order. Optional scope remains optional and is not filled from a
current route. An unordered native pending inventory may continue exposing its
original sorted facts and consuming IDs in actual input-event order; index order
is not a new device dispatch policy.

Logical invalidity and physical removal are different. A captured old scope is
immediately rejected by scope admission, while its pending ID can remain visible
until the existing clear/drain boundary. The index does not eagerly remove work
on every binding change. Conversely, explicit repeated context or attachment
operations may remove resources even when `BindingContextState.apply(equal)`
reports no change. Preserve those explicit operations.

## Native policies and extraction proof

Connection-name/provenance changes are part of one existing transport's identity
and absent from another's identity. Their Extra values preserve these predicates;
this is not a safety switch. Scope, full provenance and raw outputs remain fully
compared in host shadow traces.

Device encoding, requested physical context, contact continuity, mechanism
permissions, layer mismatch, observation freshness, transactions, echo policy,
queue rate limits and feedback payloads remain native. Their final send gates
still run. Generic resource cancellation never clears safety evidence or turns a
transport receipt into a physical observation.

Before adoption, independently execute the old owner and the candidate. Compare
binding results, transition facts, every scope field, exact canceled/pending IDs,
cache validity, observations and complete ordered outputs, then run all applicable
shared scenarios and existing full suites. Both owners' golden sequences must
remain byte identical. A shared index seeded with the native expected answer is
not a shadow proof. Local unit tests alone are not host adoption evidence.
