# J-2 neutral contract mapping and adapter boundaries

These are immutable fact/plan types, not a new runtime or authority. Device types
remain in their adapters. The tables cover fields in the proposal's contract
files, plus the endpoint and monitor facts added in J-0. Host integration adds its
own exact bridge/source references; no table row means host adoption has occurred.

## Common destination vocabulary

- `EndpointProvenance`: optional opaque endpoint/device IDs, a connection
  generation, independent transport origin. A missing ID stays nil even when an
  origin is known. Neither an ID, a name nor an origin grants qualification.
- `DeviceContext`: opaque identifier, interpretation/binding generation, optional
  mapping content revision. The kernel does not decode physical layers or pages.
- `DeviceInputEvent`: element ID, input kind, unquantized value, context, endpoint,
  simulation/hardware source, finite caller-supplied monotonic time.
- `DeviceObservation`: target, optional value, unknown/observed/expired status,
  evidence kind, context/endpoint/source/time. Sent evidence is a different type.
- `EffectDescriptor`: effect/target IDs, affected elements, actual payload,
  classification, side-effect union, context/endpoint/source/timing/time. Required
  directions are calculated as primary direction union side effects.
- `TransmissionEvidence`: effect/target IDs, context/endpoint/source/time and
  actual transport acceptance/rejection. It cannot manufacture an observation.
- `DeviceCapabilities` → opaque protocol modes → physical element declarations
  → structured input/display/effect capabilities. Counts, addresses and codecs
  remain device knowledge. This vocabulary does not grant permissions.

## BCR adapter field map

| Existing type and every field/case | Destination or adapter reason |
| --- | --- |
| `DeviceSource.mock`, `.hardware` | `DeviceSource.simulation`, `.hardware`; no origin-based inference |
| `HardwareOutputPolicy.observe/write` | Adapter/runtime output policy; no kernel override flag |
| `MIDIControlKind.controlChange/note/nrpn` | Adapter decoding/encoding only; projected semantic input kind does not expose wire kind |
| `MIDIControlID.kind/channel/number` | All remain adapter address identity. Adapter maps complete identity to opaque `elementID`; no channel/number in kernel |
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
| `.ignored/origin/delivery/endpoint` | Real decision/reason goes to shadow trace; writer origin stays runtime; delivery becomes transport evidence without promoting sent to observed; endpoint projects captured provenance |

## X-Touch Compact adapter field map

| Existing type and every field/case | Destination or adapter reason |
| --- | --- |
| `MIDIMessage.controlChange(channel,number,value)` | address remains adapter; decoded value projects `DeviceValue.number` |
| `.noteOn/.noteOff(channel,number,velocity)` | address/light encoding remain adapter; decoded press/release/value cross neutral boundary |
| `.programChange(channel,number)`, `.pitchBend(channel,value)` | Device management/motion interpretation remains adapter, including all safety and side-effect declarations; kernel contains no encoder for these |
| computed `.description/.midi1Bytes` | Formatting/codec remain adapter |
| `CompactLayer.a/b` | Adapter maps observed layer into opaque context ID; unknown layer remains unknown rather than a default layer |
| `CompactControl.fader/faderTouch/encoder/encoderPush/button(index)`, `.expression/.footswitch` | All index/count/layout knowledge stays adapter; each becomes a stable opaque element ID |
| `CompactInput.control/layer/value/isPressed` | stable element ID / context ID / unquantized number / press-release or contact role after device-specific interpretation |
| `ButtonLight.off/on/blink`, `RingStyle`, `RingDisplay` cases with position | Display payload vocabulary remains adapter; effect payload is explicit value or opaque text, effect kind declared in capabilities |
| `ButtonLightProtocol.manual/observed114` and `.velocity` | Firmware/protocol distinction and encoding stay adapter; no kernel branch |
| `CompactError` associated channel/index/position/value data | All device validation/errors stay adapter; real accept/reject reason is preserved in shadow trace |
| `CompactGeometry.faderCount/encoderCount/buttonCount/totalInputActions` | All counts remain adapter, absent from kernel |
| `CompactHardwareConfiguration.transmitChannel/receiveChannel/lightProtocol` | All device settings remain adapter. Selected mode enters capabilities only as opaque mode ID |
| computed `.profile` (control descriptors/ranges/capabilities) | Existing consumer contract remains SurfacePlugins authority; adapter bridges device facts, no copied profile/session implementation |
| `HardwareDisplayMessage.buttonLight(button,light)/ringDisplay(encoder,value)/ringStyle(encoder,style)` | Each maps to neutral display effect/target/payload; actual address encoder remains adapter. Closed hardware-service vocabulary still cannot express motion or context management |
| `CompactMIDIEndpoint.id/name/provenance/qualification` | id stringifies into opaque endpointID unless unknown; name stays diagnostic; provenance projects; unverified qualification stays adapter and never upgrades from naming |
| `CompactEndpointStamp.endpoint/generation` | optional captured endpoint and `connectionGeneration`; no current-route backfill |
| `CompactMIDIInputEnvelope.messages/origin` | decode messages into neutral input, preserving original origin stamp |
| `CompactMIDIConnection.generation/inputs/outputs/connectedInput/connectedOutput/error/isConnected` | route generation projects captured stamp; inventory/selection/error/connection lifecycle ownership stay adapter |
| `MonitorEvent.id/timestamp/direction/source/message/control` | UUID/wall time stay diagnostic; direction/source selects neutral record; message/control stays decoder input |
| `.hostLayer/deviceLayer` | Adapter interprets both; neutral context never equates inferred and observed layer |
| `.delivery/ignored` | actual transport evidence / actual decision with reason; not a new rule |
| `.text/connection/nonMotorTest/endpointOrigin` | wording/connection diagnostics/device-specific audit remain adapter; captured endpoint origin projects |

## Stepwise shadow contract

`ShadowSample` records each operation's actual decision/reason, all context and
endpoint identity/generation facts, ordered pending/revoked queue item IDs,
observations, full feedback descriptors with payload, transport outcomes and
opaque transport sequence. The comparator checks all fields with exact equality.
Array order and duplicate revocation multiplicity are retained; a missing step
is a difference. Empty lists are correct only when the real path has no entries.

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
