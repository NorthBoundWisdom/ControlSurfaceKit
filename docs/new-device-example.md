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

## Minimal hypothetical test adapter

`Tests/ConformanceTests/MinimalDeviceAdapter.swift` contains only a knob, a button,
a lamp, their capabilities and stateless packet↔contract translations. It owns no
parameter values, authorization, context/connection reducer, queue or journal.
Its tests translate three real T01 fixture operations to/from neutral values and
check identities, payloads and display-only encoding. They do **not** execute the
T01 parameter assertions or claim a passing shared scenario.

Current evidence is **three translated contract steps; zero complete shared
scenarios**. Generic runtime ownership/authorization/journal/context machinery
has not yet been extracted. Full T01–T30 execution with only this device knowledge
cannot honestly be claimed at J-2. Motor/context/preset-specific scenarios will
need real physical-feature applicability assessment; generic runtime scenarios
are pending implementation, not physically not-applicable. No ideal fixture
reducer was added to make them pass. This limitation is recorded for the next
extraction stages instead of rewriting the fixture or weakening assertions.

No kernel change was required for this adapter: device facts alone fit the J-2
contract. This establishes the vocabulary boundary only, not the complete
"new device writes only device knowledge" runtime acceptance standard.
