# New-device paper exercise and minimal adapter evidence

## X-Touch One paper exercise

The [manufacturer's current product page](https://behringer.com/en/products/0808-AAG)
describes one touch-sensitive motor fader, a push encoder, an LCD, jog/shuttle
control and transport/control buttons, with MC/HUI/MIDI compatibility. This is a
paper mapping, not device qualification, a protocol implementation or a purchase.

| Device knowledge to provide | Neutral declaration |
| --- | --- |
| Fader position and contact reports | Stable element ID, absolute input and contact-began/contact-ended capability; real observation facts with captured origin |
| Push encoder | Relative/absolute input as established by mode documentation; separate press/release role |
| Keys and transport keys | Button IDs and press/release capabilities. Business action names are supplied by host binding, not by this package |
| Key lights | Explicit display capabilities and effect payload encoding in adapter |
| LCD | Text/number display capabilities supported by actual protocol; exact segmentation/limits need documentation |
| Jog/shuttle | Input kind and units established by protocol documentation, not guessed from the physical control |
| MC/HUI/MIDI modes | Opaque mode IDs with mode-specific elements and effect side-effect declarations; capability declaration never changes device mode |
| Motor output | Mechanism direction and explicit affected elements. Remote display-only service output vocabulary must exclude it |

Reusable **principles** from the Compact adapter include contact ownership,
conservative handling when contact continuity is unknown, generation invalidation,
explicit local recall, and revalidation before any mechanism output. Their
Compact implementation is device-specific and is not moved to this kernel or
turned into optional switches. One must independently establish this device's
contact reporting, reconnect behavior, mode/layer side effects and motor protocol.

The following need device documentation or attended acquisition: message
addresses and encodings; relative units and resolution; direction independence;
LCD format; LED behavior; mode-switch procedure and side effects; contact press/
release continuity; motor motion on connection/mode change; acknowledgments,
readback and echo behavior; safe output ordering. None is inferred from Compact.
No hardware was connected, no mode/preset changed and no motion command sent.

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

For One, exact packet addresses, LCD segmentation, native mode selection, touch
continuity, reconnect/motor behavior and all final safety policy still need its
own verified documentation and attended acquisition. The official product page
links MIDI Mode implementation material, but this paper exercise does not claim
unread protocol details or infer them from Compact. Shared offline results do not
replace One-specific protocol tests and physical qualification.
