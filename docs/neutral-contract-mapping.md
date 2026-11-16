# J-2 neutral contract mapping and adapter boundaries

These are immutable fact/plan types, not a new runtime or authority. Device types
remain in their adapters. The tables cover fields in the proposal's contract
files, plus the endpoint and monitor facts added in J-0. Host integration adds its
own exact bridge/source references; no table row means host adoption has occurred.
The C adapter owner read and accepted its Models/connection/monitor field inventory
and supplied the headless endpoint/event rows below during J-2.

## Common destination vocabulary

- `EndpointProvenance`: optional opaque endpoint/device IDs, a connection
  generation, independent transport origin. A missing ID stays nil even when an
  origin is known. Neither an ID, a name nor an origin grants qualification.
- `DeviceContext`: opaque identifier, interpretation/binding generation, optional
  mapping content revision. It preserves the adapter's evidenced interpretation
  facet and hardware-context knowledge separately; UI selection does not prove a
  hardware group or layer. The kernel does not decode these facets.
- `DeviceInputEvent`: stable physical actuation-role ID, input kind, unquantized value, context, endpoint,
  simulation/hardware source, finite caller-supplied monotonic time.
- `DeviceObservation`: target, optional value, unknown/observed/expired status,
  evidence kind, context/endpoint/source/time. Sent evidence is a different type.
- `EffectDescriptor`: effect/target IDs, affected elements, actual payload,
  classification, side-effect union, context/endpoint/source/timing/time. A target
  may identify a logical display/binding facet; affected elements retain physical
  role identities. Required directions are primary direction union side effects.
- `TransmissionEvidence`: effect/target IDs, context/endpoint/source/time and
  actual transport acceptance/rejection. It cannot manufacture an observation.
- `DeviceCapabilities` → opaque protocol modes → physical element declarations
  → structured input/display/effect capabilities. Counts, addresses and codecs
  remain device knowledge. Modes mean actual protocol modes, not groups, layers
  or software banks. This vocabulary does not grant permissions.

## J-2 identity and facet integration ruling

A neutral `elementID` identifies a stable physical actuation role. The same role
on the same physical control keeps that ID across group, layer and software-bank
changes; turning and pressing one control may have distinct role IDs. Preserve
real physical row/position distinctions, but do not copy a logical row that only
encodes a group into a second physical identity. In particular, a BCR top-row
`BCRControlID(section,row,index)` row can identify a group facet, not another
physical rotary. Compact A/B and software bank similarly do not create new
physical input controls.

The existing published `control_id` continues to identify its logical binding or
display target. It is not renamed or collapsed. The device adapter owns the map
from physical role plus interpretation facet to those logical targets.
`EffectDescriptor.targetID` may remain facet-qualified, while
`affectedElements` names the physical roles actually affected. Context captures
the interpretation facet and any separately evidenced hardware context; an
unknown hardware group/layer stays unknown even when the UI selects a facet.
This is an opaque adapter encoding, not a new kernel context reducer.

One actual protocol mode aggregates each physical role once in
`ProtocolModeCapability.elements`, with the union of its supported input/display/
effect kinds across facets. Groups, A/B layers and software banks must not be
invented as protocol modes. Facet-to-logical-target mapping, learned addressing,
and device-specific safety remain in the adapter.

Observation target/attribute IDs also distinguish facts: for example,
`input.position` and `input.relative-delta` are different attributes scoped to a
physical role and its captured context. A relative input reports a delta, not an
absolute position. Preserve unknown/expired absolute-position evidence; do not
fill it with that delta, a default, an accumulated estimate or a sent display
value. The adapter may expose the delta as its own fact, without promoting it to
position evidence.

These are J-2 rules for the unpublished neutral projection only. Source/API and
legacy bindings, published IDs, send order and safety behavior are unchanged by
this documentation. Host adoption and exact source pins are recorded in the
supervisor's workspace review. J-3 context/connection algorithms have not begun.

## BCR adapter field map

