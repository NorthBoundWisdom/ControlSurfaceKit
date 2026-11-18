# New-device paper exercise and minimal adapter evidence

## X-Touch One paper exercise

Behringer describes one touch-sensitive motor fader, a push encoder, an LCD,
jog/shuttle control and transport/control buttons, with MC/HUI/MIDI compatibility.
This exercise documents a proposed adapter using offline evidence.
[Behringer X-Touch One](https://behringer.com/en/products/0808-AAG)

| Device knowledge to provide | Neutral declaration |
| --- | --- |
| Fader position and contact reports | Stable element ID, absolute input and contact-began/contact-ended capability; real observation facts with captured origin |
| Push encoder | Relative/absolute input as established by mode documentation; separate press/release role |
| Keys and transport keys | Button IDs and press/release capabilities. Business action names are supplied by host binding, not by this package |
| Key lights | Explicit display capabilities and effect payload encoding in adapter |
| LCD | Describe the documented text display capability and verify firmware character and rendering limits |
| Jog/shuttle | Input kind and units established by protocol documentation, not guessed from the physical control |
| MC/HUI/MIDI modes | Opaque mode IDs with mode-specific elements and effect side-effect declarations; capability declaration never changes device mode |
| Motor output | Mechanism direction and explicit affected elements. Remote display-only service output vocabulary must exclude it |

Reusable **principles** from the Compact adapter include contact ownership,
conservative handling when contact continuity is unknown, generation invalidation,
explicit local recall, and revalidation before any mechanism output. Their
Compact implementation is device-specific and is not moved to this kernel or
turned into optional switches. One must independently establish this device's
contact reporting, reconnect behavior, mode/layer side effects and motor protocol.

Use One-specific documentation and attended checks to verify the documented
encodings, relative units and resolution, LED and LCD rendering, mode-switch
effects, contact continuity, startup behavior, acknowledgments, readback, echo
and output ordering. The paper exercise used offline evidence only.

## Actual J3/J4 integration work for a new adapter

Provide input-role bindings as `ContextBinding(elementID, facetID, inputKind,
targetReferenceID)` or configuration-level `ControlBinding` when lookup is
independent of event kind. Keep complex targets in the caller configuration;
first-match lookup is shared. Provide explicit input/output IDs, transport
revision, connected state and native extra identity to `ConnectionSnapshot`.
Input epoch and mapping revision remain independent caller facts. Let the shared
`ContextResourceIndex` own pending/sent identity, while native payload stays in
one native owner; invalidation never invents observations or replays old plans.

Construct immutable `FeedbackPlan` values with complete captured native evidence,
source, origin, semantic scope, affected physical elements and full direction
union. Supply mandatory fresh native snapshot, explicit narrowed true grant and
mandatory native safety result. `FeedbackPreflight` performs actual admission;
a stage-only authorization sufficiency result is not a send permit. Keep this
device's real touch/layer/motor/pin gate at final native transmission. Actual
receipts distinguish not-attempted/rejected/accepted; current-scope eligibility is
separate from successful transport. No new clock/UUID is needed for these APIs.
One cannot infer physical observed position/contact from an accepted motor send.

## Minimal hypothetical offline device evidence

The J2 translation-only example remains in
`Tests/ConformanceTests/MinimalDeviceAdapter.swift` with its original tests.
J5 now adds an independent [complete integration](j5-integration.md): **17 complete
applicable scenarios, 35 applicable operations and 50 original assertions**, plus
13 real failing regression controls. Thirteen whole scenarios and only T25's
motor-continuity step are physically NA. The fixture and original assertions are
unchanged. No real device was connected or qualified.

Protocol/physical/receiver code is124 lines, plus67 explicit device/fixture wiring
lines (191 total); complete caller composition and authority infrastructure are
measured separately. The input-only knob and output-only lamp are different
physical roles. Logical axis display→lamp projection never gives the knob display
capability or makes T03's same-control independent-I/O feature applicable.
Current Kit performs real binding, route/resource invalidation, plan/preflight and
receipt logic; actual SP owns its session/actions/journal; the isolated production
authority bridge remains the only business-value/permission/history owner. That
provider's old Kit is separately pinned and never stands in for current Kit.
This proves the test composition boundary; final neutral production placement of
platform parameter authority remains outside this extraction.

## Proposed scheduling policy for One

Use the manufacturer's standard MIDI mode with Note messages for buttons as the
paper profile. It documents fader position separately from contact, and distinct
outputs for button LEDs, the encoder ring, the meter, and the LCD. The LCD
message carries the color, inversion flags and both seven-character halves.
Model each configured protocol mode as a distinct profile and invalidate the
previous scope when the mode changes. Validate the chosen mode and transport
against the actual firmware and endpoint before enabling hardware output.
[Behringer MIDI Mode Implementation](https://cdn-media.empowertribe.com/efc4402433c646579eea4d4811077c5c/Document_BE_X-TOUCH-ONE-MIDI-Mode-Implementation.pdf)

Use `FeedbackRequestState` for request equality and permission withdrawal.

| Operation | Shared policy | Adapter obligations |
| --- | --- | --- |
| Repaint button LEDs, encoder ring, meter or LCD | Use `FeedbackQueue` keyed by stable display target and current semantic scope. Keep the latest pending value at the key's original FIFO position. Use `suppressAfterAcceptedReceipt` and `discard`. | Compare normalized wire payload and current scope. If the latest desired value already matches the accepted value, cancel any older pending repaint of that target. Recheck grant, scope and endpoint before sending. Record acceptance only when all writes in the ordered logical plan succeed and the receipt still matches the current scope. Invalidate the target cache after partial or uncertain delivery so a later explicit repaint can proceed. |
| Synchronous display write with a receipt promised for each call | Use `proposeEveryRequest` and `discard`. Evaluate each call separately from the coalescing repaint queue. | Recheck authorization and pin on every call, including repeats of the same payload. Each call gets its own native admission and transport result, with a refusal or not-attempted result when its checks fail. |
| Explicit local motor-fader recall | Use `proposeEveryRequest` and `discard` on the local request path. | Verify local operator intent, fresh current-generation released-contact evidence, current mode, any device context required for that mode, and the final endpoint pin. Refuse if any of these are unknown or invalid. Startup, disconnect, reconnect and shutdown emit no motor commands. The remote display vocabulary contains only display effects and excludes the fader, mode and layer changes. |
| Permission withdrawal, mode change, disconnect and reconnect | Start with `discard` for all paths. On withdrawal cancel the affected queued keys and clear their request caches. On mode or connection change clear queue and request state and start a fresh generation. | Identify the actual permission or lifecycle change and its affected targets. Revalidate scope before crediting any in-flight completion. A new grant requires a fresh request, and reconnect restores no prior intent. Keep unavailable position or contact evidence unknown. |

Transport acceptance is sent evidence. Position, contact and rendered state
require their own observations. Verify mode behavior, touch continuity, echo,
readback, lifecycle side effects and endpoint identity through One-specific
protocol tests and attended qualification. The adapter supplies those facts,
encodes payloads and executes native sends. The [shared scheduler](scheduling-runtime.md)
owns ordered enqueue, replacement, bucket, cooldown and invalidation.

The hardware rate, burst and cooldown remain unqualified. Keep the live output
configuration pending a verified transport budget for the chosen mode and
endpoint. An offline fake transport can use `.bucket(perSecond: 2, burst: 2,
failureCooldown: 1)` with injected time to demonstrate FIFO, same-key replacement,
rate limiting and a one-second cooldown. Also exercise partial delivery, stale
receipts, cancellation of an obsolete repaint, withdrawal and reconnect clearing.
A drained repaint spends a token before the send attempt. On an actual failure,
record the supplied failure instant to set the cooldown. Another attempt requires
a later explicit input from the caller. The minimal offline device composition
uses this same queue for deferred plans and invalidation. Its original scenario
assertions provide shared software evidence.