| Existing type and every field/case | Destination or adapter reason |
| --- | --- |
| `DeviceSource.mock`, `.hardware` | `DeviceSource.simulation`, `.hardware`; no origin-based inference |
| `HardwareOutputPolicy.observe/write` | Adapter/runtime output policy; no kernel override flag |
| `MIDIControlKind.controlChange/note/nrpn` | Adapter decoding/encoding only; projected semantic input kind does not expose wire kind |
| `MIDIControlID.kind/channel/number` | All remain adapter address identity. Adapter resolves the complete address and facet into a stable physical actuation-role `elementID`; logical target/facet stays separate; no channel/number in kernel |
| `MIDIVoiceMessage.nrpn(channel,number,value)` | channel/number remain adapter; complete `dataValue` may project to `DeviceValue.number`, never the rounded seven-bit presentation value |
| `.controlChange(channel,number,value)` | address stays adapter, decoded value projects unquantized |
| `.noteOn/.noteOff(channel,number,velocity)` | address/encoding stays adapter, decoded role becomes press/release and value preserves real fact |
| message computed `controlID/value/dataValue/maximumDataValue/isPositiveActivation/diagnosticDescription/midi1Bytes` | Full protocol computation stays adapter; only its explicit decoded fact crosses boundary. No duplicate codec or value conversion in kernel |
| `MIDI1UMPCodec` (no stored fields), `MIDIEncodingError` cases | Wire parsing, packing, limits and errors stay adapter |
| `NRPNAssembler.channels`, `Selection.msb/lsb/dataMSB/date` | Multi-message protocol assembly and expiry stay adapter; caller projects completed input only |
| `MIDIConnectionSnapshot.sourceEndpoints/destinationEndpoints` | Discovery/selection inventory stays adapter; captured chosen route only projects endpoint provenance |
| `.transportGeneration` | Captured `connectionGeneration` when known; unknown does not silently become current |
| `.connectedSourceID/connectedDestinationID` | Corresponding input/output opaque `endpointID`, independently captured |
| `.sourceNames/destinationNames/connectedSource/connectedDestination` | Display/selection strings stay adapter; never used as qualification evidence |
| `.lastError` and computed `.isConnected/.hasSameRoute` | Transport diagnostics and route-selection semantics stay adapter; no callback owner in kernel |
| `SurfaceDevice.connection/onMessages/onConnection/send` | Entire I/O/callback interface stays adapter. Decoded callbacks export `DeviceInputEvent`; successful send exports `TransmissionEvidence` |
| `MockSurfaceDevice.model/connection/onMessages/onConnection` | Mock protocol state and callback ownership stay adapter; mock source is explicit simulation, never physical evidence |
| `SurfaceInputBatch.messages/endpoint` | Messages stay decoder; each resulting event carries projected captured endpoint |
| `MIDIEndpointSource.endpointID/deviceID/connectionGeneration/provenance` | Matching `EndpointProvenance` fields (`provenance` → `transportOrigin`); unknown sentinel becomes nil, never fabricated ID |
| `MIDIEndpointDescriptor.id/name/availabilityKnown/provenance` | chosen id/origin may project; name and availability/selection remain adapter facts |
| `MIDIEndpointSelection.version/sourceID/destinationID` | Persistence and explicit endpoint selection stay adapter |
| `MonitorEvent.id/time/monotonicTime` | Diagnostic event ID/wall time stay adapter; only actual finite monotonic time supplies `at` |
| `.direction/source/message/control` | direction selects input/observation/transmission record; explicit source projects; message/control decoded by adapter |
| `.ignored/origin/delivery/endpoint` | Real decision/reason goes to shadow trace; writer origin stays runtime; only actual I/O delivery becomes transport evidence; pre-I/O suppression remains a decision; endpoint projects captured provenance |

The adapter-owner-reviewed expanded per-field inventory is in
[bcr-adapter-field-map.md](bcr-adapter-field-map.md).

## X-Touch Compact adapter field map

| Existing type and every field/case | Destination or adapter reason |
| --- | --- |
| `MIDIMessage.controlChange(channel,number,value)` | address remains adapter; decoded value projects `DeviceValue.number` |
| `.noteOn/.noteOff(channel,number,velocity)` | address/light encoding remain adapter; decoded press/release/value cross neutral boundary |
| `.programChange(channel,number)`, `.pitchBend(channel,value)` | Device management/motion interpretation remains adapter, including all safety and side-effect declarations; kernel contains no encoder for these |
| computed `.description/.midi1Bytes` | Formatting/codec remain adapter |
| `CompactLayer.a/b` | Adapter maps observed layer into opaque context ID; unknown layer remains unknown rather than a default layer |
| `CompactControl.fader/faderTouch/encoder/encoderPush/button(index)`, `.expression/.footswitch` | Layout stays adapter; each physical actuation role gets a stable ID across A/B and bank facets; rotation, push and contact may be distinct roles |
| `CompactInput.control/layer/value/isPressed` | physical actuation-role ID / evidenced context facet / unquantized number / press-release or contact role; relative delta never supplies absolute-position observation |
| `ButtonLight.off/on/blink`, `RingStyle`, `RingDisplay` cases with position | Display payload vocabulary remains adapter; effect payload is explicit value or opaque text, effect kind declared in capabilities |
| `ButtonLightProtocol.manual/observed114` and `.velocity` | Firmware/protocol distinction and encoding stay adapter; no kernel branch |
| `CompactError` associated channel/index/position/value data | All device validation/errors stay adapter; real accept/reject reason is preserved in shadow trace |
| `CompactGeometry.faderCount/encoderCount/buttonCount/totalInputActions` | All counts remain adapter, absent from kernel |
| `CompactHardwareConfiguration.transmitChannel/receiveChannel/lightProtocol` | All device settings remain adapter. An actual protocol mode enters capabilities as an opaque mode ID; A/B and software banks do not become modes |
| computed `.profile` (control descriptors/ranges/capabilities) | Existing consumer contract remains SurfacePlugins authority; adapter bridges device facts, no copied profile/session implementation |
| `HardwareDisplayMessage.buttonLight(button,light)/ringDisplay(encoder,value)/ringStyle(encoder,style)` | Each maps to display effect/payload with a possibly facet-qualified target and stable physical-role affectedElements; actual address encoder remains adapter. Closed hardware-service vocabulary still cannot express motion or context management |
| `CompactMIDIEndpoint.id/name/provenance/qualification` | id stringifies into opaque endpointID unless unknown; name stays diagnostic; provenance projects; unverified qualification stays adapter and never upgrades from naming |
| `CompactEndpointStamp.endpoint/generation` | optional captured endpoint and `connectionGeneration`; no current-route backfill |
| `CompactMIDIInputEnvelope.messages/origin` | decode messages into neutral input, preserving original origin stamp |
| `CompactMIDIConnection.generation/inputs/outputs/connectedInput/connectedOutput/error/isConnected` | route generation projects captured stamp; inventory/selection/error/connection lifecycle ownership stay adapter |
| `HardwareEndpointOrigin.inputID/outputID` | Independent input/output `EndpointProvenance.endpointID` projections, nil remains nil |
| `.connectionGeneration/transportOrigin` | Exact generation and explicit declared origin; unknown remains unknown and does not infer a device ID |
| `HardwareMIDIEvent.link(connected,origin)` | Lifecycle fact with captured endpoint; no neutral input or output is invented |
| `.message(message,origin)` | Device decoder produces input facts with the original endpoint stamp |
| `.undecoded(origin)` | Adapter-visible rejection/diagnostic, never a fabricated input value |
| `HardwareMIDI.currentOrigin` | Adapter route pin only, not a source to backfill old events |
| `.send(HardwareDisplayMessage,expectedOrigin)` | Immutable display target/payload and captured endpoint; actual transport result becomes evidence, not observation |
| `MonitorEvent.id/timestamp/direction/source/message/control` | UUID/wall time stay diagnostic; direction/source selects neutral record; message/control stays decoder input |
| `.hostLayer/deviceLayer` | Adapter interprets both; neutral context never equates inferred and observed layer |
| `.delivery/ignored` | actual I/O result becomes transport evidence; pre-I/O suppression and ignored input remain decisions with reasons |
| `.text/connection/nonMotorTest/endpointOrigin` | wording/connection diagnostics/device-specific audit remain adapter; captured endpoint origin projects |

## Stepwise shadow contract

`ShadowSample` records each operation's actual decision/reason, all context and
endpoint identity/generation facts, ordered pending/revoked queue item IDs,
observations, full feedback descriptors with payload, transport outcomes and
opaque transport sequence. The comparator checks all fields with exact equality.
Array order and duplicate revocation multiplicity are retained; a missing step
is a difference. Pre-I/O suppression has no transmission evidence; an actual
transport attempt is recorded separately from its accepted/rejected result. Empty
lists are correct only when the real path has no entries.

Hosts must capture both sides from the same input and supplied time, before any
mutation caused by the next step. Candidate contract projection must be decoded
back/compared against the original fact, not compared with an independently
constructed copy of itself. A host's old implementation still controls behavior
until zero differences across applicable scenarios, full suites and golden bytes
are reviewed. These types alone prove no binding/connection/feedback algorithm
has been extracted. J-3/J-4 reducers and algorithm shadow runs are not implemented.

The exact full-schema validator remains the migrated Python implementation. Swift
`ScenarioCatalog.decode(data:)` is a typed reader of caller-validated fixture
bytes; opaque setup/arguments are deliberately not a second semantics engine.
`AssertionEvaluator` is strict about missing data, numeric types, non-finite
values and exact relations. `ScenarioStepTrace` retains the original JSON trace
vocabulary; full report validation (including counts and closed fields) still
runs through the unchanged validator.
